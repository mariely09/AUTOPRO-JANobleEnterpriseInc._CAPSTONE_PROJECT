import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'barcode_scanner_screen.dart';
import 'sync_indicator.dart';

class StaffReceivingBody extends StatefulWidget {
  final String searchQuery;
  const StaffReceivingBody({super.key, this.searchQuery = ''});
  @override
  State<StaffReceivingBody> createState() => _StaffReceivingBodyState();
}

class _StaffReceivingBodyState extends State<StaffReceivingBody> {
  static const _red = Color(0xFFE8001C);
  static const _amber = Color(0xFFd69e2e);
  static const _green = Color(0xFF38a169);
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String _filter = 'all';
  bool _fabOpen = false;
  List<Map<String, dynamic>> _deliveries = [];
  bool _loading = true;
  StreamSubscription<QuerySnapshot>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = FirebaseFirestore.instance
        .collection('receivings')
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
      case 'DRAFT':
        return const Color(0xFF718096);
      case 'INPROG':
        return const Color(0xFF003087);
      case 'COMP':
        return _green;
      case 'PARTIAL':
        return _amber;
      default:
        return const Color(0xFF718096);
    }
  }

  Color _lineStatusColor(String s) {
    switch (s) {
      case 'DRAFT':
        return const Color(0xFF718096);
      case 'COMP':
        return _green;
      case 'MISSING':
        return _red;
      case 'DEFECTIVE':
        return _red;
      case 'INCOMP':
        return _amber;
      default:
        return const Color(0xFF718096);
    }
  }

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

  // ── Scan & find pending delivery ────────────────────────────
  Future<void> _scanAndFind() async {
    setState(() => _fabOpen = false);
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (!mounted || result == null || result.isEmpty) return;

    final query = result.trim().toLowerCase();
    String resolvedNum = '', resolvedName = '';
    try {
      var snap = await FirebaseFirestore.instance
          .collection('item_master')
          .where('barcode', isEqualTo: result.trim())
          .limit(1)
          .get();
      if (snap.docs.isEmpty)
        snap = await FirebaseFirestore.instance
            .collection('item_master')
            .where('qr', isEqualTo: result.trim())
            .limit(1)
            .get();
      if (snap.docs.isEmpty)
        snap = await FirebaseFirestore.instance
            .collection('item_master')
            .where('num', isEqualTo: result.trim().toUpperCase())
            .limit(1)
            .get();
      if (snap.docs.isNotEmpty) {
        final d = snap.docs.first.data();
        resolvedNum = (d['num'] as String? ?? '').toLowerCase();
        resolvedName = (d['name'] as String? ?? '').toLowerCase();
      }
    } catch (_) {}
    if (!mounted) return;

    final pending = _deliveries
        .where(
          (d) =>
              (d['status'] as String? ?? '') == 'DRAFT' ||
              (d['status'] as String? ?? '') == 'INPROG',
        )
        .toList();
    Map<String, dynamic>? found;
    int foundItemIdx = -1;
    for (final delivery in pending) {
      final lines = (delivery['receivingLines'] as List? ?? []);
      for (int idx = 0; idx < lines.length; idx++) {
        final i = lines[idx];
        final num = (i['itemNum'] as String? ?? '').toLowerCase();
        final name = (i['itemName'] as String? ?? '').toLowerCase();
        final match =
            (resolvedNum.isNotEmpty && num.contains(resolvedNum)) ||
            (resolvedName.isNotEmpty && name.contains(resolvedName)) ||
            num.contains(query) ||
            name.contains(query);
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Item found in delivery from ${found['supplier']}'),
          backgroundColor: _green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      _showReceiveModal(
        found,
        itemIdx: foundItemIdx >= 0 ? foundItemIdx : null,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No pending delivery found for that item'),
          backgroundColor: Color(0xFF718096),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.searchQuery.toLowerCase();
    final searched = q.isEmpty
        ? _deliveries
        : _deliveries.where((d) {
            final rcvNum = (d['receivingNum'] as String? ?? '').toLowerCase();
            final poNum = (d['poNum'] as String? ?? '').toLowerCase();
            final lines = (d['receivingLines'] as List? ?? []);
            final lineMatch = lines.any(
              (i) =>
                  (i['itemName'] as String? ?? '').toLowerCase().contains(q) ||
                  (i['itemNum'] as String? ?? '').toLowerCase().contains(q) ||
                  (i['supplierCode'] as String? ?? '').toLowerCase().contains(
                    q,
                  ),
            );
            return rcvNum.contains(q) || poNum.contains(q) || lineMatch;
          }).toList();

    // Count by header status (DRAFT, INPROG, PARTIAL, COMP)
    int draft = 0, inprog = 0, partial = 0, comp = 0;
    for (final d in _deliveries) {
      final status = d['status'] as String? ?? 'DRAFT';
      switch (status) {
        case 'DRAFT':
          draft++;
          break;
        case 'INPROG':
          inprog++;
          break;
        case 'PARTIAL':
          partial++;
          break;
        case 'COMP':
          comp++;
          break;
      }
    }

    final filtered = _filter == 'all'
        ? searched
        : searched.where((d) {
            final status = d['status'] as String? ?? 'DRAFT';
            return status == _filter;
          }).toList();

    return OfflineSaveListener(
      child: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    _chip(
                      'Draft',
                      '$draft',
                      const Color(0xFF718096),
                      Icons.description_outlined,
                      'DRAFT',
                    ),
                    const SizedBox(width: 6),
                    _chip(
                      'In Progress',
                      '$inprog',
                      const Color(0xFF003087),
                      Icons.downloading_outlined,
                      'INPROG',
                    ),
                    const SizedBox(width: 6),
                    _chip(
                      'Partial',
                      '$partial',
                      _amber,
                      Icons.hourglass_empty_outlined,
                      'PARTIAL',
                    ),
                    const SizedBox(width: 6),
                    _chip(
                      'Complete',
                      '$comp',
                      _green,
                      Icons.check_circle_outline,
                      'COMP',
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : Builder(
                        builder: (_) {
                          final flatItems = <Map<String, dynamic>>[];
                          for (final d in filtered) {
                            final lines = (d['receivingLines'] as List? ?? []);
                            for (int idx = 0; idx < lines.length; idx++) {
                              final line = Map<String, dynamic>.from(
                                lines[idx] as Map,
                              );
                              flatItems.add({
                                ...line,
                                '_delivery': d,
                                '_itemIdx': idx,
                              });
                            }
                            if (lines.isEmpty)
                              flatItems.add({'_delivery': d, '_itemIdx': -1});
                          }
                          if (flatItems.isEmpty)
                            return const Center(
                              child: Text(
                                'No items found.',
                                style: TextStyle(color: Color(0xFF718096)),
                              ),
                            );
                          return ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: flatItems.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
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
                        },
                      ),
              ),
            ],
          ),
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
            bottom: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (_fabOpen) ...[
                  _fabAction(
                    label: 'Create Purchase Order (PO)',
                    icon: Icons.add_box_outlined,
                    onTap: () {
                      setState(() => _fabOpen = false);
                      _showNewDeliveryModal();
                    },
                  ),
                  const SizedBox(height: 10),
                ],
                GestureDetector(
                  onTap: () => setState(() => _fabOpen = !_fabOpen),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: _red,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: _red.withValues(alpha: 0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: AnimatedRotation(
                      turns: _fabOpen ? 0.125 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(
                        Icons.add,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(
    String label,
    String value,
    Color color,
    IconData icon,
    String filter,
  ) {
    final active = _filter == filter;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _filter = active ? 'all' : filter),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: active ? color.withValues(alpha: 0.08) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active ? color : Colors.transparent,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 6,
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 14),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                label,
                style: const TextStyle(fontSize: 8, color: Color(0xFF718096)),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fabAction({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1a202c),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, color: _red, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _itemCard(Map<String, dynamic> item, Map<String, dynamic> d) {
    final lineSt = item['lineStatus'] as String? ?? 'DRAFT';
    final color = _lineStatusColor(lineSt);
    final name = item['itemName'] as String? ?? '—';
    final uom = item['uom'] as String? ?? '';
    final supplierCode = item['supplierCode'] as String? ?? '';
    final qty = item['poQty'] as int? ?? 0;
    final rcvQty = item['receivedQty'] as int?;

    // Status label mapping
    String statusLabel = lineSt;
    switch (lineSt) {
      case 'COMP':
        statusLabel = 'Complete';
        break;
      case 'INCOMP':
        statusLabel = 'Incomplete';
        break;
      case 'MISSING':
        statusLabel = 'Missing';
        break;
      case 'DEFECTIVE':
        statusLabel = 'Defective';
        break;
      case 'DRAFT':
        statusLabel = 'Draft';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF0F4F8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: Color(0xFF1a202c),
                      height: 1.3,
                    ),
                    children: [
                      TextSpan(text: name),
                      if (uom.isNotEmpty)
                        TextSpan(
                          text: '  ($uom)',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                            color: Color(0xFF718096),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (supplierCode.isNotEmpty) ...[
                Text(
                  supplierCode,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF718096),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                'Qty: $qty',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF4a5568),
                ),
              ),
              const Spacer(),
              const Icon(
                Icons.chevron_right,
                size: 16,
                color: Color(0xFFa0aec0),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Item View Modal (per-item) — website-matching design ──
  void _showItemViewModal(Map<String, dynamic> d, int itemIdx) async {
    if (itemIdx < 0) {
      _showViewModal(d);
      return;
    }
    final items = (d['items'] as List? ?? []);
    if (itemIdx >= items.length) return;
    final item = Map<String, dynamic>.from(items[itemIdx] as Map);
    final itemSt =
        item['itemStatus'] as String? ?? d['status'] as String? ?? 'Pending';
    final name = item['itemName'] as String? ?? '—';
    final uom = item['uom'] as String? ?? '';
    final qty = item['expectedQty'] as int? ?? 0;
    final supplierCode = item['supplierCode'] as String? ?? '';
    final actual = item['actualQty'] as int?;
    final cond = item['condition'] as String? ?? '—';
    final remark = item['remark'] as String? ?? '';

    // Fetch stock and cost
    // Use stockAtReceive (frozen at receive time) if available, else fetch live stock
    int? currentStock = item['stockAtReceive'] as int?;
    double unitCost = 0;
    final itemNum = item['itemNum'] as String? ?? '';
    if (itemNum.isNotEmpty) {
      if (currentStock == null) {
        try {
          final stockSnap = await FirebaseFirestore.instance
              .collection('stock_inventory')
              .where('num', isEqualTo: itemNum)
              .limit(1)
              .get();
          if (stockSnap.docs.isNotEmpty)
            currentStock =
                (stockSnap.docs.first['stock'] as num?)?.toInt() ?? 0;
        } catch (_) {}
      }
      try {
        final masterSnap = await FirebaseFirestore.instance
            .collection('item_master')
            .where('num', isEqualTo: itemNum)
            .limit(1)
            .get();
        if (masterSnap.docs.isNotEmpty)
          unitCost =
              double.tryParse(
                (masterSnap.docs.first['cost']?.toString() ?? '0')
                    .replaceAll('₱', '')
                    .replaceAll(',', '')
                    .trim(),
              ) ??
              0;
      } catch (_) {}
    }
    if (!mounted) return;
    final subtotal = unitCost * qty;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        maxChildSize: 0.92,
        builder: (ctx2, ctrl) => SingleChildScrollView(
          controller: ctrl,
          child: Column(
            children: [
              // ── Red header with item name + supplier code ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFE31E24), Color(0xFFC41E3A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$name${uom.isNotEmpty ? '  ($uom)' : ''}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              height: 1.3,
                            ),
                          ),
                          if (supplierCode.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              supplierCode,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx2),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── 2x2 Info grid ──
                    Row(
                      children: [
                        Expanded(child: _ivInfoCard('ORDER QUANTITY', '$qty')),
                        const SizedBox(width: 10),
                        if (currentStock != null)
                          Expanded(
                            child: _ivInfoCard(
                              'CURRENT STOCK',
                              '$currentStock',
                            ),
                          )
                        else
                          const Expanded(child: SizedBox.shrink()),
                      ],
                    ),
                    if (unitCost > 0) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _ivInfoCard(
                              'UNIT PRICE',
                              _fmtPeso(unitCost),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _ivInfoCard(
                              'SUBTOTAL',
                              _fmtPeso(subtotal),
                              valueColor: _red,
                            ),
                          ),
                        ],
                      ),
                    ],
                    // ── Receiving details (if received) ──
                    if (actual != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFFe2e8f0),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'RECEIVING DETAILS',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF4a5568),
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Actual Qty',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Color(0xFFa0aec0),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '$actual',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: cond == 'OK'
                                              ? _green
                                              : cond == 'Defective'
                                              ? _red
                                              : _amber,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Condition',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Color(0xFFa0aec0),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color:
                                              (cond == 'OK'
                                                      ? _green
                                                      : cond == 'Defective'
                                                      ? _red
                                                      : _amber)
                                                  .withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        child: Text(
                                          cond,
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: cond == 'OK'
                                                ? _green
                                                : cond == 'Defective'
                                                ? _red
                                                : _amber,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Difference',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Color(0xFFa0aec0),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        actual - qty == 0
                                            ? '0'
                                            : '${actual - qty > 0 ? '+' : ''}${actual - qty}',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: actual - qty == 0
                                              ? _green
                                              : actual - qty < 0
                                              ? _red
                                              : _amber,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (remark.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFFBEB),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Remarks: $remark',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF92400E),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    // ── Delivery info (only show if not pending) ──
                    if (itemSt != 'Pending') ...[
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFFe2e8f0),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'DELIVERY INFO',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF4a5568),
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 10),
                            if (_fmtOrderDate(d['createdAt']) != '—')
                              _ivInfoRow(
                                'Order Date',
                                _fmtOrderDate(d['createdAt']),
                              ),
                            if ((item['receivedAt'] as String? ??
                                    (d['receivedAt'] is String
                                        ? d['receivedAt'] as String
                                        : ''))
                                .isNotEmpty)
                              _ivInfoRow(
                                'Received Date',
                                _fmt(
                                  item['receivedAt'] as String? ??
                                      (d['receivedAt'] is String
                                          ? d['receivedAt'] as String
                                          : ''),
                                ),
                              ),
                            if ((d['receivedBy'] as String? ?? '').isNotEmpty)
                              _ivInfoRow(
                                'Received By',
                                d['receivedBy'] as String,
                              ),
                            if ((d['checkedBy'] as String? ?? '').isNotEmpty)
                              _ivInfoRow(
                                'Checked By',
                                d['checkedBy'] as String,
                              ),
                            if ((d['reviewNotes'] as String? ?? '').isNotEmpty)
                              _ivInfoRow(
                                'Review Notes',
                                d['reviewNotes'] as String,
                              ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    // ── Action buttons ──
                    if (itemSt == 'Pending') ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx2);
                            _showReceiveModal(d, itemIdx: itemIdx);
                          },
                          icon: const Icon(Icons.download_outlined, size: 16),
                          label: const Text(
                            'Receive Item',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            elevation: 4,
                          ),
                        ),
                      ),
                    ] else if (itemSt == 'Awaiting Double Check') ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        decoration: BoxDecoration(
                          color: _amber.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: _amber.withValues(alpha: 0.3),
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.hourglass_empty_outlined,
                              size: 16,
                              color: _amber,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Awaiting Review',
                              style: TextStyle(
                                fontSize: 14,
                                color: _amber,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else if (itemSt == 'Approved') ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        decoration: BoxDecoration(
                          color: _green.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: _green.withValues(alpha: 0.3),
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              size: 16,
                              color: _green,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Approved',
                              style: TextStyle(
                                fontSize: 14,
                                color: _green,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else if (itemSt == 'Rejected') ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        decoration: BoxDecoration(
                          color: _red.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: _red.withValues(alpha: 0.3),
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.cancel_outlined, size: 16, color: _red),
                            const SizedBox(width: 6),
                            Text(
                              'Rejected',
                              style: TextStyle(
                                fontSize: 14,
                                color: _red,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ivInfoCard(String label, String value, {Color? valueColor}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFe2e8f0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFFa0aec0),
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: valueColor ?? const Color(0xFF1a202c),
              ),
            ),
          ],
        ),
      );

  Widget _ivInfoRow(String label, String value) => Container(
    padding: const EdgeInsets.symmetric(vertical: 6),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0xFFF0F4F8))),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF718096)),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1a202c),
          ),
        ),
      ],
    ),
  );

  // ── New Delivery Request Modal (create OR edit) ─────────────
  void _showNewDeliveryModal({Map<String, dynamic>? existing}) {
    final isEdit = existing != null;
    List<Map<String, dynamic>> replenishItems = [];
    List<Map<String, dynamic>> addedItems = List<Map<String, dynamic>>.from(
      (existing?['items'] as List? ?? []).map(
        (i) => Map<String, dynamic>.from(i as Map),
      ),
    );
    final Map<int, TextEditingController> qtyCtrlrs = {};
    bool loadingItems = true;
    bool saving = false;
    Set<String> addedNums = addedItems
        .map((i) => i['itemNum'] as String? ?? '')
        .toSet();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) {
          if (loadingItems) {
            Future.microtask(() async {
              try {
                final stockSnap = await FirebaseFirestore.instance
                    .collection('stock_inventory')
                    .get();
                final numToStockData = <String, Map<String, int>>{};
                final needReplenish = <Map<String, dynamic>>[];
                for (final d in stockSnap.docs) {
                  final s = d.data();
                  final n = s['num'] as String? ?? '';
                  final stock = (s['stock'] as num?)?.toInt() ?? 0;
                  final min = (s['min'] as num?)?.toInt() ?? 0;
                  final max = (s['max'] as num?)?.toInt() ?? 0;
                  if (n.isNotEmpty)
                    numToStockData[n] = {
                      'stock': stock,
                      'min': min,
                      'max': max,
                    };
                  if (stock == 0 || stock <= min) needReplenish.add(s);
                }

                final numToCost = <String, double>{};
                final numToSupplierCode = <String, String>{};
                final allMaterials = <Map<String, dynamic>>[];
                try {
                  final masterSnap = await FirebaseFirestore.instance
                      .collection('item_master')
                      .get();
                  for (final d in masterSnap.docs) {
                    final data = d.data();
                    if ((data['type'] as String? ?? '') != 'Material') continue;
                    final n = data['num'] as String? ?? '';
                    final c =
                        double.tryParse(
                          (data['cost']?.toString() ?? '0')
                              .replaceAll('₱', '')
                              .replaceAll(',', '')
                              .trim(),
                        ) ??
                        0;
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
                } catch (_) {}

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

                final loaded =
                    needReplenish
                        .map((s) {
                          final n = s['num'] as String? ?? '';
                          return <String, dynamic>{
                            'num': n,
                            'name': s['name'] as String? ?? '',
                            'uom': s['uom'] as String? ?? '',
                            'supplierCode': numToSupplierCode[n] ?? '',
                            '_stock': (s['stock'] as num?)?.toInt() ?? 0,
                            '_minLevel': (s['min'] as num?)?.toInt() ?? 0,
                            '_maxLevel': (s['max'] as num?)?.toInt() ?? 0,
                            '_cost': numToCost[n] ?? 0.0,
                          };
                        })
                        .where(
                          (m) => !activeDeliveryNums.contains(
                            m['num'] as String? ?? '',
                          ),
                        )
                        .toList()
                      ..sort((a, b) {
                        if ((a['_stock'] as int) == 0 &&
                            (b['_stock'] as int) != 0)
                          return -1;
                        if ((b['_stock'] as int) == 0 &&
                            (a['_stock'] as int) != 0)
                          return 1;
                        return (a['name'] as String).compareTo(
                          b['name'] as String,
                        );
                      });
                // Enrich pre-existing addedItems (edit mode) with cost+stock
                if (addedItems.isNotEmpty) {
                  final enriched = <Map<String, dynamic>>[];
                  for (final item in addedItems) {
                    final n = item['itemNum'] as String? ?? '';
                    final c = numToCost[n] ?? 0.0;
                    int? stockVal;
                    try {
                      final ss = await FirebaseFirestore.instance
                          .collection('stock_inventory')
                          .where('num', isEqualTo: n)
                          .limit(1)
                          .get();
                      if (ss.docs.isNotEmpty)
                        stockVal = (ss.docs.first['stock'] as num?)?.toInt();
                    } catch (_) {}
                    enriched.add({
                      ...item,
                      '_cost': c,
                      '_stock': stockVal,
                      'supplierCode': numToSupplierCode[n] ?? '',
                      '_maxQty': (item['expectedQty'] as int?) ?? 1,
                    });
                  }
                  if (ctx.mounted)
                    setModal(
                      () => addedItems
                        ..clear()
                        ..addAll(enriched),
                    );
                }

                if (ctx.mounted)
                  setModal(() {
                    replenishItems = loaded;
                    loadingItems = false;
                  });
              } catch (_) {
                if (ctx.mounted)
                  setModal(() {
                    loadingItems = false;
                  });
              }
            });
          }

          final visible = replenishItems.where((item) {
            final n = item['num'] as String? ?? '';
            return !addedNums.contains(n);
          }).toList();

          Widget statusBadge(int stock, int min) {
            if (stock == 0)
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFfef2f2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFfca5a5)),
                ),
                child: const Text(
                  'Out of Stock',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFe53e3e),
                  ),
                ),
              );
            if (stock <= min)
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFFCD34D)),
                ),
                child: const Text(
                  'Low Stock',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFd69e2e),
                  ),
                ),
              );
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FFF4),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF9AE6B4)),
              ),
              child: const Text(
                'In Stock',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF38a169),
                ),
              ),
            );
          }

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.92,
            maxChildSize: 1.0,
            builder: (_, ctrl) => Column(
              children: [
                // Header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                  decoration: const BoxDecoration(
                    color: _red,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isEdit
                                  ? 'Edit Purchase Order (PO)'
                                  : 'Purchase Order (PO)',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              isEdit
                                  ? 'Update items for this delivery'
                                  : 'Submit for admin approval',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: const Icon(Icons.close, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                // Info banner
                Container(
                  color: const Color(0xFFEFF6FF),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 14,
                        color: Color(0xFF1E40AF),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Your request will be reviewed and approved by an admin before processing.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF1E40AF),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: ctrl,
                    padding: EdgeInsets.only(
                      left: 20,
                      right: 20,
                      top: 20,
                      bottom: MediaQuery.viewInsetsOf(ctx).bottom + 24,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          loadingItems
                              ? 'Loading items…'
                              : 'Items that need replenishment',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF718096),
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (loadingItems)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        else if (visible.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0FFF4),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFF9AE6B4),
                              ),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.check_circle_outline,
                                  color: Color(0xFF38a169),
                                  size: 16,
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'All items are sufficiently stocked.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF38a169),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          Container(
                            constraints: const BoxConstraints(maxHeight: 260),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: const Color(0xFFe2e8f0),
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: ListView.separated(
                                shrinkWrap: true,
                                itemCount: visible.length,
                                separatorBuilder: (_, __) => const Divider(
                                  height: 1,
                                  color: Color(0xFFf0f4f8),
                                ),
                                itemBuilder: (_, i) {
                                  final item = visible[i];
                                  final num = item['num'] as String? ?? '';
                                  final name = item['name'] as String? ?? '';
                                  final uom = item['uom'] as String? ?? '';
                                  final supplierCode =
                                      item['supplierCode'] as String? ?? '';
                                  final stock = item['_stock'] as int? ?? 0;
                                  final min = item['_minLevel'] as int? ?? 0;
                                  final max = item['_maxLevel'] as int? ?? 0;
                                  final cost = item['_cost'] is double
                                      ? item['_cost'] as double
                                      : double.tryParse(
                                              item['_cost']?.toString() ?? '0',
                                            ) ??
                                            0.0;
                                  final rec = max > 0
                                      ? (max - stock).clamp(0, 9999)
                                      : 1;
                                  final added = addedNums.contains(num);
                                  return GestureDetector(
                                    onTap: added
                                        ? null
                                        : () {
                                            final rowIdx = addedItems.length;
                                            qtyCtrlrs[rowIdx] =
                                                TextEditingController(
                                                  text: '$rec',
                                                );
                                            setModal(() {
                                              addedItems.add({
                                                'itemNum': num,
                                                'itemName': name,
                                                'uom': uom,
                                                'expectedQty': rec,
                                                '_rowIdx': rowIdx,
                                                '_cost': cost,
                                                '_stock': stock,
                                                'supplierCode': supplierCode,
                                                '_maxQty': rec,
                                              });
                                              addedNums.add(num);
                                            });
                                          },
                                    child: AnimatedOpacity(
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      opacity: added ? 0.35 : 1.0,
                                      child: Container(
                                        color: added
                                            ? const Color(0xFFF7F8FA)
                                            : Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 11,
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  RichText(
                                                    text: TextSpan(
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        fontSize: 13,
                                                        color: Color(
                                                          0xFF1a202c,
                                                        ),
                                                      ),
                                                      children: [
                                                        TextSpan(text: name),
                                                        if (uom.isNotEmpty)
                                                          TextSpan(
                                                            text: '  ($uom)',
                                                            style:
                                                                const TextStyle(
                                                                  fontSize: 11,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w400,
                                                                  color: Color(
                                                                    0xFF718096,
                                                                  ),
                                                                ),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(height: 3),
                                                  Wrap(
                                                    spacing: 6,
                                                    children: [
                                                      if (supplierCode
                                                          .isNotEmpty)
                                                        Text(
                                                          supplierCode,
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 11,
                                                                color: Color(
                                                                  0xFF718096,
                                                                ),
                                                              ),
                                                        ),
                                                      Text(
                                                        'Current: $stock',
                                                        style: const TextStyle(
                                                          fontSize: 11,
                                                          color: Color(
                                                            0xFF718096,
                                                          ),
                                                        ),
                                                      ),
                                                      if (cost > 0)
                                                        Text(
                                                          '${_fmtPeso(cost)}/unit',
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 11,
                                                                color: Color(
                                                                  0xFF718096,
                                                                ),
                                                              ),
                                                        ),
                                                      statusBadge(stock, min),
                                                      if (rec > 0 && !added)
                                                        Text(
                                                          'Suggest order: $rec',
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 11,
                                                                color: Color(
                                                                  0xFF718096,
                                                                ),
                                                              ),
                                                        ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                            added
                                                ? const Icon(
                                                    Icons.check_circle,
                                                    size: 18,
                                                    color: Color(0xFF38a169),
                                                  )
                                                : const Icon(
                                                    Icons.add_circle_outline,
                                                    size: 18,
                                                    color: Color(0xFFE8001C),
                                                  ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        // Added items list
                        if (addedItems.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Items Added',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1a202c),
                                ),
                              ),
                              Text(
                                '${addedItems.length} item${addedItems.length != 1 ? 's' : ''}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF718096),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ...addedItems.asMap().entries.map((e) {
                            final rowIdx = e.key;
                            final item = e.value;
                            final itemCost = item['_cost'] is double
                                ? item['_cost'] as double
                                : double.tryParse(
                                        item['_cost']?.toString() ?? '0',
                                      ) ??
                                      0.0;
                            final itemStock = item['_stock'] as int?;
                            final uom = item['uom'] as String? ?? '';
                            qtyCtrlrs.putIfAbsent(
                              rowIdx,
                              () => TextEditingController(
                                text: '${item['expectedQty'] ?? 1}',
                              ),
                            );
                            final qty =
                                int.tryParse(qtyCtrlrs[rowIdx]!.text) ??
                                (item['expectedQty'] as int? ?? 1);
                            final subtotal = itemCost * qty;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0xFFe2e8f0),
                                  width: 1.2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.03),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.02),
                                    blurRadius: 2,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // ── Header: name + remove ──
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: RichText(
                                          text: TextSpan(
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14,
                                              color: Color(0xFF1a202c),
                                              height: 1.3,
                                            ),
                                            children: [
                                              TextSpan(
                                                text:
                                                    item['itemName']
                                                        as String? ??
                                                    '',
                                              ),
                                              if (uom.isNotEmpty)
                                                TextSpan(
                                                  text: '  ($uom)',
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w400,
                                                    color: Color(0xFF718096),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      GestureDetector(
                                        onTap: () {
                                          final removedNum =
                                              addedItems[rowIdx]['itemNum']
                                                  as String? ??
                                              '';
                                          setModal(() {
                                            addedItems.removeAt(rowIdx);
                                            qtyCtrlrs.remove(rowIdx);
                                            addedNums.remove(removedNum);
                                          });
                                        },
                                        child: Container(
                                          width: 28,
                                          height: 28,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFEF2F2),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            border: Border.all(
                                              color: const Color(0xFFfecaca),
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.close_rounded,
                                            size: 15,
                                            color: Color(0xFFe53e3e),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  // ── Meta info chips ──
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    children: [
                                      if ((item['supplierCode'] as String? ??
                                              '')
                                          .isNotEmpty)
                                        _metaChip(
                                          item['supplierCode'] as String,
                                          Icons.qr_code,
                                          const Color(0xFF4a5568),
                                        ),
                                      if (itemCost > 0)
                                        _metaChip(
                                          '${_fmtPeso(itemCost)}',
                                          Icons.sell_outlined,
                                          const Color(0xFF003087),
                                        ),
                                      if (itemStock != null)
                                        _metaChip(
                                          'Stock: $itemStock',
                                          Icons.inventory_2_outlined,
                                          itemStock == 0
                                              ? const Color(0xFFe53e3e)
                                              : const Color(0xFF718096),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  // ── Qty stepper row ──
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: const Color(0xFFe2e8f0),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Text(
                                          'Order Quantity',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF4a5568),
                                          ),
                                        ),
                                        const Spacer(),
                                        Container(
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            border: Border.all(
                                              color: const Color(0xFFe2e8f0),
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withValues(
                                                  alpha: 0.04,
                                                ),
                                                blurRadius: 4,
                                              ),
                                            ],
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              GestureDetector(
                                                onTap: () {
                                                  final v =
                                                      int.tryParse(
                                                        qtyCtrlrs[rowIdx]!.text,
                                                      ) ??
                                                      1;
                                                  if (v <= 1) return;
                                                  qtyCtrlrs[rowIdx]!.text =
                                                      '${v - 1}';
                                                  setModal(
                                                    () => addedItems[rowIdx] = {
                                                      ...addedItems[rowIdx],
                                                      'expectedQty': v - 1,
                                                    },
                                                  );
                                                },
                                                child: Container(
                                                  width: 34,
                                                  height: 34,
                                                  decoration: const BoxDecoration(
                                                    borderRadius:
                                                        BorderRadius.only(
                                                          topLeft:
                                                              Radius.circular(
                                                                7,
                                                              ),
                                                          bottomLeft:
                                                              Radius.circular(
                                                                7,
                                                              ),
                                                        ),
                                                  ),
                                                  child: const Icon(
                                                    Icons.remove,
                                                    size: 16,
                                                    color: Color(0xFF718096),
                                                  ),
                                                ),
                                              ),
                                              Container(
                                                width: 48,
                                                height: 34,
                                                decoration: const BoxDecoration(
                                                  border: Border.symmetric(
                                                    vertical: BorderSide(
                                                      color: Color(0xFFe2e8f0),
                                                    ),
                                                  ),
                                                ),
                                                child: Center(
                                                  child: TextField(
                                                    controller:
                                                        qtyCtrlrs[rowIdx],
                                                    keyboardType:
                                                        TextInputType.number,
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: Color(0xFF1a202c),
                                                    ),
                                                    decoration:
                                                        const InputDecoration(
                                                          border:
                                                              InputBorder.none,
                                                          isDense: true,
                                                          contentPadding:
                                                              EdgeInsets.zero,
                                                        ),
                                                    onChanged: (v) {
                                                      final maxQ =
                                                          (addedItems[rowIdx]['_maxQty']
                                                              as int?) ??
                                                          9999;
                                                      final q2 =
                                                          (int.tryParse(v) ?? 1)
                                                              .clamp(1, maxQ);
                                                      if (q2.toString() != v)
                                                        qtyCtrlrs[rowIdx]!
                                                                .text =
                                                            '$q2';
                                                      setModal(
                                                        () => addedItems[rowIdx] = {
                                                          ...addedItems[rowIdx],
                                                          'expectedQty': q2,
                                                        },
                                                      );
                                                    },
                                                  ),
                                                ),
                                              ),
                                              GestureDetector(
                                                onTap: () {
                                                  final maxQ =
                                                      (addedItems[rowIdx]['_maxQty']
                                                          as int?) ??
                                                      9999;
                                                  final v =
                                                      int.tryParse(
                                                        qtyCtrlrs[rowIdx]!.text,
                                                      ) ??
                                                      1;
                                                  if (v >= maxQ)
                                                    return; // cap reached
                                                  qtyCtrlrs[rowIdx]!.text =
                                                      '${v + 1}';
                                                  setModal(
                                                    () => addedItems[rowIdx] = {
                                                      ...addedItems[rowIdx],
                                                      'expectedQty': v + 1,
                                                    },
                                                  );
                                                },
                                                child: Container(
                                                  width: 34,
                                                  height: 34,
                                                  decoration: const BoxDecoration(
                                                    borderRadius:
                                                        BorderRadius.only(
                                                          topRight:
                                                              Radius.circular(
                                                                7,
                                                              ),
                                                          bottomRight:
                                                              Radius.circular(
                                                                7,
                                                              ),
                                                        ),
                                                  ),
                                                  child: Builder(
                                                    builder: (_) {
                                                      final maxQ =
                                                          (addedItems[rowIdx]['_maxQty']
                                                              as int?) ??
                                                          9999;
                                                      final cur =
                                                          int.tryParse(
                                                            qtyCtrlrs[rowIdx]!
                                                                .text,
                                                          ) ??
                                                          1;
                                                      return Icon(
                                                        Icons.add,
                                                        size: 16,
                                                        color: cur >= maxQ
                                                            ? const Color(
                                                                0xFFcbd5e0,
                                                              )
                                                            : const Color(
                                                                0xFFE8001C,
                                                              ),
                                                      );
                                                    },
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // ── Subtotal ──
                                  if (itemCost > 0) ...[
                                    const SizedBox(height: 10),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        const Text(
                                          'Subtotal  ',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFFa0aec0),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        Text(
                                          _fmtPeso(subtotal),
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFFE8001C),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            );
                          }),
                          Builder(
                            builder: (_) {
                              final total = addedItems.fold<double>(0, (
                                sum,
                                i,
                              ) {
                                final c = i['_cost'] is double
                                    ? i['_cost'] as double
                                    : double.tryParse(
                                            i['_cost']?.toString() ?? '0',
                                          ) ??
                                          0.0;
                                final q = i['expectedQty'] as int? ?? 1;
                                return sum + c * q;
                              });
                              if (total <= 0) return const SizedBox.shrink();
                              return Container(
                                margin: const EdgeInsets.only(top: 4),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: const Color(0xFFe2e8f0),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Estimated Total',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF4a5568),
                                      ),
                                    ),
                                    Text(
                                      _fmtPeso(total),
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF1a202c),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: saving
                                ? null
                                : () async {
                                    if (addedItems.isEmpty) return;
                                    // Check for duplicate items in other active deliveries
                                    final activeDeliveries = _deliveries.where((
                                      del,
                                    ) {
                                      if (isEdit && del['id'] == existing['id'])
                                        return false;
                                      final st =
                                          del['status'] as String? ?? 'Pending';
                                      return st != 'Approved' &&
                                          st != 'Rejected';
                                    }).toList();
                                    final duplicates = <String>[];
                                    for (final item in addedItems) {
                                      final num =
                                          item['itemNum'] as String? ?? '';
                                      for (final del in activeDeliveries) {
                                        final delItems =
                                            (del['items'] as List? ?? []);
                                        if (delItems.any(
                                          (i) =>
                                              (i['itemNum'] as String? ?? '') ==
                                              num,
                                        )) {
                                          duplicates.add(
                                            item['itemName'] as String? ?? '',
                                          );
                                          break;
                                        }
                                      }
                                    }
                                    if (duplicates.isNotEmpty) {
                                      if (ctx.mounted)
                                        ScaffoldMessenger.of(ctx).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Item already in an active delivery: ${duplicates.toSet().join(', ')}',
                                            ),
                                            backgroundColor: Colors.red,
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                      return;
                                    }
                                    setModal(() => saving = true);
                                    final items = addedItems
                                        .map(
                                          (i) => {
                                            'itemNum': i['itemNum'],
                                            'itemName': i['itemName'],
                                            'uom': i['uom'],
                                            'expectedQty': i['expectedQty'],
                                            'supplierCode':
                                                i['supplierCode'] ?? '',
                                          },
                                        )
                                        .toList();
                                    try {
                                      if (isEdit) {
                                        await SyncStatusNotifier.instance
                                            .trackWrite(
                                              () => FirebaseFirestore.instance
                                                  .collection('deliveries')
                                                  .doc(existing['id'] as String)
                                                  .update({'items': items}),
                                            );
                                      } else {
                                        await SyncStatusNotifier.instance
                                            .trackWrite(
                                              () => FirebaseFirestore.instance
                                                  .collection('deliveries')
                                                  .add({
                                                    'items': items,
                                                    'status':
                                                        'For Admin Review',
                                                    'createdAt':
                                                        FieldValue.serverTimestamp(),
                                                  }),
                                            );
                                      }
                                      if (ctx.mounted) {
                                        Navigator.pop(ctx);
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              isEdit
                                                  ? 'Request updated!'
                                                  : 'Purchase order created successfully!',
                                            ),
                                            backgroundColor: isEdit
                                                ? _red
                                                : _green,
                                            behavior: SnackBarBehavior.floating,
                                            shape: const RoundedRectangleBorder(
                                              borderRadius: BorderRadius.all(
                                                Radius.circular(10),
                                              ),
                                            ),
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      setModal(() => saving = false);
                                      if (ctx.mounted)
                                        ScaffoldMessenger.of(ctx).showSnackBar(
                                          SnackBar(
                                            content: Text('Error: $e'),
                                            backgroundColor: Colors.red,
                                          ),
                                        );
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _red,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(isEdit ? 'Update' : 'Save'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Edit PO Picker ──────────────────────────────────────────
  void _showEditPOPicker(List<Map<String, dynamic>> editablePOs) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        maxChildSize: 0.85,
        builder: (_, ctrl) => Column(
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              decoration: const BoxDecoration(
                color: Color(0xFF003087),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Edit Purchase Order',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Select a PO to edit',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            // List
            Expanded(
              child: ListView.separated(
                controller: ctrl,
                padding: const EdgeInsets.all(16),
                itemCount: editablePOs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final d = editablePOs[i];
                  final items = (d['items'] as List? ?? []);
                  final createdAt = d['createdAt'];
                  final st = d['status'] as String? ?? 'Pending';
                  String dateStr = '—';
                  if (createdAt is Timestamp) {
                    final dt = createdAt.toDate();
                    dateStr = '${_months[dt.month - 1]} ${dt.day}, ${dt.year}';
                  }
                  final statusColor = st == 'Pending'
                      ? const Color(0xFF718096)
                      : _red;
                  final statusLabel = st == 'For Admin Review'
                      ? 'For Review'
                      : st;
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      _showNewDeliveryModal(existing: d);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFe2e8f0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEBF4FF),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.description_outlined,
                              size: 18,
                              color: Color(0xFF003087),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${items.length} item${items.length != 1 ? 's' : ''}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: Color(0xFF1a202c),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  dateStr,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF718096),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: statusColor.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Text(
                              statusLabel,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: statusColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: Color(0xFFa0aec0),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Pick a pending delivery to receive ──────────────────────
  void _showPickPendingModal() {
    final pending = _deliveries
        .where((d) => (d['status'] as String? ?? '') == 'Pending')
        .toList();
    if (pending.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No pending deliveries to receive.'),
          backgroundColor: Color(0xFF718096),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        maxChildSize: 0.85,
        builder: (_, ctrl) => Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              decoration: const BoxDecoration(
                color: _red,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Select Delivery',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Choose a pending delivery to receive',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                controller: ctrl,
                padding: const EdgeInsets.all(16),
                itemCount: pending.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final d = pending[i];
                  final items = (d['items'] as List? ?? []);
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      _showReceiveModal(d);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFe2e8f0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  d['supplier'] as String? ?? '—',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: Color(0xFF1a202c),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${items.length} item${items.length != 1 ? 's' : ''}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF718096),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: Color(0xFFa0aec0),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── View Delivery Modal ──────────────────────────────────────
  void _showViewModal(Map<String, dynamic> d) async {
    final status = d['status'] as String? ?? 'Pending';
    final color = _statusColor(status);
    List<Map<String, dynamic>> items = List<Map<String, dynamic>>.from(
      (d['items'] as List? ?? []).map(
        (i) => Map<String, dynamic>.from(i as Map),
      ),
    );

    if (status == 'Pending' ||
        status == 'Awaiting Double Check' ||
        status == 'For Admin Review') {
      try {
        final masterSnap = await FirebaseFirestore.instance
            .collection('item_master')
            .get();
        final numToCost = <String, double>{};
        final numToGroup = <String, String>{};
        for (final doc in masterSnap.docs) {
          final data = doc.data();
          final n = data['num'] as String? ?? '';
          final c =
              double.tryParse(
                (data['cost']?.toString() ?? '0')
                    .replaceAll('₱', '')
                    .replaceAll(',', '')
                    .trim(),
              ) ??
              0;
          if (n.isNotEmpty) {
            numToCost[n] = c;
            numToGroup[n] = data['group'] as String? ?? '';
          }
        }
        final numToStock = <String, int>{};
        final numToMin = <String, int>{};
        try {
          final stockSnap = await FirebaseFirestore.instance
              .collection('stock_inventory')
              .get();
          for (final doc in stockSnap.docs) {
            final data = doc.data();
            final n = data['num'] as String? ?? '';
            if (n.isNotEmpty) {
              numToStock[n] = (data['stock'] as num?)?.toInt() ?? 0;
              numToMin[n] = (data['min'] as num?)?.toInt() ?? 0;
            }
          }
        } catch (_) {}
        items = items.map((item) {
          final n = item['itemNum'] as String? ?? '';
          return {
            ...item,
            '_cost': numToCost[n] ?? 0.0,
            '_group': numToGroup[n] ?? '',
            '_stock': numToStock[n],
            '_min': numToMin[n],
          };
        }).toList();
      } catch (_) {}
    }
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (_, ctrl) => SingleChildScrollView(
          controller: ctrl,
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            d['supplier'] as String? ?? '—',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _fmt(d['date'] as String?),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        status,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if ((d['notes'] as String? ?? '').isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFFCD34D)),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.sticky_note_2_outlined,
                              size: 14,
                              color: Color(0xFF92400E),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                d['notes'] as String,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF92400E),
                                ),
                              ),
                            ),
                          ],
                        ),
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
                    Text(
                      'Items (${items.length})',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1a202c),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...items.map((item) {
                      final cond = item['condition'] as String? ?? '—';
                      final condColor = cond == 'OK'
                          ? _green
                          : cond == 'Defective'
                          ? _red
                          : _amber;
                      final actual = item['actualQty'];
                      final exp = item['expectedQty'] as int? ?? 0;
                      final diff = actual != null
                          ? (actual as int) - exp
                          : null;

                      if (status == 'Approved') {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFe2e8f0)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item['itemName'] as String? ?? '—',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                            color: Color(0xFF1a202c),
                                          ),
                                        ),
                                        Text(
                                          item['supplierCode'] as String? ?? '',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF718096),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: condColor.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      cond,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: condColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              const Divider(
                                height: 1,
                                color: Color(0xFFF0F4F8),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  _gridCol(
                                    'EXPECTED',
                                    '$exp ${item['uom'] ?? ''}',
                                  ),
                                  _gridCol(
                                    'ACTUAL RECEIVED',
                                    actual != null
                                        ? '$actual ${item['uom'] ?? ''}${diff != null && diff != 0 ? '  (${diff > 0 ? '+' : ''}$diff)' : ''}'
                                        : '—',
                                    valueColor: actual != null && diff != 0
                                        ? (diff! < 0 ? _red : _amber)
                                        : condColor,
                                  ),
                                  _gridCol(
                                    'CONDITION',
                                    cond,
                                    valueColor: condColor,
                                  ),
                                  _gridCol(
                                    'REMARKS',
                                    (item['remark'] as String? ?? '').isEmpty
                                        ? '—'
                                        : item['remark'] as String,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }

                      final itemCostVal = item['_cost'] is double
                          ? item['_cost'] as double
                          : double.tryParse(item['_cost']?.toString() ?? '0') ??
                                0.0;
                      final itemTotal = itemCostVal * exp;
                      final itemGroup = item['_group'] as String? ?? '';
                      final itemStock = item['_stock'] as int?;
                      final itemMin = item['_min'] as int? ?? 0;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFe2e8f0)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: RichText(
                                      text: TextSpan(
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: Color(0xFF1a202c),
                                        ),
                                        children: [
                                          TextSpan(
                                            text:
                                                item['itemName'] as String? ??
                                                '—',
                                          ),
                                          if ((item['uom'] as String? ?? '')
                                              .isNotEmpty)
                                            TextSpan(
                                              text: '  (${item['uom']})',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w400,
                                                color: Color(0xFF718096),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (itemStock != null) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
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
                                              : const Color(0xFFe2e8f0),
                                        ),
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
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                [
                                  item['itemNum'] as String? ?? '',
                                  if (itemGroup.isNotEmpty) itemGroup,
                                ].join(' · '),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF718096),
                                ),
                              ),
                              if (itemCostVal > 0) ...[
                                const SizedBox(height: 10),
                                const Divider(
                                  height: 1,
                                  color: Color(0xFFF0F4F8),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    _miniStat(
                                      'Order Qty',
                                      '$exp',
                                      const Color(0xFF1a202c),
                                    ),
                                    const SizedBox(width: 12),
                                    _miniStat(
                                      'Rcv Qty',
                                      (item['actualQty'] != null)
                                          ? '${item['actualQty']}'
                                          : '—',
                                      const Color(0xFF1a202c),
                                    ),
                                    const SizedBox(width: 12),
                                    _miniStat(
                                      'OEM #',
                                      (item['oem'] as String? ?? '').isNotEmpty
                                          ? item['oem'] as String
                                          : (item['itemNum'] as String? ?? '—'),
                                      const Color(0xFF718096),
                                    ),
                                  ],
                                ),
                              ] else ...[
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    _miniStat(
                                      'Order Qty',
                                      '$exp',
                                      const Color(0xFF1a202c),
                                    ),
                                    const SizedBox(width: 12),
                                    _miniStat(
                                      'Rcv Qty',
                                      (item['actualQty'] != null)
                                          ? '${item['actualQty']}'
                                          : '—',
                                      const Color(0xFF1a202c),
                                    ),
                                    const SizedBox(width: 12),
                                    _miniStat(
                                      'OEM #',
                                      (item['oem'] as String? ?? '').isNotEmpty
                                          ? item['oem'] as String
                                          : (item['itemNum'] as String? ?? '—'),
                                      const Color(0xFF718096),
                                    ),
                                  ],
                                ),
                              ],
                              if ((item['remark'] as String? ?? '')
                                  .isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFFBEB),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    item['remark'] as String,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Color(0xFF92400E),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 16),
                    if (status == 'Pending') ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _showReceiveModal(d);
                          },
                          icon: const Icon(Icons.download_outlined, size: 15),
                          label: const Text('Receive Items'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _red,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ] else if (status == 'For Admin Review') ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _red.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _red.withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.hourglass_empty_outlined,
                              size: 16,
                              color: Color(0xFFE8001C),
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Submitted for admin review. Awaiting approval.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFFE8001C),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _showNewDeliveryModal(existing: d);
                          },
                          icon: const Icon(Icons.edit_outlined, size: 15),
                          label: const Text('Edit Request'),
                        ),
                      ),
                    ] else if (status == 'Awaiting Double Check') ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _amber.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _amber.withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.hourglass_empty_outlined,
                              size: 16,
                              color: Color(0xFFd69e2e),
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Submitted for review. Awaiting approval.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFFd69e2e),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _viewRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF718096),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1a202c),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _miniStat(String label, String value, Color valueColor) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: Color(0xFFa0aec0),
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    ),
  );

  Widget _gridCol(String label, String value, {Color? valueColor}) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: Color(0xFFa0aec0),
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: valueColor ?? const Color(0xFF1a202c),
          ),
        ),
      ],
    ),
  );

  Widget _metaChip(String text, IconData icon, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withValues(alpha: 0.15)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    ),
  );

  Widget _field(String label, {required Widget child}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Color(0xFF4a5568),
        ),
      ),
      const SizedBox(height: 4),
      child,
    ],
  );

  // ── Receive Items Modal (per-item) ──────────────────────────
  void _showReceiveModal(Map<String, dynamic> delivery, {int? itemIdx}) async {
    String currentUserName = '';
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      currentUserName = (doc.data()?['name'] as String?) ?? '';
    }
    if (!mounted) return;

    final allItems = List<Map<String, dynamic>>.from(
      (delivery['items'] as List? ?? []).map(
        (i) => Map<String, dynamic>.from(i as Map),
      ),
    );
    int rcvIdx =
        itemIdx ??
        allItems.indexWhere((i) => (i['itemStatus'] ?? 'Pending') == 'Pending');
    if (rcvIdx < 0) rcvIdx = 0;
    final item = allItems[rcvIdx];

    final receivedByCtrl = TextEditingController(text: currentUserName);
    final qtyCtrl = TextEditingController(text: '${item['expectedQty'] ?? 0}');
    String condition = 'OK';
    final remarkCtrl = TextEditingController();
    bool submitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          maxChildSize: 0.97,
          builder: (_, ctrl) => SingleChildScrollView(
            controller: ctrl,
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                  decoration: const BoxDecoration(
                    color: _red,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Receive Item',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: const Icon(Icons.close, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    top: 16,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _itemReceiveCard(
                        index: 0,
                        item: item,
                        expected: item['expectedQty'] as int? ?? 0,
                        qtyCtrl: qtyCtrl,
                        remarkCtrl: remarkCtrl,
                        condition: condition,
                        onCondChange: (c) => setModal(() => condition = c),
                        onQtyChange: () => setModal(() {}),
                      ),
                      const SizedBox(height: 12),
                      _field(
                        'Received By',
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7F8FA),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFe2e8f0)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.person_outline,
                                size: 16,
                                color: Color(0xFF718096),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                receivedByCtrl.text.isNotEmpty
                                    ? receivedByCtrl.text
                                    : '—',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1a202c),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: submitting
                              ? null
                              : () async {
                                  if (receivedByCtrl.text.trim().isEmpty)
                                    return;
                                  setModal(() => submitting = true);
                                  final updatedItems = allItems.toList();
                                  // Fetch current stock to freeze it at receive time
                                  int? stockAtReceive;
                                  try {
                                    final sSnap = await FirebaseFirestore
                                        .instance
                                        .collection('stock_inventory')
                                        .where(
                                          'num',
                                          isEqualTo: item['itemNum'] ?? '',
                                        )
                                        .limit(1)
                                        .get();
                                    if (sSnap.docs.isNotEmpty)
                                      stockAtReceive =
                                          (sSnap.docs.first['stock'] as num?)
                                              ?.toInt();
                                  } catch (_) {}
                                  updatedItems[rcvIdx] = {
                                    ...updatedItems[rcvIdx],
                                    'actualQty':
                                        int.tryParse(qtyCtrl.text) ??
                                        item['expectedQty'],
                                    'condition': condition,
                                    'remark': remarkCtrl.text.trim(),
                                    'itemStatus': 'Awaiting Double Check',
                                    'receivedBy': receivedByCtrl.text.trim(),
                                    'receivedAt': DateTime.now()
                                        .toIso8601String(),
                                    if (stockAtReceive != null)
                                      'stockAtReceive': stockAtReceive,
                                  };
                                  final allReceived = updatedItems.every(
                                    (i) =>
                                        i['itemStatus'] ==
                                            'Awaiting Double Check' ||
                                        i['itemStatus'] == 'Approved',
                                  );
                                  try {
                                    await SyncStatusNotifier.instance.trackWrite(
                                      () => FirebaseFirestore.instance
                                          .collection('deliveries')
                                          .doc(delivery['id'] as String)
                                          .update({
                                            'items': updatedItems,
                                            'receivedBy': receivedByCtrl.text
                                                .trim(),
                                            'status': allReceived
                                                ? 'Awaiting Double Check'
                                                : 'Pending',
                                            'receivedAt':
                                                FieldValue.serverTimestamp(),
                                          }),
                                    );

                                    // ── Notify admin about the received item ──
                                    final itemName =
                                        item['itemName'] as String? ?? '—';
                                    final itemNum =
                                        item['itemNum'] as String? ?? '';
                                    final actualQty =
                                        int.tryParse(qtyCtrl.text) ??
                                        (item['expectedQty'] as int? ?? 0);
                                    final receivedBy = receivedByCtrl.text
                                        .trim();
                                    final condLabel = condition;
                                    final numLabel = itemNum.isNotEmpty
                                        ? ' ($itemNum)'
                                        : '';
                                    final condSuffix = condLabel != 'OK'
                                        ? ' — Condition: $condLabel'
                                        : '';
                                    final notifMsg =
                                        '$receivedBy received $actualQty × $itemName$numLabel.$condSuffix Awaiting admin double-check.';
                                    try {
                                      await FirebaseFirestore.instance
                                          .collection('notifications')
                                          .add({
                                            'title':
                                                '📦 Item Received — Awaiting Review',
                                            'message': notifMsg,
                                            'type': 'info',
                                            'targetRole': 'admin',
                                            'targetUid': '',
                                            'createdAt':
                                                FieldValue.serverTimestamp(),
                                            'readBy': <String, bool>{},
                                            'isRead': false,
                                          });
                                    } catch (
                                      _
                                    ) {} // non-fatal — main receive already succeeded

                                    if (ctx.mounted) {
                                      Navigator.pop(ctx);
                                      ScaffoldMessenger.of(ctx).showSnackBar(
                                        const SnackBar(
                                          content: Text('Submitted!'),
                                          backgroundColor: Colors.orange,
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    }
                                  } catch (err) {
                                    setModal(() => submitting = false);
                                    if (ctx.mounted)
                                      ScaffoldMessenger.of(ctx).showSnackBar(
                                        SnackBar(
                                          content: Text('Error: $err'),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                  }
                                },
                          child: submitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Submit'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _red,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _itemReceiveCard({
    required int index,
    required Map<String, dynamic> item,
    required int expected,
    required TextEditingController qtyCtrl,
    required TextEditingController remarkCtrl,
    required String condition,
    required ValueChanged<String> onCondChange,
    required VoidCallback onQtyChange,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF90cdf4)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: TextSpan(
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: Color(0xFF1a202c),
              ),
              children: [
                TextSpan(text: item['itemName'] as String),
                if ((item['uom'] as String? ?? '').isNotEmpty)
                  TextSpan(
                    text: '  (${item['uom']})',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF718096),
                    ),
                  ),
              ],
            ),
          ),
          Text(
            '${item['supplierCode'] ?? ''} · Order Qty: $expected',
            style: const TextStyle(fontSize: 11, color: Color(0xFF718096)),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: qtyCtrl,
            keyboardType: TextInputType.number,
            onChanged: (_) => onQtyChange(),
            decoration: InputDecoration(
              labelText: 'Actual Qty *',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Condition',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF4a5568),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _condBtn('✅ OK', 'OK', condition, onCondChange),
              const SizedBox(width: 6),
              _condBtn('❌ Defective', 'Defective', condition, onCondChange),
              const SizedBox(width: 6),
              _condBtn('⚠️ Shortage', 'Shortage', condition, onCondChange),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: remarkCtrl,
            decoration: const InputDecoration(
              labelText: 'Remarks (optional)',
              border: OutlineInputBorder(),
              isDense: true,
              hintText: 'e.g. 1 unit damaged packaging',
            ),
          ),
        ],
      ),
    );
  }

  Widget _condBtn(
    String label,
    String value,
    String current,
    ValueChanged<String> onChange,
  ) {
    final active = current == value;
    Color color;
    switch (value) {
      case 'OK':
        color = _green;
        break;
      case 'Defective':
        color = _red;
        break;
      default:
        color = _amber;
    }
    return GestureDetector(
      onTap: () => onChange(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.1) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? color : const Color(0xFFe2e8f0),
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: active ? color : const Color(0xFF718096),
          ),
        ),
      ),
    );
  }
}
