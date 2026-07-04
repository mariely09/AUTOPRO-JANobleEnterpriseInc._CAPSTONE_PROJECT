import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'barcode_scanner_screen.dart';

class StaffReceivingBody extends StatefulWidget {
  final String searchQuery;
  const StaffReceivingBody({super.key, this.searchQuery = ''});
  @override
  State<StaffReceivingBody> createState() => _StaffReceivingBodyState();
}

class _StaffReceivingBodyState extends State<StaffReceivingBody> {
  static const _red   = Color(0xFFE8001C);
  static const _amber = Color(0xFFd69e2e);
  static const _green = Color(0xFF38a169);
  static const _months = [
    'Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec',
  ];

  String _filter = 'all';

  List<Map<String, dynamic>> _deliveries = [];
  bool _loading = true;
  StreamSubscription<QuerySnapshot>? _sub;

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
              .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
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

  Color _statusColor(String s) {
    switch (s) {
      case 'Pending':               return const Color(0xFF718096);
      case 'Awaiting Double Check': return _amber;
      case 'Approved':              return _green;
      case 'Rejected':              return _red;
      default:                      return const Color(0xFF718096);
    }
  }

  Future<void> _scanAndFind() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (!mounted || result == null || result.isEmpty) return;

    final query = result.trim().toLowerCase();

    // Step 1: Look up item master to resolve barcode/QR → itemNum/itemName
    String resolvedNum  = '';
    String resolvedName = '';
    try {
      // Try barcode field first
      var snap = await FirebaseFirestore.instance
          .collection('item_master')
          .where('barcode', isEqualTo: result.trim())
          .limit(1)
          .get();
      if (snap.docs.isEmpty) {
        // Try QR field
        snap = await FirebaseFirestore.instance
            .collection('item_master')
            .where('qr', isEqualTo: result.trim())
            .limit(1)
            .get();
      }
      if (snap.docs.isEmpty) {
        // Try item number field (uppercase)
        snap = await FirebaseFirestore.instance
            .collection('item_master')
            .where('num', isEqualTo: result.trim().toUpperCase())
            .limit(1)
            .get();
      }
      if (snap.docs.isNotEmpty) {
        final d = snap.docs.first.data() as Map<String, dynamic>;
        resolvedNum  = (d['num']  as String? ?? '').toLowerCase();
        resolvedName = (d['name'] as String? ?? '').toLowerCase();
      }
    } catch (_) {}

    if (!mounted) return;

    // Step 2: Search pending deliveries for the resolved item or raw scan value
    final pending = _deliveries.where(
      (d) => (d['status'] as String? ?? 'Pending') == 'Pending',
    ).toList();

    Map<String, dynamic>? found;
    for (final delivery in pending) {
      final items = (delivery['items'] as List? ?? []);
      final match = items.any((i) {
        final num  = (i['itemNum']  as String? ?? '').toLowerCase();
        final name = (i['itemName'] as String? ?? '').toLowerCase();
        // Match against resolved item master values OR raw scan string
        return (resolvedNum.isNotEmpty  && num.contains(resolvedNum))  ||
               (resolvedName.isNotEmpty && name.contains(resolvedName)) ||
               num.contains(query)  ||
               name.contains(query);
      });
      if (match) { found = delivery; break; }
    }

    if (!mounted) return;
    if (found != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Item found in delivery from ${found['supplier']}'),
        backgroundColor: _green, behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      _showReceiveModal(found);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No pending delivery found for that item'),
        backgroundColor: Color(0xFF718096), behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
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

    int pending = 0, awaiting = 0, approved = 0, rejected = 0;
    for (final d in _deliveries) {
      switch (d['status'] as String? ?? 'Pending') {
        case 'Pending':               pending++; break;
        case 'Awaiting Double Check': awaiting++; break;
        case 'Approved':              approved++; break;
        case 'Rejected':              rejected++; break;
      }
    }

    final filtered = _filter == 'all'
        ? searched
        : searched.where((d) => (d['status'] as String? ?? 'Pending') == _filter).toList();

    return Stack(children: [
      Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(children: [
            _chip('Pending',  '$pending',  const Color(0xFF718096), Icons.inventory_outlined,      'Pending'),
            const SizedBox(width: 6),
            _chip('Awaiting', '$awaiting', _amber,  Icons.hourglass_empty_outlined, 'Awaiting Double Check'),
            const SizedBox(width: 6),
            _chip('Approved', '$approved', _green,  Icons.check_circle_outline,     'Approved'),
            const SizedBox(width: 6),
            _chip('Rejected', '$rejected', _red,    Icons.cancel_outlined,          'Rejected'),
          ]),
        ),
        Expanded(
          child: _loading
            ? const Center(child: CircularProgressIndicator())
            : filtered.isEmpty
              ? const Center(child: Text('No deliveries found.', style: TextStyle(color: Color(0xFF718096))))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => GestureDetector(
                    onTap: () => _showViewModal(filtered[i]),
                    child: _deliveryCard(filtered[i]),
                  ),
                ),
        ),
      ]),
      // Scanner FAB
      Positioned(
        bottom: 16, right: 16,
        child: GestureDetector(
          onTap: _scanAndFind,
          child: Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: _red, shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: _red.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: const Icon(Icons.qr_code_scanner, color: Colors.white, size: 28),
          ),
        ),
      ),
    ]);
  }

  Widget _chip(String label, String value, Color color, IconData icon, String filter) {
    final active = _filter == filter;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _filter = active ? 'all' : filter),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: active ? color.withOpacity(0.08) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: active ? color : Colors.transparent, width: 1.5),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
          ),
          child: Column(children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: color, size: 14),
            ),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: const TextStyle(fontSize: 8, color: Color(0xFF718096)), textAlign: TextAlign.center),
          ]),
        ),
      ),
    );
  }

  Widget _deliveryCard(Map<String, dynamic> d) {
    final status = d['status'] as String? ?? 'Pending';
    final color  = _statusColor(status);
    final items  = (d['items'] as List? ?? []);
    final names  = items.map((i) => i['itemName'] as String? ?? '').join(', ');
    final itemCount = items.length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF0F4F8)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(d['supplier'] as String? ?? '—',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF1a202c))),
            const SizedBox(height: 2),
            Text(_fmt(d['date'] as String?),
              style: const TextStyle(fontSize: 12, color: Color(0xFF718096))),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
            child: Text(status, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
          ),
        ]),
        if (names.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(names, style: const TextStyle(fontSize: 12, color: Color(0xFF4a5568)),
            maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
        if ((d['notes'] as String? ?? '').isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(d['notes'] as String, style: const TextStyle(fontSize: 11, color: Color(0xFFa0aec0)),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
        const SizedBox(height: 10),
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F8FA), borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFe2e8f0))),
            child: Text('$itemCount item${itemCount != 1 ? 's' : ''}',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF718096))),
          ),
          if (d['receivedBy'] != null && (d['receivedBy'] as String).isNotEmpty) ...[
            const SizedBox(width: 8),
            const Icon(Icons.person_outline, size: 11, color: Color(0xFF718096)),
            const SizedBox(width: 3),
            Text(d['receivedBy'] as String,
              style: const TextStyle(fontSize: 10, color: Color(0xFF718096))),
          ],
          const Spacer(),
          const Icon(Icons.chevron_right, size: 18, color: Color(0xFFa0aec0)),
        ]),
      ]),
    );
  }

  void _showViewModal(Map<String, dynamic> d) {
    final status = d['status'] as String? ?? 'Pending';
    final color  = _statusColor(status);
    final items  = (d['items'] as List? ?? []);

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => DraggableScrollableSheet(
        expand: false, initialChildSize: 0.6, maxChildSize: 0.92,
        builder: (__, ctrl) => SingleChildScrollView(
          controller: ctrl,
          child: Column(children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              decoration: BoxDecoration(color: color,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
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
                GestureDetector(onTap: () => Navigator.pop(context),
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
                      color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFCD34D))),
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

                  if (status == 'Approved') {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white, borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFe2e8f0)),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6)]),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(item['itemName'] as String? ?? '—',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF1a202c))),
                            Text(item['itemNum'] as String? ?? '',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
                          ])),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: condColor.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                            child: Text(cond, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: condColor)),
                          ),
                        ]),
                        const SizedBox(height: 10),
                        const Divider(height: 1, color: Color(0xFFF0F4F8)),
                        const SizedBox(height: 10),
                        Row(children: [
                          _gridCol('EXPECTED', '$exp ${item['uom'] ?? ''}'),
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

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white, borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFe2e8f0)),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 4)]),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(item['itemName'] as String? ?? '—',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                          Text(item['itemNum'] as String? ?? '',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
                        ])),
                        if (cond != '—')
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: condColor.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                            child: Text(cond, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: condColor)),
                          ),
                      ]),
                      const SizedBox(height: 6),
                      Row(children: [
                        _reviewCol('Expected', '$exp ${item['uom'] ?? ''}'),
                        if (actual != null)
                          _reviewCol('Actual',
                            '$actual ${item['uom'] ?? ''}${diff != null && diff != 0 ? ' (${diff > 0 ? '+' : ''}$diff)' : ''}',
                            valueColor: diff != null && diff != 0 ? (diff < 0 ? _red : _amber) : null),
                        if ((item['remark'] as String? ?? '').isNotEmpty)
                          _reviewCol('Remarks', item['remark'] as String),
                      ]),
                    ]),
                  );
                }),
                const SizedBox(height: 16),
                if (status == 'Pending') ...[
                  SizedBox(width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () { Navigator.pop(context); _showReceiveModal(d); },
                      icon: const Icon(Icons.download_outlined, size: 15),
                      label: const Text('Receive Items'),
                      style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white),
                    )),
                ] else if (status == 'Awaiting Double Check') ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _amber.withOpacity(0.08), borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _amber.withOpacity(0.3))),
                    child: const Row(children: [
                      Icon(Icons.hourglass_empty_outlined, size: 16, color: Color(0xFFd69e2e)),
                      SizedBox(width: 8),
                      Expanded(child: Text('Submitted for admin double check. Awaiting approval.',
                        style: TextStyle(fontSize: 12, color: Color(0xFFd69e2e), fontWeight: FontWeight.w500))),
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

  Widget _viewRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 100, child: Text(label,
        style: const TextStyle(fontSize: 12, color: Color(0xFF718096), fontWeight: FontWeight.w500))),
      Expanded(child: Text(value,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1a202c)))),
    ]),
  );

  Widget _reviewCol(String label, String value, {Color? valueColor}) => Expanded(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFFa0aec0), letterSpacing: 0.4)),
      const SizedBox(height: 2),
      Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: valueColor ?? const Color(0xFF1a202c))),
    ]),
  );

  Widget _gridCol(String label, String value, {Color? valueColor}) => Expanded(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFFa0aec0), letterSpacing: 0.4)),
      const SizedBox(height: 3),
      Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: valueColor ?? const Color(0xFF1a202c))),
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

  void _showReceiveModal(Map<String, dynamic> delivery) async {
    String currentUserName = '';
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      currentUserName = (doc.data()?['name'] as String?) ?? '';
    }
    if (!mounted) return;

    final items = List<Map<String, dynamic>>.from(
      (delivery['items'] as List? ?? []).map((i) => Map<String, dynamic>.from(i as Map)));
    final receivedByCtrl = TextEditingController(text: currentUserName);
    final qtyCtrlrs = List.generate(items.length, (i) =>
        TextEditingController(text: '${items[i]['expectedQty'] ?? 0}'));
    final conditionList = List<String>.filled(items.length, 'OK');
    final remarkCtrlrs = List.generate(items.length, (_) => TextEditingController());

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) => DraggableScrollableSheet(
          expand: false, initialChildSize: 0.92, maxChildSize: 0.97,
          builder: (_, ctrl) => SingleChildScrollView(
            controller: ctrl,
            child: Column(children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                decoration: const BoxDecoration(color: _red,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                child: Row(children: [
                  Container(width: 44, height: 44,
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.download_outlined, color: Colors.white, size: 22)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Receive Items',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    Text('${delivery['supplier']} · ${_fmt(delivery['date'] as String?)}',
                      style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  ])),
                  GestureDetector(onTap: () => Navigator.pop(ctx),
                    child: const Icon(Icons.close, color: Colors.white)),
                ]),
              ),
              Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(children: [
                  _step('1', 'Input Quantities', active: true),
                  const Expanded(child: Divider()),
                  _step('2', 'Awaiting Check'),
                  const Expanded(child: Divider()),
                  _step('3', 'Approved'),
                ]),
              ),
              Padding(
                padding: EdgeInsets.only(left: 20, right: 20, top: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ...items.asMap().entries.map((e) {
                    final i = e.key;
                    final item = e.value;
                    final expected = item['expectedQty'] as int? ?? 0;
                    return _itemReceiveCard(
                      index: i, item: item, expected: expected,
                      qtyCtrl: qtyCtrlrs[i], remarkCtrl: remarkCtrlrs[i],
                      condition: conditionList[i],
                      onCondChange: (c) => setModal(() => conditionList[i] = c),
                      onQtyChange: () => setModal(() {}));
                  }),
                  const SizedBox(height: 12),
                  _field('Received By (Your Name) *', child: TextField(
                    controller: receivedByCtrl,
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true,
                      hintText: 'Enter your full name'))),
                  const SizedBox(height: 20),
                  SizedBox(width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        if (receivedByCtrl.text.trim().isEmpty) return;
                        final updatedItems = items.asMap().entries.map((e) {
                          final i = e.key;
                          return {
                            ...e.value,
                            'actualQty': int.tryParse(qtyCtrlrs[i].text) ?? e.value['expectedQty'],
                            'condition': conditionList[i],
                            'remark': remarkCtrlrs[i].text.trim(),
                          };
                        }).toList();
                        try {
                          await FirebaseFirestore.instance.collection('deliveries')
                              .doc(delivery['id'] as String).update({
                            'items': updatedItems,
                            'receivedBy': receivedByCtrl.text.trim(),
                            'status': 'Awaiting Double Check',
                            'receivedAt': FieldValue.serverTimestamp(),
                          });
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text('Submitted for double check!'),
                              backgroundColor: Colors.orange, behavior: SnackBarBehavior.floating));
                          }
                        } catch (err) {
                          if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('Error: $err'), backgroundColor: Colors.red));
                        }
                      },
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: const Text('Submit for Double Check'),
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

  Widget _step(String num, String label, {bool active = false}) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 22, height: 22,
        decoration: BoxDecoration(
          color: active ? _red : const Color(0xFFe2e8f0), shape: BoxShape.circle),
        child: Center(child: Text(num, style: TextStyle(
          color: active ? Colors.white : const Color(0xFF718096),
          fontWeight: FontWeight.w700, fontSize: 11))),
      ),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(fontSize: 8, color: Color(0xFF718096)), textAlign: TextAlign.center),
    ],
  );

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
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF90cdf4)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(item['itemName'] as String,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        Text('${item['itemNum']} · Expected: $expected ${item['uom'] ?? ''}',
          style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
        const SizedBox(height: 10),
        TextField(
          controller: qtyCtrl, keyboardType: TextInputType.number,
          onChanged: (_) => onQtyChange(),
          decoration: InputDecoration(
            labelText: 'Actual Qty *', border: const OutlineInputBorder(), isDense: true,
            suffixText: item['uom'] as String? ?? '')),
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
          color: active ? color.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? color : const Color(0xFFe2e8f0), width: 1.5)),
        child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
          color: active ? color : const Color(0xFF718096))),
      ),
    );
  }
}
