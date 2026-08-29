import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'barcode_scanner_screen.dart';

class AdminReceiving extends StatelessWidget {
  const AdminReceiving({super.key});
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFF7F8FA),
      body: AdminReceivingBody(),
    );
  }
}

class AdminReceivingBody extends StatefulWidget {
  final String searchQuery;
  const AdminReceivingBody({super.key, this.searchQuery = ''});
  @override
  State<AdminReceivingBody> createState() => AdminReceivingBodyState();
}

class AdminReceivingBodyState extends State<AdminReceivingBody>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  static const _red   = Color(0xFFE8001C);
  static const _amber = Color(0xFFd69e2e);
  static const _green = Color(0xFF38a169);
  static const _months = [
    'Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec',
  ];

  String _filter = 'all';

  // Stream subscription — subscribed once in initState, never recreated
  List<Map<String, dynamic>> _deliveries = [];
  bool _loading = true;
  StreamSubscription<QuerySnapshot>? _sub;

  bool _fabOpen = false;

  @override
  void initState() {
    super.initState();
    _sub = FirebaseFirestore.instance
        .collection('deliveries')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snap) {
      if (mounted) {
        setState(() {
          _deliveries = snap.docs
              .map((d) => {...d.data(), 'id': d.id})
              .where((d) => d['archived'] != true)
              .toList();
          _loading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  String _fmt(String? d) {
    if (d == null || d.isEmpty) return '—';
    final dt = DateTime.tryParse(d);
    if (dt != null) return '${_months[dt.month - 1]} ${dt.day}, ${dt.year}';
    return d;
  }

  /// Formats a Firestore Timestamp or ISO string to a readable date.
  /// Used for Order Date (createdAt) which is stored as a Timestamp.
  String _fmtOrderDate(dynamic raw) {
    if (raw == null) return '—';
    DateTime? dt;
    if (raw is Timestamp) {
      dt = raw.toDate();
    } else if (raw is String && raw.isNotEmpty) {
      dt = DateTime.tryParse(raw);
    } else if (raw is Map && raw['seconds'] != null) {
      dt = DateTime.fromMillisecondsSinceEpoch((raw['seconds'] as int) * 1000);
    }
    if (dt == null) return '—';
    return '${_months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'Pending':               return const Color(0xFF718096);
      case 'For Admin Review':      return _red;
      case 'Awaiting Double Check': return _amber;
      case 'Approved':              return _green;
      case 'Rejected':              return _red;
      default:                      return const Color(0xFF718096);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // Apply search filter
    final q = widget.searchQuery.toLowerCase();
    final searched = q.isEmpty
        ? _deliveries
        : _deliveries.where((d) {
            final sup  = (d['supplier'] as String? ?? '').toLowerCase();
            final note = (d['notes']    as String? ?? '').toLowerCase();
            final rcv  = (d['receivedBy'] as String? ?? '').toLowerCase();
            final items = (d['items'] as List? ?? []);
            final itemMatch = items.any((i) =>
              (i['itemName'] as String? ?? '').toLowerCase().contains(q) ||
              (i['itemNum']  as String? ?? '').toLowerCase().contains(q));
            return sup.contains(q) || note.contains(q) || rcv.contains(q) || itemMatch;
          }).toList();

    // Count by status
    // Count by per-item status
    int pending = 0, awaiting = 0, approved = 0, rejected = 0, forReview = 0;
    for (final d in _deliveries) {
      final deliveryStatus = d['status'] as String? ?? 'Pending';
      final items = (d['items'] as List? ?? []);
      for (final item in items) {
        final st = (item as Map)['itemStatus'] as String? ?? deliveryStatus;
        switch (st) {
          case 'Pending':               pending++; break;
          case 'For Admin Review':      forReview++; break;
          case 'Awaiting Double Check': awaiting++; break;
          case 'Approved':              approved++; break;
          case 'Rejected':              rejected++; break;
        }
      }
    }

    final filtered = _filter == 'all'
        ? searched
        : searched.where((d) {
            final deliveryStatus = d['status'] as String? ?? 'Pending';
            final items = (d['items'] as List? ?? []);
            if (items.isEmpty) return deliveryStatus == _filter;
            return items.any((item) {
              final st = (item as Map)['itemStatus'] as String? ?? deliveryStatus;
              return st == _filter;
            });
          }).toList();

    return Stack(children: [
      // ── Main list area ──
      Column(children: [
        // Filter chips
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _chip('Pending',  '$pending',   const Color(0xFF718096), Icons.inventory_outlined,      'Pending'),
              const SizedBox(width: 6),
              _chip('Review',   '$forReview', _red, Icons.rate_review_outlined,    'For Admin Review'),
              const SizedBox(width: 6),
              _chip('Awaiting\nReview', '$awaiting',  _amber,  Icons.hourglass_empty_outlined, 'Awaiting Double Check'),
              const SizedBox(width: 6),
              _chip('Approved', '$approved',  _green,  Icons.check_circle_outline,     'Approved'),
              const SizedBox(width: 6),
              _chip('Rejected', '$rejected',  _red,    Icons.cancel_outlined,          'Rejected'),
            ]),
          ),
        ),
        // List body - per item
        Expanded(
          child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Builder(builder: (_) {
                // Flatten deliveries into individual items
                final flatItems = <Map<String, dynamic>>[];
                for (final d in filtered) {
                  final items = (d['items'] as List? ?? []);
                  for (int idx = 0; idx < items.length; idx++) {
                    final item = Map<String, dynamic>.from(items[idx] as Map);
                    // Skip items that don't match the active per-item filter
                    if (_filter != 'all') {
                      final deliveryStatus = d['status'] as String? ?? 'Pending';
                      final itemSt = (item['itemStatus'] as String?) ?? deliveryStatus;
                      if (itemSt != _filter) continue;
                    }
                    flatItems.add({...item, '_delivery': d, '_itemIdx': idx});
                  }
                  if (items.isEmpty) flatItems.add({'_delivery': d, '_itemIdx': -1});
                }
                if (flatItems.isEmpty) return const Center(child: Text('No items found.', style: TextStyle(color: Color(0xFF718096))));
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: flatItems.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final fi = flatItems[i];
                    final d = fi['_delivery'] as Map<String, dynamic>;
                    final itemIdx = fi['_itemIdx'] as int;
                    return GestureDetector(
                      onTap: () => _showItemViewModal(d, itemIdx),
                      child: _itemCard(fi, d),
                    );
                  },
                );
              }),
        ),
      ]),
      // ── Backdrop ──
      if (_fabOpen)
        Positioned.fill(
          child: GestureDetector(
            onTap: () => setState(() => _fabOpen = false),
            child: Container(color: Colors.transparent),
          ),
        ),
      // ── Speed-dial FAB ──
      Positioned(
        bottom: 16, right: 16,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (_fabOpen) ...[
              _fabAction(
                label: 'Review Purchase Order',
                icon: Icons.edit_outlined,
                onTap: () {
                  setState(() => _fabOpen = false);
                  final pendingDeliveries = _deliveries.where((d) => (d['status'] as String? ?? '') == 'For Admin Review').toList();
                  if (pendingDeliveries.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('No purchase orders for admin review found.'),
                      backgroundColor: Color(0xFF718096), behavior: SnackBarBehavior.floating));
                  } else {
                    _showEditPOPicker(pendingDeliveries);
                  }
                },
              ),
              const SizedBox(height: 10),
              _fabAction(
                label: 'Scan Item',
                icon: Icons.qr_code_scanner,
                onTap: _scanAndFind,
              ),
              const SizedBox(height: 10),
              _fabAction(
                label: 'Create Purchase Order (PO)',
                icon: Icons.add_box_outlined,
                onTap: () { setState(() => _fabOpen = false); _showNewDeliveryModal(); },
              ),
              const SizedBox(height: 10),
            ],
            GestureDetector(
              onTap: () => setState(() => _fabOpen = !_fabOpen),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 56, height: 56,
                decoration: BoxDecoration(
                  color: _red, shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: _red.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 4))],
                ),
                child: AnimatedRotation(
                  turns: _fabOpen ? 0.125 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.add, color: Colors.white, size: 28),
                ),
              ),
            ),
          ],
        ),
      ),
    ]);
  }

  // ── Scan & find pending delivery ────────────────────────────
  Future<void> _scanAndFind() async {
    setState(() => _fabOpen = false);
    final result = await Navigator.push<String>(
      context, MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()));
    if (!mounted || result == null || result.isEmpty) return;

    final query = result.trim().toLowerCase();
    String resolvedNum = '', resolvedName = '';
    try {
      var snap = await FirebaseFirestore.instance
          .collection('item_master').where('barcode', isEqualTo: result.trim()).limit(1).get();
      if (snap.docs.isEmpty) snap = await FirebaseFirestore.instance
          .collection('item_master').where('qr', isEqualTo: result.trim()).limit(1).get();
      if (snap.docs.isEmpty) snap = await FirebaseFirestore.instance
          .collection('item_master').where('num', isEqualTo: result.trim().toUpperCase()).limit(1).get();
      if (snap.docs.isNotEmpty) {
        final d = snap.docs.first.data();
        resolvedNum  = (d['num']  as String? ?? '').toLowerCase();
        resolvedName = (d['name'] as String? ?? '').toLowerCase();
      }
    } catch (_) {}
    if (!mounted) return;

    final pending = _deliveries.where((d) => (d['status'] as String? ?? '') == 'Pending').toList();
    Map<String, dynamic>? found;
    int foundItemIdx = -1;
    for (final delivery in pending) {
      final items = (delivery['items'] as List? ?? []);
      for (int idx = 0; idx < items.length; idx++) {
        final i = items[idx];
        final num  = (i['itemNum']  as String? ?? '').toLowerCase();
        final name = (i['itemName'] as String? ?? '').toLowerCase();
        final match = (resolvedNum.isNotEmpty  && num.contains(resolvedNum)) ||
                      (resolvedName.isNotEmpty && name.contains(resolvedName)) ||
                      num.contains(query) || name.contains(query);
        if (match) {
          found = delivery;
          foundItemIdx = idx;
          break;
        }
      }
      if (found != null) break;
    }
    if (!mounted) return;
    if (found != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Item found in PO from ${found['supplier'] ?? ''}'),
        backgroundColor: _green, behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
      _showReceiveModal(found, itemIdx: foundItemIdx >= 0 ? foundItemIdx : null);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No pending PO found for that item'),
        backgroundColor: Color(0xFF718096), behavior: SnackBarBehavior.floating));
    }
  }

  Widget _fabAction({required String label, required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1a202c))),
        ),
        const SizedBox(width: 10),
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: Colors.white, shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Icon(icon, color: _red, size: 20),
        ),
      ]),
    );
  }

  Widget _chip(String label, String value, Color color, IconData icon, String filter) {
    final active = _filter == filter;
    return GestureDetector(
      onTap: () => setState(() => _filter = active ? 'all' : filter),
      child: Container(
        width: 72,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: active ? color : Colors.transparent, width: 1.5),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
        ),
        child: Column(children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 14),
          ),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: const TextStyle(fontSize: 8, color: Color(0xFF718096)), textAlign: TextAlign.center),
        ]),
      ),
    );
  }

  Widget _itemCard(Map<String, dynamic> item, Map<String, dynamic> d) {
    final itemSt = item['itemStatus'] as String? ?? d['status'] as String? ?? 'Pending';
    final color = _statusColor(itemSt);
    final name = item['itemName'] as String? ?? '—';
    final uom = item['uom'] as String? ?? '';
    final supplierCode = item['supplierCode'] as String? ?? '';
    final qty = item['expectedQty'] as int? ?? 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF0F4F8)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: RichText(text: TextSpan(
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF1a202c), height: 1.3),
            children: [
              TextSpan(text: name),
              if (uom.isNotEmpty)
                TextSpan(text: '  ($uom)', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w400, color: Color(0xFF718096))),
            ],
          ))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
            child: Text(itemSt == 'Awaiting Double Check' ? 'Awaiting Review' : itemSt, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: color)),
          ),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          if (supplierCode.isNotEmpty) ...[
            Text(supplierCode, style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
            const SizedBox(width: 8),
          ],
          Text('Qty: $qty', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF4a5568))),
          const Spacer(),
          const Icon(Icons.chevron_right, size: 16, color: Color(0xFFa0aec0)),
        ]),
      ]),
    );
  }

  // ── Item View Modal (per-item) — website-matching design ──
  void _showItemViewModal(Map<String, dynamic> d, int itemIdx) async {
    if (itemIdx < 0) { _showViewModal(d); return; }
    final items = (d['items'] as List? ?? []);
    if (itemIdx >= items.length) return;
    final item = Map<String, dynamic>.from(items[itemIdx] as Map);
    final itemSt = item['itemStatus'] as String? ?? d['status'] as String? ?? 'Pending';
    final name = item['itemName'] as String? ?? '—';
    final uom = item['uom'] as String? ?? '';
    final qty = item['expectedQty'] as int? ?? 0;
    final supplierCode = item['supplierCode'] as String? ?? '';
    final actual = item['actualQty'] as int?;
    final cond = item['condition'] as String? ?? '—';
    final remark = item['remark'] as String? ?? '';

    // Fetch stock and cost for this item
    // Use stockAtReceive (frozen at receive time) if available, else fetch live stock
    int? currentStock = item['stockAtReceive'] as int?;
    double unitCost = 0;
    final itemNum = item['itemNum'] as String? ?? '';
    if (itemNum.isNotEmpty) {
      if (currentStock == null) {
        try {
          final stockSnap = await FirebaseFirestore.instance
              .collection('stock_inventory').where('num', isEqualTo: itemNum).limit(1).get();
          if (stockSnap.docs.isNotEmpty) currentStock = (stockSnap.docs.first['stock'] as num?)?.toInt() ?? 0;
        } catch (_) {}
      }
      try {
        final masterSnap = await FirebaseFirestore.instance
            .collection('item_master').where('num', isEqualTo: itemNum).limit(1).get();
        if (masterSnap.docs.isNotEmpty) unitCost = double.tryParse(
          (masterSnap.docs.first['cost']?.toString() ?? '0').replaceAll('₱', '').replaceAll(',', '').trim()) ?? 0;
      } catch (_) {}
    }
    if (!mounted) return;
    final subtotal = unitCost * qty;

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        expand: false, initialChildSize: 0.65, maxChildSize: 0.92,
        builder: (ctx2, ctrl) => SingleChildScrollView(
          controller: ctrl,
          child: Column(children: [
            // ── Red header with item name + supplier code ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFFE31E24), Color(0xFFC41E3A)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('$name${uom.isNotEmpty ? '  ($uom)' : ''}',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, height: 1.3)),
                  if (supplierCode.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(supplierCode, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ])),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => Navigator.pop(ctx2),
                  child: Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
                    child: const Icon(Icons.close, color: Colors.white, size: 18),
                  ),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // ── 2x2 Info grid ──
                Row(children: [
                  Expanded(child: _ivInfoCard('ORDER QUANTITY', '$qty')),
                  const SizedBox(width: 10),
                  if (currentStock != null) Expanded(child: _ivInfoCard('CURRENT STOCK', '$currentStock'))
                  else const Expanded(child: SizedBox.shrink()),
                ]),
                if (unitCost > 0) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: _ivInfoCard('UNIT PRICE', _fmtPeso(unitCost))),
                    const SizedBox(width: 10),
                    Expanded(child: _ivInfoCard('SUBTOTAL', _fmtPeso(subtotal), valueColor: _red)),
                  ]),
                ],
                // ── Receiving details (if received) ──
                if (actual != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity, padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFe2e8f0), width: 1.5)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('RECEIVING DETAILS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF4a5568), letterSpacing: 0.5)),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Actual Qty', style: TextStyle(fontSize: 10, color: Color(0xFFa0aec0), fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text('$actual', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                            color: cond == 'OK' ? _green : cond == 'Defective' ? _red : _amber)),
                        ])),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Condition', style: TextStyle(fontSize: 10, color: Color(0xFFa0aec0), fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: (cond == 'OK' ? _green : cond == 'Defective' ? _red : _amber).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20)),
                            child: Text(cond, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                              color: cond == 'OK' ? _green : cond == 'Defective' ? _red : _amber)),
                          ),
                        ])),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Difference', style: TextStyle(fontSize: 10, color: Color(0xFFa0aec0), fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(actual - qty == 0 ? '0' : '${actual - qty > 0 ? '+' : ''}${actual - qty}',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                              color: actual - qty == 0 ? _green : actual - qty < 0 ? _red : _amber)),
                        ])),
                      ]),
                      if (remark.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity, padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(8)),
                          child: Text('Remarks: $remark', style: const TextStyle(fontSize: 11, color: Color(0xFF92400E))),
                        ),
                      ],
                    ]),
                  ),
                ],
                // ── Delivery info (only show if not pending) ──
                if (itemSt != 'Pending') ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity, padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFe2e8f0), width: 1.5)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('DELIVERY INFO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF4a5568), letterSpacing: 0.5)),
                      const SizedBox(height: 10),
                      if (_fmtOrderDate(d['createdAt']) != '—')
                        _ivInfoRow('Order Date', _fmtOrderDate(d['createdAt'])),
                      if ((item['receivedAt'] as String? ?? (d['receivedAt'] is String ? d['receivedAt'] as String : '')).isNotEmpty)
                        _ivInfoRow('Received Date', _fmt(item['receivedAt'] as String? ?? (d['receivedAt'] is String ? d['receivedAt'] as String : ''))),
                      if ((d['receivedBy'] as String? ?? '').isNotEmpty)
                        _ivInfoRow('Received By', d['receivedBy'] as String),
                      if ((d['checkedBy'] as String? ?? '').isNotEmpty)
                        _ivInfoRow('Checked By', d['checkedBy'] as String),
                      if ((d['reviewNotes'] as String? ?? '').isNotEmpty)
                        _ivInfoRow('Review Notes', d['reviewNotes'] as String),
                    ]),
                  ),
                ],
                const SizedBox(height: 20),
                // ── Action buttons ──
                if (d['status'] == 'For Admin Review') ...[
                  Row(children: [
                    Expanded(child: OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx2);
                        _rejectAdminReviewItem(d, itemIdx);
                      },
                      icon: const Icon(Icons.cancel_outlined, size: 14, color: Colors.red),
                      label: const Text('Reject', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red), padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
                    )),
                    const SizedBox(width: 10),
                    Expanded(flex: 2, child: ElevatedButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx2);
                        _approveAdminReviewItem(d, itemIdx);
                      },
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: const Text('Approve Request', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)), elevation: 4),
                    )),
                  ]),
                ] else if (itemSt == 'Pending') ...[
                  SizedBox(width: double.infinity, child: ElevatedButton.icon(
                    onPressed: () { Navigator.pop(ctx2); _showReceiveModal(d, itemIdx: itemIdx); },
                    icon: const Icon(Icons.download_outlined, size: 16),
                    label: const Text('Receive Item', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)), elevation: 4),
                  )),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: OutlinedButton.icon(
                      onPressed: () async {
                        final maxQty = (item['_maxQty'] as num?)?.toInt() ?? qty;
                        final newQty = await _showEditQtyDialog(qty, maxQty: maxQty);
                        if (newQty == null || newQty == qty) return;
                        final updatedItems = List<Map<String, dynamic>>.from(items.map((i) => Map<String, dynamic>.from(i as Map)));
                        updatedItems[itemIdx] = {...updatedItems[itemIdx], 'expectedQty': newQty};
                        await FirebaseFirestore.instance.collection('deliveries').doc(d['id'] as String).update({'items': updatedItems});
                        if (mounted) { Navigator.pop(ctx2); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Quantity updated!'), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating)); }
                      },
                      icon: const Icon(Icons.edit_outlined, size: 14),
                      label: const Text('Edit Qty', style: TextStyle(fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
                    )),
                    const SizedBox(width: 8),
                    Expanded(child: OutlinedButton.icon(
                      onPressed: () { Navigator.pop(ctx2); _archiveItemFromDelivery(d, itemIdx); },
                      icon: const Icon(Icons.archive_outlined, size: 14, color: Colors.red),
                      label: const Text('Archive', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red), padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
                    )),
                  ]),
                ] else if (itemSt == 'Awaiting Double Check') ...[
                  SizedBox(width: double.infinity, child: ElevatedButton.icon(
                    onPressed: () { Navigator.pop(ctx2); _showReviewModal(d, itemIdx: itemIdx); },
                    icon: const Icon(Icons.fact_check_outlined, size: 16),
                    label: const Text('Review & Verify', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(backgroundColor: _amber, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)), elevation: 4),
                  )),
                ] else if (itemSt == 'Approved') ...[
                  Container(
                    width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 15),
                    decoration: BoxDecoration(color: _green.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(30), border: Border.all(color: _green.withValues(alpha: 0.3), width: 1.5)),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.check_circle_outline, size: 16, color: _green),
                      const SizedBox(width: 6),
                      Text('Approved', style: TextStyle(fontSize: 14, color: _green, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ] else if (itemSt == 'Rejected') ...[
                  Container(
                    width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 15),
                    decoration: BoxDecoration(color: _red.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(30), border: Border.all(color: _red.withValues(alpha: 0.3), width: 1.5)),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.cancel_outlined, size: 16, color: _red),
                      const SizedBox(width: 6),
                      Text('Rejected', style: TextStyle(fontSize: 14, color: _red, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  // Info card for 2x2 grid (matches website)
  Widget _ivInfoCard(String label, String value, {Color? valueColor}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFe2e8f0)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFFa0aec0), fontWeight: FontWeight.w700, letterSpacing: 0.3)),
      const SizedBox(height: 4),
      Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: valueColor ?? const Color(0xFF1a202c))),
    ]),
  );

  // Info row for delivery info section
  Widget _ivInfoRow(String label, String value) => Container(
    padding: const EdgeInsets.symmetric(vertical: 6),
    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F4F8)))),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF718096))),
      Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1a202c))),
    ]),
  );

  Future<int?> _showEditQtyDialog(int currentQty, {int? maxQty}) async {
    final max = maxQty ?? currentQty;
    final ctrl = TextEditingController(text: '$currentQty');
    return showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Edit Order Quantity', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Max allowed: $max', style: const TextStyle(fontSize: 12, color: Color(0xFF718096))),
          const SizedBox(height: 10),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: 'Quantity',
              helperText: 'Enter 1 – $max',
            ),
            onChanged: (val) {
              final v = int.tryParse(val);
              if (v != null && v > max) {
                ctrl.text = '$max';
                ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
              }
            },
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final v = int.tryParse(ctrl.text) ?? 0;
              if (v <= 0) return;
              if (v > max) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Quantity cannot exceed $max.'),
                  backgroundColor: Colors.red,
                  behavior: SnackBarBehavior.floating,
                ));
                return;
              }
              Navigator.pop(context, v);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _archiveItemFromDelivery(Map<String, dynamic> d, int itemIdx) async {
    final items = d['items'] as List? ?? [];
    final item = items.isNotEmpty && itemIdx < items.length ? items[itemIdx] as Map : <String, dynamic>{};
    final itemName = item['itemName'] as String? ?? 'this item';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.archive_outlined, color: Colors.red, size: 22),
          SizedBox(width: 8),
          Text('Archive Item', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
        content: Text(
          'Are you sure you want to archive "$itemName"?',
          style: const TextStyle(fontSize: 14, color: Color(0xFF4a5568)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF718096))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Yes, Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await FirebaseFirestore.instance.collection('deliveries').doc(d['id'] as String).update({
      'archived': true,
      'archivedAt': FieldValue.serverTimestamp(),
    });
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Item "$itemName" archived successfully!'),
      backgroundColor: Colors.green, behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
  }

  void _confirmArchive(Map<String, dynamic> d) async {
    final supplier = d['supplier'] as String? ?? 'this delivery';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.archive_outlined, color: Colors.red, size: 22),
          SizedBox(width: 8),
          Text('Archive Delivery', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
        content: Text(
          'Are you sure you want to archive the delivery from "$supplier"?',
          style: const TextStyle(fontSize: 14, color: Color(0xFF4a5568)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF718096))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Yes, Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await FirebaseFirestore.instance.collection('deliveries').doc(d['id'] as String).update({
      'archived': true,
      'archivedAt': FieldValue.serverTimestamp(),
    });
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Purchase order archived successfully!'),
      backgroundColor: Colors.green, behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
  }

  // ── View Delivery Modal ─────────────────────────────────────
  void _showViewModal(Map<String, dynamic> d) async {
    final status = d['status'] as String? ?? 'Pending';
    final color  = _statusColor(status);
    List<Map<String, dynamic>> items = List<Map<String, dynamic>>.from(
      (d['items'] as List? ?? []).map((i) => Map<String, dynamic>.from(i as Map)));

    // Fetch unit cost from item_master + current stock from stock_inventory (best-effort)
    if (status == 'Pending' || status == 'Awaiting Double Check' || status == 'For Admin Review') {
      try {
        final masterSnap = await FirebaseFirestore.instance
            .collection('item_master').get();
        final numToCost = <String, double>{};
        final numToGroup = <String, String>{};
        for (final doc in masterSnap.docs) {
          final data = doc.data();
          final n = data['num'] as String? ?? '';
          final c = double.tryParse(
            (data['cost']?.toString() ?? '0')
                .replaceAll('₱', '').replaceAll(',', '').trim()) ?? 0;
          if (n.isNotEmpty) {
            numToCost[n] = c;
            numToGroup[n] = data['group'] as String? ?? '';
          }
        }
        // Fetch current stock for each item
        final numToStock = <String, int>{};
        final numToMin   = <String, int>{};
        try {
          final stockSnap = await FirebaseFirestore.instance
              .collection('stock_inventory').get();
          for (final doc in stockSnap.docs) {
            final data = doc.data();
            final n = data['num'] as String? ?? '';
            if (n.isNotEmpty) {
              numToStock[n] = (data['stock'] as num?)?.toInt() ?? 0;
              numToMin[n]   = (data['min']   as num?)?.toInt() ?? 0;
            }
          }
        } catch (_) {}
        items = items.map((item) {
          final n = item['itemNum'] as String? ?? '';
          return {
            ...item,
            '_cost':  numToCost[n]  ?? 0.0,
            '_group': numToGroup[n] ?? '',
            '_stock': numToStock[n],  // null if not found in stock_inventory
            '_min':   numToMin[n],    // null if not found
          };
        }).toList();
      } catch (_) {}
    }
    if (!mounted) return;

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => DraggableScrollableSheet(
        expand: false, initialChildSize: 0.6, maxChildSize: 0.92,
        builder: (_, ctrl) => SingleChildScrollView(
          controller: ctrl,
          child: Column(children: [
            // ── Colored header ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(d['supplier'] as String? ?? '—',
                    style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(_fmt(d['date'] as String?),
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20)),
                  child: Text(status, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close, color: Colors.white)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if ((d['notes'] as String? ?? '').isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFCD34D)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.sticky_note_2_outlined, size: 14, color: Color(0xFF92400E)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(d['notes'] as String,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF92400E)))),
                    ]),
                  ),
                  const SizedBox(height: 14),
                ],
                if ((d['receivedBy'] as String? ?? '').isNotEmpty)
                  _viewRow('Received By', d['receivedBy'] as String),
                if ((d['checkedBy'] as String? ?? '').isNotEmpty)
                  _viewRow('Checked By', d['checkedBy'] as String),
                if ((d['reviewNotes'] as String? ?? '').isNotEmpty)
                  _viewRow('Review Notes', d['reviewNotes'] as String),
                const SizedBox(height: 14),
                Text('Items (${items.length})',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1a202c))),
                const SizedBox(height: 8),
                ...items.map((item) {
                  final cond = item['condition'] as String? ?? '—';
                  final condColor = cond == 'OK' ? _green : cond == 'Defective' ? _red : _amber;
                  final actual = item['actualQty'];
                  final exp = item['expectedQty'] as int? ?? 0;
                  final diff = actual != null ? (actual as int) - exp : null;

                  // Approved: website-style 4-column grid (Expected/Actual/Condition/Remarks)
                  if (status == 'Approved') {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white, borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFe2e8f0)),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6)],
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(item['itemName'] as String? ?? '—',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF1a202c))),
                            Text(item['supplierCode'] as String? ?? '',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
                          ])),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: condColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                            child: Text(cond,
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: condColor)),
                          ),
                        ]),
                        const SizedBox(height: 10),
                        const Divider(height: 1, color: Color(0xFFF0F4F8)),
                        const SizedBox(height: 10),
                        Row(children: [
                          _gridCol('ORDER QTY', '$exp ${item['uom'] ?? ''}'),
                          _gridCol('ACTUAL RECEIVED',
                            actual != null
                              ? '$actual ${item['uom'] ?? ''}${diff != null && diff != 0 ? '  (${diff > 0 ? '+' : ''}$diff)' : ''}'
                              : '—',
                            valueColor: actual != null && diff != 0 ? (diff! < 0 ? _red : _amber) : condColor),
                          _gridCol('CONDITION', cond, valueColor: condColor),
                          _gridCol('REMARKS', (item['remark'] as String? ?? '').isEmpty ? '—' : item['remark'] as String),
                        ]),
                      ]),
                    );
                  }

                  // Other statuses: simple card
                  final itemCostVal = item['_cost'] is double ? item['_cost'] as double
                      : double.tryParse(item['_cost']?.toString() ?? '0') ?? 0.0;
                  final itemTotal   = itemCostVal * exp;
                  final itemGroup   = item['_group'] as String? ?? '';
                  final itemStock   = item['_stock'] as int?;
                  final itemMin     = item['_min']   as int? ?? 0;

                  // Badge: red = out of stock, amber = low stock, gray = ok
                  // (used inline in the stock badge below)
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFe2e8f0)),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                // Item name + UOM (left) + current stock badge (right)
                                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Expanded(
                                    child: RichText(text: TextSpan(
                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF1a202c)),
                                      children: [
                                        TextSpan(text: item['itemName'] as String? ?? '—'),
                                        if ((item['uom'] as String? ?? '').isNotEmpty)
                                          TextSpan(
                                            text: '  (${item['uom']})',
                                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w400, color: Color(0xFF718096))),
                                      ],
                                    )),
                                  ),
                                  if (itemStock != null) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: itemStock == 0
                                          ? const Color(0xFFfef2f2)
                                          : itemStock <= itemMin
                                            ? const Color(0xFFFFFBEB)
                                            : const Color(0xFFF0F4F8),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: itemStock == 0
                                            ? const Color(0xFFfca5a5)
                                            : itemStock <= itemMin
                                              ? const Color(0xFFFCD34D)
                                              : const Color(0xFFe2e8f0)),
                                      ),
                                      child: Text(
                                        'Stock: $itemStock',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: itemStock == 0
                                            ? const Color(0xFFe53e3e)
                                            : itemStock <= itemMin
                                              ? const Color(0xFFd69e2e)
                                              : const Color(0xFF718096),
                                        ),
                                      ),
                                    ),
                                  ],
                                ]),
                                const SizedBox(height: 3),
                                // Item number · group
                                Text(
                                  [item['itemNum'] as String? ?? '', if (itemGroup.isNotEmpty) itemGroup].join(' · '),
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
                                if (itemCostVal > 0) ...[
                                  const SizedBox(height: 10),
                                  const Divider(height: 1, color: Color(0xFFF0F4F8)),
                                  const SizedBox(height: 8),
                                  Row(children: [
                                    _miniStat('Price', _fmtPeso(itemCostVal), const Color(0xFF003087)),
                                    const SizedBox(width: 12),
                                    _miniStat('Qty', '$exp', const Color(0xFF1a202c)),
                                    const SizedBox(width: 12),
                                    _miniStat('Total', _fmtPeso(itemTotal), const Color(0xFFE8001C)),
                                  ]),
                                ] else ...[
                                  const SizedBox(height: 4),
                                  Text('Order Qty: $exp',
                                    style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
                                ],
                                if ((item['remark'] as String? ?? '').isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFFBEB),
                                      borderRadius: BorderRadius.circular(6)),
                                    child: Text(item['remark'] as String,
                                      style: const TextStyle(fontSize: 10, color: Color(0xFF92400E)))),
                                ],
                              ]),
                            ),
                          );
                }),
                const SizedBox(height: 16),
                if (status == 'Pending') ...[
                  Row(children: [
                    Expanded(child: OutlinedButton.icon(
                      onPressed: () { Navigator.pop(context); _showNewDeliveryModal(existing: d); },
                      icon: const Icon(Icons.edit_outlined, size: 15),
                      label: const Text('Edit'),
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: ElevatedButton.icon(
                      onPressed: () { Navigator.pop(context); _showReceiveModal(d); },
                      icon: const Icon(Icons.download_outlined, size: 15),
                      label: const Text('Receive Items'),
                      style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white),
                    )),
                  ]),
                  const SizedBox(height: 8),
                  SizedBox(width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () { Navigator.pop(context); _confirmArchive(d); },
                      icon: const Icon(Icons.archive_outlined, size: 15, color: Colors.red),
                      label: const Text('Archive', style: TextStyle(color: Colors.red)),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                    )),
                ] else if (status == 'For Admin Review') ...[
                  // Purple info banner
                  Container(
                    width: double.infinity, padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _red.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _red.withValues(alpha: 0.3))),
                    child: const Row(children: [
                      Icon(Icons.rate_review_outlined, size: 16, color: Color(0xFFE8001C)),
                      SizedBox(width: 8),
                      Expanded(child: Text('Staff delivery request — review before approving.',
                        style: TextStyle(fontSize: 12, color: Color(0xFFE8001C), fontWeight: FontWeight.w500))),
                    ])),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: OutlinedButton.icon(
                      onPressed: () { Navigator.pop(context); _confirmArchive(d); },
                      icon: const Icon(Icons.archive_outlined, size: 15, color: Colors.red),
                      label: const Text('Archive', style: TextStyle(color: Colors.red)),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                    )),
                    const SizedBox(width: 10),
                    Expanded(flex: 2, child: ElevatedButton.icon(
                      onPressed: () async {
                        Navigator.pop(context);
                        await FirebaseFirestore.instance.collection('deliveries').doc(d['id'] as String).update({'status': 'Pending'});
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Approved! Delivery is now Pending.'),
                          backgroundColor: Color(0xFF38a169), behavior: SnackBarBehavior.floating));
                      },
                      icon: const Icon(Icons.check_circle_outline, size: 15),
                      label: const Text('Approve Request'),
                      style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white),
                    )),
                  ]),
                ] else if (status == 'Awaiting Double Check') ...[
                  Row(children: [
                    Expanded(child: OutlinedButton.icon(
                      onPressed: () { Navigator.pop(context); _confirmArchive(d); },
                      icon: const Icon(Icons.archive_outlined, size: 15, color: Colors.red),
                      label: const Text('Archive', style: TextStyle(color: Colors.red)),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                    )),
                    const SizedBox(width: 10),
                    Expanded(flex: 2, child: ElevatedButton.icon(
                      onPressed: () { Navigator.pop(context); _showReviewModal(d); },
                      icon: const Icon(Icons.fact_check_outlined, size: 15),
                      label: const Text('Review & Verify'),
                      style: ElevatedButton.styleFrom(backgroundColor: _amber, foregroundColor: Colors.white),
                    )),
                  ]),
                ] else ...[
                  Row(children: [
                    Expanded(child: OutlinedButton.icon(
                      onPressed: () { Navigator.pop(context); _confirmArchive(d); },
                      icon: const Icon(Icons.archive_outlined, size: 15, color: Colors.red),
                      label: const Text('Archive', style: TextStyle(color: Colors.red)),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                    )),
                    if (status == 'Rejected') ...[
                      const SizedBox(width: 10),
                      Expanded(flex: 2, child: ElevatedButton.icon(
                        onPressed: () { Navigator.pop(context); _showReviewModal(d); },
                        icon: const Icon(Icons.visibility_outlined, size: 15),
                        label: const Text('View Details'),
                        style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white),
                      )),
                    ],
                  ]),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _miniStat(String label, String value, Color valueColor) => Expanded(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
        color: Color(0xFFa0aec0), letterSpacing: 0.4)),
      const SizedBox(height: 2),
      Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: valueColor)),
    ]),
  );

  Widget _viewRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 100, child: Text(label,
        style: const TextStyle(fontSize: 12, color: Color(0xFF718096), fontWeight: FontWeight.w500))),
      Expanded(child: Text(value,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1a202c)))),
    ]),
  );

  Widget _gridCol(String label, String value, {Color? valueColor}) => Expanded(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(
        fontSize: 9, fontWeight: FontWeight.w700,
        color: Color(0xFFa0aec0), letterSpacing: 0.4)),
      const SizedBox(height: 3),
      Text(value, style: TextStyle(
        fontSize: 12, fontWeight: FontWeight.w600,
        color: valueColor ?? const Color(0xFF1a202c))),
    ]),
  );

  // ── Edit PO Picker ──────────────────────────────────────────
  void _showEditPOPicker(List<Map<String, dynamic>> pendingDeliveries) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => DraggableScrollableSheet(
        expand: false, initialChildSize: 0.5, maxChildSize: 0.85,
        builder: (_, ctrl) => Column(children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            decoration: const BoxDecoration(
              color: Color(0xFF003087),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Row(children: [
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Review Purchase Order', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                Text('Select a pending PO to review', style: TextStyle(color: Colors.white70, fontSize: 11)),
              ])),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.close, color: Colors.white)),
            ]),
          ),
          // List
          Expanded(
            child: ListView.separated(
              controller: ctrl,
              padding: const EdgeInsets.all(16),
              itemCount: pendingDeliveries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final d = pendingDeliveries[i];
                final items = (d['items'] as List? ?? []);
                final createdAt = d['createdAt'];
                String dateStr = '—';
                if (createdAt is Timestamp) {
                  final dt = createdAt.toDate();
                  dateStr = '${_months[dt.month - 1]} ${dt.day}, ${dt.year}';
                }
                return GestureDetector(
                  onTap: () { Navigator.pop(context); _showNewDeliveryModal(existing: d); },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white, borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFe2e8f0)),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)]),
                    child: Row(children: [
                      Container(
                        width: 38, height: 38,
                        decoration: BoxDecoration(color: const Color(0xFFEBF4FF), borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.description_outlined, size: 18, color: Color(0xFF003087)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${items.length} item${items.length != 1 ? 's' : ''}',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF1a202c))),
                        const SizedBox(height: 2),
                        Text(dateStr, style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
                      ])),
                      const Icon(Icons.chevron_right, size: 18, color: Color(0xFFa0aec0)),
                    ]),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  // ── New / Edit Delivery Modal ──────────────────────────────
  void _showNewDeliveryModal({Map<String, dynamic>? existing}) {
    final isEdit = existing != null;

    List<Map<String, dynamic>> replenishItems = [];
    List<Map<String, dynamic>> addedItems = List<Map<String, dynamic>>.from(
      (existing?['items'] as List? ?? []).map((i) => Map<String, dynamic>.from(i as Map)),
    );
    final Map<int, TextEditingController> qtyCtrlrs = {};
    bool loadingItems = true;
    bool saving = false;
    Set<String> addedNums = addedItems
        .map((i) => i['itemNum'] as String? ?? '').toSet();

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) {
          // Load replenishment items once after modal opens
          if (loadingItems) {
            Future.microtask(() async {
              try {
                // Step 1: fetch stock inventory (always works)
                final stockSnap = await FirebaseFirestore.instance
                    .collection('stock_inventory').get();
                final numToStockData = <String, Map<String, int>>{};
                final needReplenish = <Map<String, dynamic>>[];
                for (final d in stockSnap.docs) {
                  final s = d.data();
                  final n = s['num'] as String? ?? '';
                  final stock = (s['stock'] as num?)?.toInt() ?? 0;
                  final min   = (s['min']   as num?)?.toInt() ?? 0;
                  final max   = (s['max']   as num?)?.toInt() ?? 0;
                  if (n.isNotEmpty) numToStockData[n] = {'stock': stock, 'min': min, 'max': max};
                  if (stock == 0 || stock <= min) needReplenish.add(s);
                }

                // Step 2: try fetching cost and supplierCode from item_master (optional, best-effort)
                final numToCost = <String, double>{};
                final numToSupplierCode = <String, String>{};
                final allMaterials = <Map<String, dynamic>>[];
                try {
                  final masterSnap = await FirebaseFirestore.instance
                      .collection('item_master').get();
                  for (final d in masterSnap.docs) {
                    final data = d.data();
                    final type = data['type'] as String? ?? '';
                    if (type != 'Material') continue;
                    final n = data['num'] as String? ?? '';
                    final rawCost = data['cost']?.toString() ?? '0';
                    final c = double.tryParse(
                      rawCost.replaceAll('₱', '').replaceAll(',', '').trim()) ?? 0;
                    final sc = data['supplierCode'] as String? ?? '';
                    if (n.isNotEmpty) {
                      numToCost[n] = c;
                      numToSupplierCode[n] = sc;
                    }
                    final sd = numToStockData[n];
                    allMaterials.add({
                      'num': n,
                      'name': data['name'] as String? ?? '',
                      'uom': data['uom'] as String? ?? '',
                      'supplierCode': sc,
                      '_cost': c,
                      '_stock': sd?['stock'] ?? 0,
                      '_minLevel': sd?['min'] ?? 0,
                      '_maxLevel': sd?['max'] ?? 0,
                    });
                  }
                } catch (_) {} // cost fetch failure is non-fatal

                // Collect item nums already in active (non-approved/rejected) deliveries
                final activeDeliveryNums = <String>{};
                for (final d in _deliveries) {
                  final st = d['status'] as String? ?? 'Pending';
                  if (st == 'Approved' || st == 'Rejected') continue;
                  if (isEdit && d['id'] == existing?['id']) continue;
                  for (final item in (d['items'] as List? ?? [])) {
                    final itemSt = (item as Map)['itemStatus'] as String? ?? st;
                    if (itemSt != 'Approved' && itemSt != 'Rejected') {
                      activeDeliveryNums.add(item['itemNum'] as String? ?? '');
                    }
                  }
                }

                final loaded = needReplenish.map((s) {
                  final n = s['num'] as String? ?? '';
                  return <String, dynamic>{
                    'num':       n,
                    'name':      s['name']  as String? ?? '',
                    'uom':       s['uom']   as String? ?? '',
                    'supplierCode': numToSupplierCode[n] ?? '',
                    '_stock':    (s['stock'] as num?)?.toInt() ?? 0,
                    '_minLevel': (s['min']   as num?)?.toInt() ?? 0,
                    '_maxLevel': (s['max']   as num?)?.toInt() ?? 0,
                    '_cost':     numToCost[n] ?? 0.0,
                  };
                }).where((m) => !activeDeliveryNums.contains(m['num'] as String? ?? '')).toList()
                  ..sort((a, b) {
                    if ((a['_stock'] as int) == 0 && (b['_stock'] as int) != 0) return -1;
                    if ((b['_stock'] as int) == 0 && (a['_stock'] as int) != 0) return 1;
                    return (a['name'] as String).compareTo(b['name'] as String);
                  });

                // Enrich pre-existing addedItems (from edit mode) with cost+stock
                if (addedItems.isNotEmpty) {
                  final enriched = <Map<String, dynamic>>[];
                  for (final item in addedItems) {
                    final n = item['itemNum'] as String? ?? '';
                    final c = numToCost[n] ?? 0.0;
                    int? stockVal;
                    try {
                      final ss = await FirebaseFirestore.instance
                          .collection('stock_inventory').where('num', isEqualTo: n).limit(1).get();
                      if (ss.docs.isNotEmpty) stockVal = (ss.docs.first['stock'] as num?)?.toInt();
                    } catch (_) {}
                    enriched.add({...item, '_cost': c, '_stock': stockVal, 'supplierCode': numToSupplierCode[n] ?? '', '_maxQty': (item['expectedQty'] as int?) ?? 1});
                  }
                  if (ctx.mounted) setModal(() => addedItems
                    ..clear()
                    ..addAll(enriched));
                }

                if (ctx.mounted) setModal(() { replenishItems = loaded; loadingItems = false; });
              } catch (e) {
                if (ctx.mounted) setModal(() { loadingItems = false; });
              }
            });
          }

          final visible = replenishItems.where((item) {
            final n = item['num'] as String? ?? '';
            return !addedNums.contains(n);
          }).toList();

          Widget statusBadge(int stock, int min) {
            if (stock == 0) return Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: const Color(0xFFfef2f2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFfca5a5))),
              child: const Text('Out of Stock',
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFFe53e3e))));
            if (stock <= min) return Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFFCD34D))),
              child: const Text('Low Stock',
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFFd69e2e))));
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: const Color(0xFFF0FFF4),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF9AE6B4))),
              child: const Text('In Stock',
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF38a169))));
          }

          return DraggableScrollableSheet(
            expand: false, initialChildSize: 0.92, maxChildSize: 1.0,
            builder: (_, ctrl) => Column(children: [
              // ── Header ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                decoration: const BoxDecoration(color: _red,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(isEdit ? 'Review Purchase Order (PO)' : 'Purchase Order (PO)',
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    const Text('Record incoming stock delivery',
                        style: TextStyle(color: Colors.white70, fontSize: 11)),
                  ])),
                  GestureDetector(onTap: () => Navigator.pop(ctx),
                      child: const Icon(Icons.close, color: Colors.white)),
                ]),
              ),
              Expanded(child: SingleChildScrollView(
                controller: ctrl,
                padding: EdgeInsets.only(
                  left: 20, right: 20, top: 20,
                  bottom: MediaQuery.viewInsetsOf(ctx).bottom + 24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(loadingItems ? 'Loading items…' : 'Items that need replenishment',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
                  const SizedBox(height: 8),
                  // Item cards
                  if (loadingItems)
                    const Center(child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: CircularProgressIndicator()))
                  else if (visible.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FFF4),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF9AE6B4))),
                      child: const Row(children: [
                        Icon(Icons.check_circle_outline, color: Color(0xFF38a169), size: 16),
                        SizedBox(width: 8),
                        Expanded(child: Text('All items are sufficiently stocked.',
                          style: TextStyle(fontSize: 12, color: Color(0xFF38a169), fontWeight: FontWeight.w600))),
                      ]))
                  else
                    Container(
                      constraints: const BoxConstraints(maxHeight: 260),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFe2e8f0)),
                        borderRadius: BorderRadius.circular(12)),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: visible.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFf0f4f8)),
                          itemBuilder: (_, i) {
                            final item   = visible[i];
                            final num    = item['num']       as String;
                            final name   = item['name']      as String;
                            final uom    = item['uom']       as String;
                            final supplierCode = item['supplierCode'] as String? ?? '';
                            final stock  = item['_stock']    as int;
                            final min    = item['_minLevel'] as int;
                            final max    = item['_maxLevel'] as int;
                            final cost   = item['_cost'] is double ? item['_cost'] as double : double.tryParse(item['_cost']?.toString() ?? '0') ?? 0.0;
                            final rec    = max > 0 ? (max - stock).clamp(0, 9999) : 1;
                            final added  = addedNums.contains(num);
                            return GestureDetector(
                              onTap: added ? null : () {
                                final rowIdx = addedItems.length;
                                qtyCtrlrs[rowIdx] = TextEditingController(text: '$rec');
                                setModal(() {
                                  addedItems.add({'itemNum': num, 'itemName': name,
                                    'uom': uom, 'expectedQty': rec, '_rowIdx': rowIdx,
                                    '_cost': cost, '_stock': stock, 'supplierCode': supplierCode, '_maxQty': rec});
                                  addedNums.add(num);
                                });
                              },
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 200),
                                opacity: added ? 0.35 : 1.0,
                                child: Container(
                                  color: added ? const Color(0xFFF7F8FA) : Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                                  child: Row(children: [
                                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      RichText(text: TextSpan(
                                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF1a202c)),
                                        children: [
                                          TextSpan(text: name),
                                          if (uom.isNotEmpty)
                                            TextSpan(text: '  ($uom)', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w400, color: Color(0xFF718096))),
                                        ],
                                      )),
                                      const SizedBox(height: 3),
                                      Wrap(spacing: 6, children: [
                                        if (supplierCode.isNotEmpty)
                                          Text(supplierCode, style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
                                        Text('Current: $stock', style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
                                        if (cost > 0)
                                          Text('${_fmtPeso(cost)}/unit', style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
                                        statusBadge(stock, min),
                                        if (rec > 0 && !added)
                                          Text('Suggest order: $rec', style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
                                      ]),
                                    ])),
                                    added
                                      ? const Icon(Icons.check_circle, size: 18, color: Color(0xFF38a169))
                                      : const Icon(Icons.add_circle_outline, size: 18, color: Color(0xFFE8001C)),
                                  ]),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  // Added items
                  if (addedItems.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('Items Added', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1a202c))),
                      Text('${addedItems.length} item${addedItems.length != 1 ? 's' : ''}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
                    ]),
                    const SizedBox(height: 8),
                    ...addedItems.asMap().entries.map((e) {
                      final rowIdx   = e.key;
                      final item     = e.value;
                      final itemCost = (item['_cost'] is double
                          ? item['_cost'] as double
                          : double.tryParse(item['_cost']?.toString() ?? '0') ?? 0.0);
                      final itemStock = item['_stock'] as int?;
                      final uom       = item['uom'] as String? ?? '';

                      qtyCtrlrs.putIfAbsent(rowIdx, () =>
                          TextEditingController(text: '${item['expectedQty'] ?? 1}'));
                      final qty      = int.tryParse(qtyCtrlrs[rowIdx]!.text) ?? (item['expectedQty'] as int? ?? 1);
                      final subtotal = itemCost * qty;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFe2e8f0), width: 1.2),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2)),
                            BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 2, offset: const Offset(0, 1)),
                          ],
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          // ── Header: name + remove ──
                          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Expanded(child: RichText(text: TextSpan(
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF1a202c), height: 1.3),
                              children: [
                                TextSpan(text: item['itemName'] as String? ?? ''),
                                if (uom.isNotEmpty)
                                  TextSpan(text: '  ($uom)', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w400, color: Color(0xFF718096))),
                              ],
                            ))),
                            const SizedBox(width: 10),
                            GestureDetector(
                              onTap: () {
                                final removedNum = addedItems[rowIdx]['itemNum'] as String? ?? '';
                                setModal(() {
                                  addedItems.removeAt(rowIdx);
                                  qtyCtrlrs.remove(rowIdx);
                                  addedNums.remove(removedNum);
                                });
                              },
                              child: Container(
                                width: 28, height: 28,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF2F2),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFFfecaca)),
                                ),
                                child: const Icon(Icons.close_rounded, size: 15, color: Color(0xFFe53e3e)),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 8),
                          // ── Meta info chips ──
                          Wrap(spacing: 8, runSpacing: 6, children: [
                            if ((item['supplierCode'] as String? ?? '').isNotEmpty)
                              _metaChip(item['supplierCode'] as String, Icons.qr_code, const Color(0xFF4a5568)),
                            if (itemCost > 0)
                              _metaChip('${_fmtPeso(itemCost)}', Icons.sell_outlined, const Color(0xFF003087)),
                            if (itemStock != null)
                              _metaChip('Stock: $itemStock', Icons.inventory_2_outlined,
                                itemStock == 0 ? const Color(0xFFe53e3e) : const Color(0xFF718096)),
                          ]),
                          const SizedBox(height: 12),
                          // ── Qty stepper row ──
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFe2e8f0)),
                            ),
                            child: Row(children: [
                              const Text('Order Quantity', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF4a5568))),
                              const Spacer(),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFFe2e8f0)),
                                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4)],
                                ),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  GestureDetector(
                                    onTap: () {
                                      final v = (int.tryParse(qtyCtrlrs[rowIdx]!.text) ?? 1);
                                      if (v <= 1) return;
                                      qtyCtrlrs[rowIdx]!.text = '${v - 1}';
                                      setModal(() => addedItems[rowIdx] = {...addedItems[rowIdx], 'expectedQty': v - 1});
                                    },
                                    child: Container(
                                      width: 34, height: 34,
                                      decoration: const BoxDecoration(
                                        borderRadius: BorderRadius.only(topLeft: Radius.circular(7), bottomLeft: Radius.circular(7))),
                                      child: const Icon(Icons.remove, size: 16, color: Color(0xFF718096)),
                                    ),
                                  ),
                                  Container(
                                    width: 48, height: 34,
                                    decoration: const BoxDecoration(
                                      border: Border.symmetric(vertical: BorderSide(color: Color(0xFFe2e8f0))),
                                    ),
                                    child: Center(
                                      child: TextField(
                                        controller: qtyCtrlrs[rowIdx],
                                        keyboardType: TextInputType.number,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1a202c)),
                                        decoration: const InputDecoration(
                                          border: InputBorder.none,
                                          isDense: true,
                                          contentPadding: EdgeInsets.zero,
                                        ),
                                        onChanged: (v) {
                                          final maxQ = (addedItems[rowIdx]['_maxQty'] as int?) ?? 9999;
                                          final q2 = (int.tryParse(v) ?? 1).clamp(1, maxQ);
                                          if (q2.toString() != v) qtyCtrlrs[rowIdx]!.text = '$q2';
                                          setModal(() => addedItems[rowIdx] = {...addedItems[rowIdx], 'expectedQty': q2});
                                        },
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () {
                                      final maxQ = (addedItems[rowIdx]['_maxQty'] as int?) ?? 9999;
                                      final v = (int.tryParse(qtyCtrlrs[rowIdx]!.text) ?? 1);
                                      if (v >= maxQ) return; // cap reached
                                      qtyCtrlrs[rowIdx]!.text = '${v + 1}';
                                      setModal(() => addedItems[rowIdx] = {...addedItems[rowIdx], 'expectedQty': v + 1});
                                    },
                                    child: Container(
                                      width: 34, height: 34,
                                      decoration: const BoxDecoration(
                                        borderRadius: BorderRadius.only(topRight: Radius.circular(7), bottomRight: Radius.circular(7))),
                                      child: Builder(builder: (ctx3) {
                                        final maxQ = (addedItems[rowIdx]['_maxQty'] as int?) ?? 9999;
                                        final cur = int.tryParse(qtyCtrlrs[rowIdx]!.text) ?? 1;
                                        final atMax = cur >= maxQ;
                                        return Icon(Icons.add, size: 16,
                                          color: atMax ? const Color(0xFFcbd5e0) : const Color(0xFFE8001C));
                                      }),
                                    ),
                                  ),
                                ]),
                              ),
                            ]),
                          ),
                          // ── Subtotal ──
                          if (itemCost > 0) ...[
                            const SizedBox(height: 10),
                            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                              const Text('Subtotal  ',
                                style: TextStyle(fontSize: 11, color: Color(0xFFa0aec0), fontWeight: FontWeight.w500)),
                              Text(_fmtPeso(subtotal),
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFFE8001C))),
                            ]),
                          ],
                        ]),
                      );
                    }),
                    // Grand total
                    Builder(builder: (_) {
                      final total = addedItems.fold<double>(0, (sum, i) {
                        final c = i['_cost'] is double ? i['_cost'] as double : double.tryParse(i['_cost']?.toString() ?? '0') ?? 0.0;
                        final q = i['expectedQty'] as int? ?? 1;
                        return sum + c * q;
                      });
                      if (total <= 0) return const SizedBox.shrink();
                      return Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFe2e8f0))),
                        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          const Text('Estimated Total',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF4a5568))),
                          Text(_fmtPeso(total),
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF1a202c))),
                        ]),
                      );
                    }),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(width: double.infinity, child: ElevatedButton(
                    onPressed: saving ? null : () async {
                      if (addedItems.isEmpty) return;
                      // Check for duplicate items in other active deliveries
                      final activeDeliveries = _deliveries.where((del) {
                        if (isEdit && del['id'] == existing['id']) return false;
                        final st = del['status'] as String? ?? 'Pending';
                        return st != 'Approved' && st != 'Rejected';
                      }).toList();
                      final duplicates = <String>[];
                      for (final item in addedItems) {
                        final num = item['itemNum'] as String? ?? '';
                        for (final del in activeDeliveries) {
                          final delItems = (del['items'] as List? ?? []);
                          if (delItems.any((i) => (i['itemNum'] as String? ?? '') == num)) {
                            duplicates.add(item['itemName'] as String? ?? '');
                            break;
                          }
                        }
                      }
                      if (duplicates.isNotEmpty) {
                        if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                          content: Text('Item already in an active delivery: ${duplicates.toSet().join(', ')}'),
                          backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));
                        return;
                      }
                      setModal(() => saving = true);
                      final items = addedItems.map((i) => {
                        'itemNum': i['itemNum'], 'itemName': i['itemName'],
                        'uom': i['uom'], 'expectedQty': i['expectedQty'],
                        'supplierCode': i['supplierCode'] ?? '',
                      }).toList();
                      final data = <String, dynamic>{'items': items};
                      try {
                        if (isEdit) {
                          // Approve: update items and set status to Pending
                          data['status'] = 'Pending';
                          await FirebaseFirestore.instance.collection('deliveries')
                              .doc(existing['id'] as String).update(data);
                        } else {
                          data['status'] = 'Pending';
                          data['createdAt'] = FieldValue.serverTimestamp();
                          await FirebaseFirestore.instance.collection('deliveries').add(data);
                        }
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(isEdit ? 'Purchase order approved! Status set to Pending.' : 'Purchase order created!'),
                            backgroundColor: Colors.green, behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
                        }
                      } catch (e) {
                        setModal(() => saving = false);
                        if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: saving
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(isEdit ? 'Approve' : 'Save'),
                  )),
                ]),
              )),
            ]),
          );
        },
      ),
    );
  }

  Widget _metaChip(String text, IconData icon, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withValues(alpha: 0.15)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 11, color: color),
      const SizedBox(width: 4),
      Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    ]),
  );

  Widget _field(String label, {required Widget child}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF4a5568))),
      const SizedBox(height: 4),
      child,
    ],
  );

  /// Formats a double as Philippine peso with commas e.g. ₱1,234.50
  String _fmtPeso(double v) {
    final parts = v.toStringAsFixed(2).split('.');
    final intPart = parts[0];
    final dec = parts[1];
    final buffer = StringBuffer();
    for (int i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buffer.write(',');
      buffer.write(intPart[i]);
    }
    return '₱$buffer.$dec';
  }

  /// Called externally (e.g. from AdminInventoryHub via GlobalKey) to open the receive modal directly.
  void openReceiveModal(Map<String, dynamic> delivery, {int? itemIdx}) => _showReceiveModal(delivery, itemIdx: itemIdx);

  // ── Receive Items Modal (Step 1) ───────────────────────────
  void _showReceiveModal(Map<String, dynamic> delivery, {int? itemIdx}) async {
    String currentUserName = '';
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      currentUserName = (doc.data()?['name'] as String?) ?? '';
    }
    if (!mounted) return;

    // If itemIdx not provided, find first pending item
    final allItems = List<Map<String, dynamic>>.from(
      (delivery['items'] as List? ?? []).map((i) => Map<String, dynamic>.from(i as Map)));
    int rcvIdx = itemIdx ?? allItems.indexWhere((i) => (i['itemStatus'] ?? 'Pending') == 'Pending');
    if (rcvIdx < 0) rcvIdx = 0;
    final item = allItems[rcvIdx];

    final receivedByCtrl = TextEditingController(text: currentUserName);
    final qtyCtrl = TextEditingController(text: '${item['expectedQty'] ?? 0}');
    String condition = 'OK';
    final remarkCtrl = TextEditingController();
    bool submitting = false;

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) => DraggableScrollableSheet(
          expand: false, initialChildSize: 0.85, maxChildSize: 0.97,
          builder: (_, ctrl) => SingleChildScrollView(
            controller: ctrl,
            child: Column(children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                decoration: const BoxDecoration(color: _red, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                child: Row(children: [
                  const Expanded(child: Text('Receive Item',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
                  GestureDetector(onTap: () => Navigator.pop(ctx), child: const Icon(Icons.close, color: Colors.white)),
                ]),
              ),
              Padding(
                padding: EdgeInsets.only(left: 20, right: 20, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _itemReceiveCard(
                    index: 0, item: item, expected: item['expectedQty'] as int? ?? 0,
                    qtyCtrl: qtyCtrl, remarkCtrl: remarkCtrl,
                    condition: condition,
                    onCondChange: (c) => setModal(() => condition = c),
                    onQtyChange: () => setModal(() {}),
                  ),
                  const SizedBox(height: 12),
                  _field('Received By', child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(color: const Color(0xFFF7F8FA), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFe2e8f0))),
                    child: Row(children: [
                      const Icon(Icons.person_outline, size: 16, color: Color(0xFF718096)),
                      const SizedBox(width: 8),
                      Text(receivedByCtrl.text.isNotEmpty ? receivedByCtrl.text : '—',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1a202c))),
                    ]),
                  )),
                  const SizedBox(height: 20),
                  SizedBox(width: double.infinity, child: ElevatedButton(
                    onPressed: submitting ? null : () async {
                      if (receivedByCtrl.text.trim().isEmpty) return;
                      setModal(() => submitting = true);
                      // Update only this specific item
                      final updatedItems = allItems.toList();
                      // Fetch current stock to freeze it at receive time
                      int? stockAtReceive;
                      try {
                        final sSnap = await FirebaseFirestore.instance.collection('stock_inventory').where('num', isEqualTo: item['itemNum'] ?? '').limit(1).get();
                        if (sSnap.docs.isNotEmpty) stockAtReceive = (sSnap.docs.first['stock'] as num?)?.toInt();
                      } catch (_) {}
                      updatedItems[rcvIdx] = {
                        ...updatedItems[rcvIdx],
                        'actualQty': int.tryParse(qtyCtrl.text) ?? item['expectedQty'],
                        'condition': condition,
                        'remark': remarkCtrl.text.trim(),
                        'itemStatus': 'Awaiting Double Check',
                        'receivedBy': receivedByCtrl.text.trim(),
                        'receivedAt': DateTime.now().toIso8601String(),
                        if (stockAtReceive != null) 'stockAtReceive': stockAtReceive,
                      };
                      final allReceived = updatedItems.every((i) => i['itemStatus'] == 'Awaiting Double Check' || i['itemStatus'] == 'Approved');
                      try {
                        await FirebaseFirestore.instance.collection('deliveries').doc(delivery['id'] as String).update({
                          'items': updatedItems,
                          'receivedBy': receivedByCtrl.text.trim(),
                          'status': allReceived ? 'Awaiting Double Check' : 'Pending',
                          'receivedAt': FieldValue.serverTimestamp(),
                        });
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                            content: Text('Submitted!'),
                            backgroundColor: Colors.orange, behavior: SnackBarBehavior.floating));
                        }
                      } catch (err) {
                        setModal(() => submitting = false);
                        if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text('Error: $err'), backgroundColor: Colors.red));
                      }
                    },
                    child: submitting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Submit'),
                    style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white),
                  )),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _itemReceiveCard({
    required int index, required Map<String, dynamic> item, required int expected,
    required TextEditingController qtyCtrl, required TextEditingController remarkCtrl,
    required String condition, required ValueChanged<String> onCondChange,
    required VoidCallback onQtyChange,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF90cdf4)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        RichText(text: TextSpan(
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF1a202c)),
          children: [
            TextSpan(text: item['itemName'] as String),
            if ((item['uom'] as String? ?? '').isNotEmpty)
              TextSpan(
                text: '  (${item['uom']})',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w400, color: Color(0xFF718096))),
          ],
        )),
        Text('${item['supplierCode'] ?? ''} · Order Qty: $expected',
          style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(
            controller: qtyCtrl, keyboardType: TextInputType.number,
            onChanged: (_) => onQtyChange(),
            decoration: const InputDecoration(
              labelText: 'Actual Qty *', border: OutlineInputBorder(), isDense: true),
          )),
        ]),
        const SizedBox(height: 10),
        const Text('Condition', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF4a5568))),
        const SizedBox(height: 6),
        Row(children: [
          _condBtn('✅ OK', 'OK', condition, onCondChange),
          const SizedBox(width: 6),
          _condBtn('❌ Defective', 'Defective', condition, onCondChange),
          const SizedBox(width: 6),
          _condBtn('⚠️ Shortage', 'Shortage', condition, onCondChange),
        ]),
        const SizedBox(height: 10),
        TextField(controller: remarkCtrl,
          decoration: const InputDecoration(
            labelText: 'Remarks (optional)', border: OutlineInputBorder(), isDense: true,
            hintText: 'e.g. 1 unit damaged packaging')),
      ]),
    );
  }

  Widget _condBtn(String label, String value, String current, ValueChanged<String> onChange) {
    final active = current == value;
    Color color;
    switch (value) {
      case 'OK':        color = _green; break;
      case 'Defective': color = _red;   break;
      default:          color = _amber;
    }
    return GestureDetector(
      onTap: () => onChange(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.1) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? color : const Color(0xFFe2e8f0), width: 1.5)),
        child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
          color: active ? color : const Color(0xFF718096))),
      ),
    );
  }

  // ── Review / Verify Modal (Step 2→3) — per-item ──────────────────────
  void _showReviewModal(Map<String, dynamic> delivery, {int? itemIdx}) async {
    final allItems = List<Map<String, dynamic>>.from(
      (delivery['items'] as List? ?? []).map((i) => Map<String, dynamic>.from(i as Map)));

    // If itemIdx provided, review only that item. Otherwise find first 'Awaiting Double Check' item.
    int rcvIdx = itemIdx ?? allItems.indexWhere((i) => (i['itemStatus'] ?? 'Pending') == 'Awaiting Double Check');
    if (rcvIdx < 0) rcvIdx = 0;
    final item = allItems[rcvIdx];
    final itemSt = item['itemStatus'] as String? ?? delivery['status'] as String? ?? 'Pending';
    final isReadOnly = itemSt == 'Approved' || itemSt == 'Rejected';

    // Pre-fill Checked By with the logged-in user's name
    String currentUserName = '';
    if (!isReadOnly) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        currentUserName = (doc.data()?['name'] as String?) ?? '';
      }
    }
    if (!mounted) return;

    final checkedByCtrl = TextEditingController(
      text: isReadOnly ? (item['checkedBy'] as String? ?? delivery['checkedBy'] as String? ?? '') : currentUserName);
    final notesCtrl = TextEditingController(text: item['reviewNotes'] as String? ?? delivery['reviewNotes'] as String? ?? '');
    bool submittingReview = false;

    final cond = item['condition'] as String? ?? '—';
    final actual = item['actualQty'];
    final exp = item['expectedQty'] as int? ?? 0;
    final diff = actual != null ? (actual as int) - exp : null;
    Color cc;
    switch (cond) {
      case 'OK':        cc = _green; break;
      case 'Defective': cc = _red;   break;
      case 'Shortage':  cc = _amber;  break;
      default:          cc = const Color(0xFF718096);
    }

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setReview) => DraggableScrollableSheet(
          expand: false, initialChildSize: 0.85, maxChildSize: 0.97,
          builder: (_, ctrl) => SingleChildScrollView(
          controller: ctrl,
          child: Column(children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              decoration: const BoxDecoration(color: _red, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
              child: Row(children: [
                Container(width: 44, height: 44,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(12)),
                  child: Icon(isReadOnly ? Icons.visibility_outlined : Icons.fact_check_outlined,
                    color: Colors.white, size: 22)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(isReadOnly ? 'Item Details' : 'Review & Verify',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  const Text('Per-item review', style: TextStyle(color: Colors.white70, fontSize: 11)),
                ])),
                GestureDetector(onTap: () => Navigator.pop(context), child: const Icon(Icons.close, color: Colors.white)),
              ]),
            ),
            Padding(
              padding: EdgeInsets.only(left: 20, right: 20, top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Single item review card
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white, borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFe2e8f0)),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)]),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        RichText(text: TextSpan(
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF1a202c)),
                          children: [
                            TextSpan(text: item['itemName'] as String? ?? '—'),
                            if ((item['uom'] as String? ?? '').isNotEmpty)
                              TextSpan(text: '  (${item['uom']})', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w400, color: Color(0xFF718096))),
                          ],
                        )),
                        if ((item['supplierCode'] as String? ?? '').isNotEmpty)
                          Text(item['supplierCode'] as String, style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
                      ])),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: cc.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                        child: Text(cond, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cc)),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    Row(children: [
                      _reviewCol('Order Qty', '$exp ${item['uom'] ?? ''}'),
                      _reviewCol('Actual',
                        actual != null ? '$actual ${item['uom'] ?? ''}${diff != null && diff != 0 ? ' (${diff > 0 ? '+' : ''}$diff)' : ''}' : '—',
                        valueColor: actual != null && diff != 0 ? (diff! < 0 ? _red : _amber) : null),
                      _reviewCol('Remarks', (item['remark'] as String? ?? '').isEmpty ? '—' : item['remark'] as String),
                    ]),
                  ]),
                ),
                const SizedBox(height: 4),
                // Received by
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFF7F8FA), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFe2e8f0))),
                  child: Row(children: [
                    const SizedBox(width: 80, child: Text('Received By', style: TextStyle(fontSize: 11, color: Color(0xFF718096)))),
                    Expanded(child: Text(item['receivedBy'] as String? ?? delivery['receivedBy'] as String? ?? '—',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                  ]),
                ),
                const SizedBox(height: 10),
                // Checked by
                isReadOnly
                  ? Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFFF7F8FA), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFe2e8f0))),
                      child: Row(children: [
                        const SizedBox(width: 80, child: Text('Checked By', style: TextStyle(fontSize: 11, color: Color(0xFF718096)))),
                        Expanded(child: Text(checkedByCtrl.text.isNotEmpty ? checkedByCtrl.text : '—',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                      ]),
                    )
                  : _field('Checked By', child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F8FA),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFe2e8f0)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.person_outline, size: 16, color: Color(0xFF718096)),
                        const SizedBox(width: 8),
                        Text(
                          checkedByCtrl.text.isNotEmpty ? checkedByCtrl.text : '—',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1a202c)),
                        ),
                      ]),
                    )),
                const SizedBox(height: 10),
                // Review notes
                isReadOnly
                  ? Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFFF7F8FA), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFe2e8f0))),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Review Notes', style: TextStyle(fontSize: 11, color: Color(0xFF718096))),
                        const SizedBox(height: 4),
                        Text(notesCtrl.text.isEmpty ? 'No notes.' : notesCtrl.text,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ]))
                  : _field('Review Notes (required for rejection)', child: TextField(
                      controller: notesCtrl, maxLines: 2,
                      decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true,
                        hintText: 'Add notes for rejection or revision...'))),
                const SizedBox(height: 20),
                if (!isReadOnly) ...[
                  Row(children: [
                    Expanded(child: OutlinedButton.icon(
                      onPressed: submittingReview ? null : () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            title: const Row(children: [
                              Icon(Icons.cancel_outlined, color: Colors.red, size: 22),
                              SizedBox(width: 8),
                              Text('Reject Item', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                            ]),
                            content: const Text(
                              'Are you sure you want to reject this item?',
                              style: TextStyle(fontSize: 14, color: Color(0xFF4a5568)),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel', style: TextStyle(color: Color(0xFF718096))),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(context, true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red, foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                child: const Text('Yes, Reject'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true) return;
                        setReview(() => submittingReview = true);
                        await _submitReviewItem(delivery, rcvIdx, 'Rejected', checkedByCtrl.text, notesCtrl.text);
                        setReview(() => submittingReview = false);
                      },
                      icon: submittingReview
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red))
                        : const Icon(Icons.cancel_outlined, size: 16, color: Colors.red),
                      label: const Text('Reject', style: TextStyle(color: Colors.red)),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                    )),
                    const SizedBox(width: 12),
                    Expanded(flex: 2, child: ElevatedButton.icon(
                      onPressed: submittingReview ? null : () async {
                        setReview(() => submittingReview = true);
                        await _submitReviewItem(delivery, rcvIdx, 'Approved', checkedByCtrl.text, notesCtrl.text);
                        setReview(() => submittingReview = false);
                      },
                      icon: submittingReview
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_circle_outline, size: 16),
                      label: Text(submittingReview ? 'Processing...' : 'Approve & Update Stock'),
                      style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white),
                    )),
                  ]),
                ] else ...[
                  SizedBox(width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'))),
                ],
              ]),
            ),
          ]),
        ),
      ),
    ),
  );
  }

  Widget _reviewCol(String label, String value, {Color? valueColor}) => Expanded(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
        color: Color(0xFFa0aec0), letterSpacing: 0.4)),
      const SizedBox(height: 2),
      Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
        color: valueColor ?? const Color(0xFF1a202c))),
    ]),
  );

  Future<void> _submitReviewItem(Map<String, dynamic> delivery, int itemIdx, String decision, String checkedBy, String notes) async {
    if (checkedBy.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please enter your name.'), backgroundColor: Colors.orange));
      return;
    }
    final docId = delivery['id'] as String;
    final items = List<Map<String, dynamic>>.from(
      (delivery['items'] as List? ?? []).map((i) => Map<String, dynamic>.from(i as Map)));
    try {
      // Update only the specific item's itemStatus
      items[itemIdx] = {
        ...items[itemIdx],
        'itemStatus': decision,
        'checkedBy': checkedBy.trim(),
        'reviewNotes': notes.trim(),
        'reviewedAt': DateTime.now().toIso8601String(),
      };

      if (decision == 'Approved') {
        final item = items[itemIdx];
        final actual = (item['actualQty'] as int?) ?? 0;
        if (actual > 0) {
          final itemNum = item['itemNum'] as String? ?? '';
          final stockSnap = await FirebaseFirestore.instance
              .collection('stock_inventory').where('num', isEqualTo: itemNum).limit(1).get();
          final now = DateTime.now();
          final dateStr = '${_months[now.month - 1]} ${now.day}, ${now.year}';
          if (stockSnap.docs.isNotEmpty) {
            final doc = stockSnap.docs.first;
            final cur = (doc['stock'] as num?)?.toInt() ?? 0;
            final newStock = cur + actual;
            final minLevel = (doc['min'] as num?)?.toInt() ?? 0;
            await doc.reference.update({
              'stock': newStock,
              'status': newStock >= minLevel ? 'OK' : 'Low',
              'updatedAt': FieldValue.serverTimestamp(),
            });
            await FirebaseFirestore.instance.collection('transactions').add({
              'item': item['itemName'],
              'desc': 'Stock received — delivery',
              'type': 'IN', 'qty': '+$actual', 'date': dateStr,
              'by': checkedBy, 'createdAt': FieldValue.serverTimestamp(),
            });
          } else {
            await FirebaseFirestore.instance.collection('stock_inventory').add({
              'num': itemNum, 'name': item['itemName'], 'uom': item['uom'] ?? '',
              'stock': actual, 'min': 0, 'max': 0, 'reorder': 0, 'status': 'OK',
              'createdAt': FieldValue.serverTimestamp(), 'updatedAt': FieldValue.serverTimestamp(),
            });
          }
        }
      }

      // Determine delivery-level status from all items
      final allApproved = items.every((i) => i['itemStatus'] == 'Approved');
      final anyRejected = items.any((i) => i['itemStatus'] == 'Rejected');
      final allDone = items.every((i) => i['itemStatus'] == 'Approved' || i['itemStatus'] == 'Rejected');
      final deliveryStatus = allApproved ? 'Approved' : (anyRejected && allDone) ? 'Rejected' : delivery['status'];

      await FirebaseFirestore.instance.collection('deliveries').doc(docId).update({
        'items': items,
        'status': deliveryStatus,
        'checkedBy': checkedBy.trim(),
        'reviewNotes': notes.trim(),
        'reviewedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(decision == 'Approved'
            ? '✅ Item approved! Stock updated.'
            : '❌ Item rejected.'),
          backgroundColor: decision == 'Approved' ? Colors.green : Colors.red,
          behavior: SnackBarBehavior.floating));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  void _approveAdminReviewItem(Map<String, dynamic> d, int itemIdx) async {
    final items = List<Map<String, dynamic>>.from((d['items'] as List).map((i) => Map<String, dynamic>.from(i as Map)));
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.check_circle_outline, color: Color(0xFF38a169), size: 22),
          SizedBox(width: 8),
          Text('Approve Item', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
        content: const Text(
          'Are you sure you want to approve this item? It will be set to Pending for receiving.',
          style: TextStyle(fontSize: 14, color: Color(0xFF4a5568)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF718096))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF38a169), foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Yes, Approve'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    items[itemIdx] = {...items[itemIdx], 'itemStatus': 'Pending'};
    final allPending = items.every((i) => (i['itemStatus'] ?? 'Pending') == 'Pending' || i['itemStatus'] == null);
    final deliveryStatus = allPending ? 'Pending' : d['status'];
    await FirebaseFirestore.instance.collection('deliveries').doc(d['id'] as String).update({'items': items, 'status': deliveryStatus});
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Item approved! Ready for receiving.'), backgroundColor: Color(0xFF38a169), behavior: SnackBarBehavior.floating));
  }

  // ── Reject Admin Review (per-item) ──
  void _rejectAdminReviewItem(Map<String, dynamic> d, int itemIdx) async {
    final items = List<Map<String, dynamic>>.from((d['items'] as List).map((i) => Map<String, dynamic>.from(i as Map)));
    final item = items[itemIdx];
    final confirmed = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(children: [
        Icon(Icons.cancel_outlined, color: Colors.red, size: 22),
        SizedBox(width: 8),
        Text('Reject Item', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ]),
      content: Text(
        'Are you sure you want to reject "${item['itemName']}"?',
        style: const TextStyle(fontSize: 14, color: Color(0xFF4a5568)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel', style: TextStyle(color: Color(0xFF718096))),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red, foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: const Text('Yes, Reject'),
        ),
      ],
    ));
    if (confirmed != true) return;
    items.removeAt(itemIdx);
    if (items.isEmpty) {
      await FirebaseFirestore.instance.collection('deliveries').doc(d['id'] as String).delete();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Request rejected. Purchase order deleted.'), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));
    } else {
      final allPending = items.every((i) => (i['itemStatus'] ?? 'Pending') == 'Pending' || i['itemStatus'] == null);
      final deliveryStatus = allPending ? 'Pending' : d['status'];
      await FirebaseFirestore.instance.collection('deliveries').doc(d['id'] as String).update({'items': items, 'status': deliveryStatus});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Item rejected and removed.'), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));
    }
  }

  // kept for backward compat — now archives instead
  void _confirmDelete(Map<String, dynamic> d) => _confirmArchive(d);
}


