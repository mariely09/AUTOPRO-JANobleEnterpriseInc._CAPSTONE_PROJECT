import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';

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

class AdminReceivingBodyState extends State<AdminReceivingBody> {
  static const _red   = Color(0xFFE8001C);
  static const _blue  = Color(0xFF003087);
  static const _amber = Color(0xFFd69e2e);
  static const _green = Color(0xFF38a169);
  static const _months = [
    'Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec',
  ];

  String _filter = 'all';
  bool _fabOpen = false;

  // Stream subscription — subscribed once in initState, never recreated
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
              .map((d) => {...d.data(), 'id': d.id})
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

  @override
  Widget build(BuildContext context) {
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
      // ── Main list area ──
      Column(children: [
        // Filter chips
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
        // List body
        Expanded(
          child: _loading
            ? const Center(child: CircularProgressIndicator())
            : filtered.isEmpty
              ? const Center(child: Text('No deliveries found.', style: TextStyle(color: Color(0xFF718096))))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final d = filtered[i];
                    return GestureDetector(
                      onTap: () => _showViewModal(d),
                      child: _deliveryCard(d),
                    );
                  },
                ),
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
                label: 'Compare PO / Invoice',
                icon: Icons.table_chart_outlined,
                onTap: () { setState(() => _fabOpen = false); _showCompareModal(); },
              ),
              const SizedBox(height: 10),
              _fabAction(
                label: 'New Delivery',
                icon: Icons.download_outlined,
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
                  color: _red,
                  shape: BoxShape.circle,
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

  Widget _chip(String label, String value, Color color, IconData icon, String filter) {
    final active = _filter == filter;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _filter = active ? 'all' : filter),
        child: Container(
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
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Header row: supplier + status badge ──
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
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(status,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
            ),
          ]),
          // ── Items preview ──
          if (names.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(names,
              style: const TextStyle(fontSize: 12, color: Color(0xFF4a5568)),
              maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
          if ((d['notes'] as String? ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(d['notes'] as String,
              style: const TextStyle(fontSize: 11, color: Color(0xFFa0aec0)),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 10),
          // ── Footer: item count + received by + chevron ──
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F8FA),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFe2e8f0)),
              ),
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

  Widget _fabAction({required String label, required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1a202c))),
        ),
        const SizedBox(width: 10),
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Icon(icon, color: _red, size: 20),
        ),
      ]),
    );
  }

  // ── View Delivery Modal ─────────────────────────────────────
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
                            Text(item['itemNum'] as String? ?? '',
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

                  // Other statuses: simple card
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white, borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFe2e8f0)),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4)],
                    ),
                    child: Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(item['itemName'] as String? ?? '—',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        Text(item['itemNum'] as String? ?? '',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
                        if ((item['remark'] as String? ?? '').isNotEmpty)
                          Text(item['remark'] as String,
                            style: const TextStyle(fontSize: 10, color: Color(0xFFa0aec0))),
                      ])),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text('Expected: $exp ${item['uom'] ?? ''}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
                      ]),
                    ]),
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
                      onPressed: () { Navigator.pop(context); _confirmDelete(d); },
                      icon: const Icon(Icons.delete_outline, size: 15, color: Colors.red),
                      label: const Text('Delete', style: TextStyle(color: Colors.red)),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                    )),
                ] else if (status == 'Awaiting Double Check') ...[
                  Row(children: [
                    Expanded(child: OutlinedButton.icon(
                      onPressed: () { Navigator.pop(context); _confirmDelete(d); },
                      icon: const Icon(Icons.delete_outline, size: 15, color: Colors.red),
                      label: const Text('Delete', style: TextStyle(color: Colors.red)),
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
                      onPressed: () { Navigator.pop(context); _confirmDelete(d); },
                      icon: const Icon(Icons.delete_outline, size: 15, color: Colors.red),
                      label: const Text('Delete', style: TextStyle(color: Colors.red)),
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

  // ── Compare PO vs Invoice Modal ───────────────────────────
  void _showCompareModal() {
    File? poFile;
    File? invFile;
    final notesCtrl = TextEditingController();
    Map<String, dynamic>? linkedDelivery;
    final picker = ImagePicker();

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) {
          Future<void> pickImage(bool isPo) async {
            final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
            if (picked == null) return;
            setModal(() {
              if (isPo) {
                poFile = File(picked.path);
              } else {
                invFile = File(picked.path);
              }
            });
          }

          Widget imageZone({required String title, required String subtitle, required File? file, required bool isPo}) {
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1a202c)),
                      overflow: TextOverflow.ellipsis),
                    Text(subtitle, style: const TextStyle(fontSize: 10, color: Color(0xFF718096)),
                      overflow: TextOverflow.ellipsis),
                  ]),
                ),
                if (file != null) ...[
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => setModal(() {
                      if (isPo) {
                        poFile = null;
                      } else {
                        invFile = null;
                      }
                    }),
                    child: const Text('✕', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.red)),
                  ),
                ],
              ]),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => pickImage(isPo),
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(minHeight: 140),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: file != null ? _red : const Color(0xFFcbd5e0), width: 1.5, style: BorderStyle.solid),
                  ),
                  child: file != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(13),
                        child: Image.file(file, fit: BoxFit.cover))
                    : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const SizedBox(height: 24),
                        Icon(Icons.cloud_upload_outlined, size: 36, color: Colors.grey.shade400),
                        const SizedBox(height: 8),
                        Text('Tap to upload ${isPo ? 'PO' : 'Invoice'}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF718096))),
                        const Text('PNG, JPG supported', style: TextStyle(fontSize: 11, color: Color(0xFFa0aec0))),
                        const SizedBox(height: 24),
                      ]),
                ),
              ),
            ]);
          }

          return DraggableScrollableSheet(
            expand: false, initialChildSize: 0.92, maxChildSize: 0.97,
            builder: (_, ctrl) => SingleChildScrollView(
              controller: ctrl,
              child: Column(children: [
                // Header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                  decoration: const BoxDecoration(
                    color: _red,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                  child: Row(children: [
                    Container(width: 44, height: 44,
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.table_chart_outlined, color: Colors.white, size: 22)),
                    const SizedBox(width: 12),
                    const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Compare PO vs Invoice', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      Text('Upload images to compare side by side', style: TextStyle(color: Colors.white70, fontSize: 11)),
                    ])),
                    GestureDetector(onTap: () => Navigator.pop(ctx), child: const Icon(Icons.close, color: Colors.white)),
                  ]),
                ),
                // Info banner
                Container(
                  color: const Color(0xFFEFF6FF),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: const Row(children: [
                    Icon(Icons.info_outline, size: 14, color: Color(0xFF1E40AF)),
                    SizedBox(width: 8),
                    Expanded(child: Text(
                      'Images are kept locally and not stored on the server.',
                      style: TextStyle(fontSize: 11, color: Color(0xFF1E40AF)))),
                  ]),
                ),
                Padding(
                  padding: EdgeInsets.only(left: 20, right: 20, top: 20,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 24),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // Link to delivery (optional)
                    const Text('Link to Delivery', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF4a5568))),
                    const Text('Optional', style: TextStyle(fontSize: 11, color: Color(0xFF718096))),
                    const SizedBox(height: 8),
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance.collection('deliveries').orderBy('createdAt', descending: true).limit(20).snapshots(),
                      builder: (ctx2, snap) {
                        final docs = snap.data?.docs ?? [];
                        return DropdownButtonFormField<String>(
                          initialValue: linkedDelivery?['id'] as String?,
                          decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, hintText: '— Select a delivery —'),
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem(value: null, child: Text('— None —')),
                            ...docs.map((d) {
                              final data = d.data() as Map<String, dynamic>;
                              return DropdownMenuItem(
                                value: d.id,
                                child: Text('${data['supplier'] ?? '—'}  (${data['status'] ?? ''})',
                                  overflow: TextOverflow.ellipsis));
                            }),
                          ],
                          onChanged: (id) {
                            if (id == null) { setModal(() => linkedDelivery = null); return; }
                            final doc = docs.firstWhere((d) => d.id == id);
                            final data = doc.data() as Map<String, dynamic>;
                            setModal(() {
                              linkedDelivery = {...data, 'id': id};
                              if ((data['reviewNotes'] as String? ?? '').isNotEmpty) {
                                notesCtrl.text = data['reviewNotes'] as String;
                              }
                            });
                          },
                          borderRadius: BorderRadius.circular(10),
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    // Side-by-side images
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: imageZone(
                        title: '📄 Purchase Order', subtitle: 'Your internal PO copy',
                        file: poFile, isPo: true)),
                      const SizedBox(width: 12),
                      Expanded(child: imageZone(
                        title: '🧾 Supplier Invoice', subtitle: 'Invoice from supplier',
                        file: invFile, isPo: false)),
                    ]),
                    const SizedBox(height: 16),
                    // Comparison notes
                    const Text('Comparison Notes', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF4a5568))),
                    const SizedBox(height: 6),
                    TextField(
                      controller: notesCtrl, maxLines: 3,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(), isDense: true,
                        hintText: 'e.g. Invoice item 3 price differs from PO — ₱741 vs ₱760...',
                        hintStyle: TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(height: 20),
                    // Buttons
                    Row(children: [
                      Expanded(child: ElevatedButton.icon(
                        onPressed: linkedDelivery == null || notesCtrl.text.trim().isEmpty ? null : () async {
                          await FirebaseFirestore.instance
                              .collection('deliveries').doc(linkedDelivery!['id'] as String)
                              .update({'compareNotes': notesCtrl.text.trim()});
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                              content: Text('Notes saved to delivery.'),
                              backgroundColor: Colors.green, behavior: SnackBarBehavior.floating));
                          }
                        },
                        icon: const Icon(Icons.save_outlined, size: 15),
                        label: const Text('Save Notes'),
                        style: ElevatedButton.styleFrom(backgroundColor: _blue, foregroundColor: Colors.white),
                      )),
                    ]),
                  ]),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  // ── New / Edit Delivery Modal ──────────────────────────────
  void _showNewDeliveryModal({Map<String, dynamic>? existing}) async {
    final isEdit = existing != null;
    final dateCtrl     = TextEditingController(text: existing?['date'] as String? ?? DateTime.now().toIso8601String().split('T')[0]);
    final supplierCtrl = TextEditingController(text: existing?['supplier'] as String? ?? '');
    final notesCtrl    = TextEditingController(text: existing?['notes']    as String? ?? '');
    final searchCtrl   = TextEditingController();

    // Load item master for searching
    final masterSnap = await FirebaseFirestore.instance.collection('item_master').orderBy('name').get();
    final masterItems = masterSnap.docs.map((d) {
      final data = d.data();
      return {'num': data['num'] as String? ?? '', 'name': data['name'] as String? ?? '', 'uom': data['uom'] as String? ?? ''};
    }).toList();

    List<Map<String, dynamic>> addedItems = List<Map<String, dynamic>>.from(
      (existing?['items'] as List? ?? []).map((i) => Map<String, dynamic>.from(i as Map)),
    );
    Map<String, dynamic>? foundItem;
    final expectedCtrl = TextEditingController();

    if (!mounted) return;

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) {
          void searchItem(String q) {
            final lower = q.trim().toLowerCase();
            if (lower.isEmpty) { setModal(() => foundItem = null); return; }
            final match = masterItems.firstWhere(
              (i) => (i['name'] as String).toLowerCase().contains(lower) ||
                     (i['num']  as String).toLowerCase().contains(lower),
              orElse: () => {},
            );
            setModal(() => foundItem = match.isNotEmpty ? match : null);
          }

          return DraggableScrollableSheet(
            expand: false, initialChildSize: 0.92, maxChildSize: 0.97,
            builder: (_, ctrl) => SingleChildScrollView(
              controller: ctrl,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                  decoration: const BoxDecoration(color: _red, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                  child: Row(children: [
                    Container(width: 44, height: 44,
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(12)),
                      child: Icon(isEdit ? Icons.edit_outlined : Icons.add, color: Colors.white, size: 22)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(isEdit ? 'Edit Delivery' : 'New Delivery',
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      const Text('Record incoming stock delivery',
                        style: TextStyle(color: Colors.white70, fontSize: 11)),
                    ])),
                    GestureDetector(onTap: () => Navigator.pop(ctx), child: const Icon(Icons.close, color: Colors.white)),
                  ]),
                ),
                Padding(
                  padding: EdgeInsets.only(left: 20, right: 20, top: 20,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 24),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // Date + Supplier
                    Row(children: [
                      Expanded(child: _field('Delivery Date *', child: TextField(
                        controller: dateCtrl, readOnly: true,
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(), isDense: true,
                          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
                        ),
                        onTap: () async {
                          final today = DateTime.now();
                          final initial = DateTime.tryParse(dateCtrl.text) ?? today;
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: initial.isBefore(today) ? today : initial,
                            firstDate: today, lastDate: DateTime(2030),
                            builder: (c, child) => Theme(data: Theme.of(c).copyWith(colorScheme: const ColorScheme.light(primary: _red)), child: child!),
                          );
                          if (picked != null) dateCtrl.text = picked.toIso8601String().split('T')[0];
                        },
                      ))),
                    ]),
                    const SizedBox(height: 10),
                    _field('Supplier / Reference *', child: TextField(controller: supplierCtrl,
                      decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, hintText: 'e.g. HNP AutoParts'))),
                    const SizedBox(height: 10),
                    _field('Notes', child: TextField(controller: notesCtrl,
                      decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, hintText: 'Optional notes'))),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 12),
                    // Item search
                    const Text('Add Items', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1a202c))),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: TextField(
                        controller: searchCtrl,
                        onChanged: searchItem,
                        decoration: const InputDecoration(
                          hintText: 'Search item name or number...',
                          border: OutlineInputBorder(), isDense: true,
                          prefixIcon: Icon(Icons.search, size: 18),
                        ),
                      )),
                    ]),
                    if (foundItem != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: const Color(0xFFebf8ff), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF90cdf4))),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            const Icon(Icons.inventory_2_outlined, size: 16, color: _blue),
                            const SizedBox(width: 8),
                            Expanded(child: Text(foundItem!['name'] as String, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                          ]),
                          Text('${foundItem!['num']} · ${foundItem!['uom']}', style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
                          const SizedBox(height: 8),
                          Row(children: [
                            Expanded(child: TextField(
                              controller: expectedCtrl,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'Expected Qty *',
                                border: const OutlineInputBorder(), isDense: true,
                                suffixText: foundItem!['uom'] as String,
                              ),
                            )),
                            const SizedBox(width: 10),
                            ElevatedButton(
                              onPressed: () {
                                final qty = int.tryParse(expectedCtrl.text.trim()) ?? 0;
                                if (qty <= 0) return;
                                final already = addedItems.any((i) => i['itemNum'] == foundItem!['num']);
                                if (already) return;
                                setModal(() {
                                  addedItems.add({
                                    'itemNum': foundItem!['num'],
                                    'itemName': foundItem!['name'],
                                    'uom': foundItem!['uom'],
                                    'expectedQty': qty,
                                  });
                                  foundItem = null;
                                  searchCtrl.clear();
                                  expectedCtrl.clear();
                                });
                              },
                              style: ElevatedButton.styleFrom(backgroundColor: _blue, foregroundColor: Colors.white),
                              child: const Text('Add'),
                            ),
                          ]),
                        ]),
                      ),
                    ],
                    if (addedItems.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text('${addedItems.length} item${addedItems.length != 1 ? 's' : ''} added',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
                      const SizedBox(height: 6),
                      ...addedItems.asMap().entries.map((e) => Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(color: const Color(0xFFF7F8FA), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFe2e8f0))),
                        child: Row(children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(e.value['itemName'] as String, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                            Text('${e.value['itemNum']} · Expected: ${e.value['expectedQty']} ${e.value['uom']}',
                              style: const TextStyle(fontSize: 10, color: Color(0xFF718096))),
                          ])),
                          GestureDetector(
                            onTap: () => setModal(() => addedItems.removeAt(e.key)),
                            child: const Icon(Icons.close, size: 16, color: Colors.red),
                          ),
                        ]),
                      )),
                    ],
                    const SizedBox(height: 20),
                    Row(children: [
                      Expanded(child: ElevatedButton(
                        onPressed: () async {
                          if (dateCtrl.text.isEmpty || supplierCtrl.text.trim().isEmpty) return;
                          if (addedItems.isEmpty) return;
                          final data = <String, dynamic>{
                            'date': dateCtrl.text,
                            'supplier': supplierCtrl.text.trim(),
                            'notes': notesCtrl.text.trim(),
                            'items': addedItems,
                          };
                          try {
                            if (isEdit) {
                              await FirebaseFirestore.instance.collection('deliveries').doc(existing['id'] as String).update(data);
                            } else {
                              data['status'] = 'Pending';
                              data['createdAt'] = FieldValue.serverTimestamp();
                              await FirebaseFirestore.instance.collection('deliveries').add(data);
                            }
                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                                content: Text(isEdit ? 'Delivery updated!' : 'Delivery created!'),
                                backgroundColor: Colors.green, behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
                            }
                          } catch (e) {
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.save_outlined, size: 16), const SizedBox(width: 6),
                          Text(isEdit ? 'Update' : 'Save Delivery'),
                        ]),
                      )),
                    ]),
                  ]),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _field(String label, {required Widget child}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF4a5568))),
      const SizedBox(height: 4),
      child,
    ],
  );

  /// Called externally (e.g. from AdminInventoryHub via GlobalKey) to open the receive modal directly.
  void openReceiveModal(Map<String, dynamic> delivery) => _showReceiveModal(delivery);

  // ── Receive Items Modal (Step 1) ───────────────────────────
  void _showReceiveModal(Map<String, dynamic> delivery) async {
    // Pre-fill Received By with the logged-in user's name
    String currentUserName = '';
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      currentUserName = (doc.data()?['name'] as String?) ?? '';
    }
    if (!mounted) return;

    final items = List<Map<String, dynamic>>.from(
      (delivery['items'] as List? ?? []).map((i) => Map<String, dynamic>.from(i as Map)),
    );
    final receivedByCtrl = TextEditingController(text: currentUserName);
    // Controllers for actual qty per item
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
              // Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                decoration: const BoxDecoration(color: _red, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                child: Row(children: [
                  Container(width: 44, height: 44,
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.download_outlined, color: Colors.white, size: 22)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Receive Items', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    Text('${delivery['supplier']} · ${_fmt(delivery['date'] as String?)}',
                      style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  ])),
                  GestureDetector(onTap: () => Navigator.pop(ctx), child: const Icon(Icons.close, color: Colors.white)),
                ]),
              ),
              // Step indicator
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
                      qtyCtrl: qtyCtrlrs[i],
                      remarkCtrl: remarkCtrlrs[i],
                      condition: conditionList[i],
                      onCondChange: (c) => setModal(() => conditionList[i] = c),
                      onQtyChange: () => setModal(() {}),
                    );
                  }),
                  const SizedBox(height: 12),
                  _field('Received By', child: Container(
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
                        receivedByCtrl.text.isNotEmpty ? receivedByCtrl.text : '—',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1a202c)),
                      ),
                    ]),
                  )),
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(flex: 2, child: ElevatedButton.icon(
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
                          await FirebaseFirestore.instance.collection('deliveries').doc(delivery['id'] as String).update({
                            'items': updatedItems,
                            'receivedBy': receivedByCtrl.text.trim(),
                            'status': 'Awaiting Double Check',
                            'receivedAt': FieldValue.serverTimestamp(),
                          });
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                              content: Text('Submitted for double check!'),
                              backgroundColor: Colors.orange, behavior: SnackBarBehavior.floating));
                          }
                        } catch (err) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(content: Text('Error: $err'), backgroundColor: Colors.red));
                          }
                        }
                      },
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: const Text('Submit for Double Check'),
                      style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white),
                    )),
                  ]),
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
          color: active ? _red : const Color(0xFFe2e8f0),
          shape: BoxShape.circle),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF90cdf4)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(item['itemName'] as String, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        Text('${item['itemNum']} · Expected: $expected ${item['uom'] ?? ''}',
          style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(
            controller: qtyCtrl, keyboardType: TextInputType.number,
            onChanged: (_) => onQtyChange(),
            decoration: InputDecoration(
              labelText: 'Actual Qty *', border: const OutlineInputBorder(), isDense: true,
              suffixText: item['uom'] as String? ?? ''),
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

  // ── Review / Verify Modal (Step 2→3) ──────────────────────
  void _showReviewModal(Map<String, dynamic> delivery) async {
    final status = delivery['status'] as String? ?? 'Awaiting Double Check';
    final isReadOnly = status == 'Approved' || status == 'Rejected';

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
      text: isReadOnly ? (delivery['checkedBy'] as String? ?? '') : currentUserName);
    final notesCtrl = TextEditingController(text: delivery['reviewNotes'] as String? ?? '');
    final items = List<Map<String, dynamic>>.from(
      (delivery['items'] as List? ?? []).map((i) => Map<String, dynamic>.from(i as Map)),
    );

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => DraggableScrollableSheet(
        expand: false, initialChildSize: 0.92, maxChildSize: 0.97,
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
                  Text(isReadOnly ? 'Delivery Details' : 'Review & Verify',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  Text('${delivery['supplier']} · ${_fmt(delivery['date'] as String?)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 11)),
                ])),
                GestureDetector(onTap: () => Navigator.pop(context), child: const Icon(Icons.close, color: Colors.white)),
              ]),
            ),
            // Warning banner (only for Awaiting Double Check)
            if (status == 'Awaiting Double Check')
              Container(
                color: const Color(0xFFFFFBEB),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(children: const [
                  Icon(Icons.warning_amber_outlined, color: Color(0xFF92400E), size: 16),
                  SizedBox(width: 8),
                  Expanded(child: Text(
                    'Approving will automatically update Stock Inventory and log transactions.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF92400E)))),
                ]),
              ),
            Padding(
              padding: EdgeInsets.only(left: 20, right: 20, top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Item review cards
                ...items.map((item) {
                  final cond  = item['condition'] as String? ?? '—';
                  final actual = item['actualQty'];
                  final exp   = item['expectedQty'] as int? ?? 0;
                  final diff  = actual != null ? (actual as int) - exp : null;
                  Color cc;
                  switch (cond) {
                    case 'OK':        cc = _green; break;
                    case 'Defective': cc = _red;   break;
                    case 'Shortage':  cc = _amber;  break;
                    default:          cc = const Color(0xFF718096);
                  }
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white, borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFe2e8f0)),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)]),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(item['itemName'] as String, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                          Text(item['itemNum'] as String, style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
                        ])),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: cc.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                          child: Text(cond, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cc)),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        _reviewCol('Expected', '$exp ${item['uom'] ?? ''}'),
                        _reviewCol('Actual',
                          actual != null ? '$actual ${item['uom'] ?? ''}${diff != null && diff != 0 ? ' (${diff > 0 ? '+' : ''}$diff)' : ''}' : '—',
                          valueColor: actual != null && diff != 0 ? (diff! < 0 ? _red : _amber) : null),
                        _reviewCol('Remarks', (item['remark'] as String? ?? '').isEmpty ? '—' : item['remark'] as String),
                      ]),
                    ]),
                  );
                }),
                const SizedBox(height: 4),
                // Received by
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFF7F8FA), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFe2e8f0))),
                  child: Row(children: [
                    const SizedBox(width: 80, child: Text('Received By', style: TextStyle(fontSize: 11, color: Color(0xFF718096)))),
                    Expanded(child: Text(delivery['receivedBy'] as String? ?? '—',
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
                        Expanded(child: Text(delivery['checkedBy'] as String? ?? '—',
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
                        Text((delivery['reviewNotes'] as String? ?? '').isEmpty ? 'No notes.' : delivery['reviewNotes'] as String,
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
                      onPressed: () => _submitReview(delivery, 'Rejected', checkedByCtrl.text, notesCtrl.text),
                      icon: const Icon(Icons.cancel_outlined, size: 16, color: Colors.red),
                      label: const Text('Reject', style: TextStyle(color: Colors.red)),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                    )),
                    const SizedBox(width: 12),
                    Expanded(flex: 2, child: ElevatedButton.icon(
                      onPressed: () => _submitReview(delivery, 'Approved', checkedByCtrl.text, notesCtrl.text),
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: const Text('Approve & Update Stock'),
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

  Future<void> _submitReview(Map<String, dynamic> delivery, String decision, String checkedBy, String notes) async {
    if (checkedBy.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please enter your name.'), backgroundColor: Colors.orange));
      return;
    }
    final docId = delivery['id'] as String;
    final items = List<Map<String, dynamic>>.from(
      (delivery['items'] as List? ?? []).map((i) => Map<String, dynamic>.from(i as Map)));
    try {
      if (decision == 'Approved') {
        for (final item in items) {
          final actual = (item['actualQty'] as int?) ?? 0;
          if (actual <= 0) continue;
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
              'desc': 'Stock received — ${delivery['supplier']}',
              'type': 'IN', 'qty': '+$actual', 'date': dateStr,
              'by': checkedBy, 'createdAt': FieldValue.serverTimestamp(),
            });
          } else {
            await FirebaseFirestore.instance.collection('stock_inventory').add({
              'num': num, 'name': item['itemName'], 'uom': item['uom'] ?? '',
              'stock': actual, 'min': 0, 'max': 0, 'reorder': 0, 'status': 'OK',
              'createdAt': FieldValue.serverTimestamp(), 'updatedAt': FieldValue.serverTimestamp(),
            });
            // No transaction logged for initial stock received
          }
        }
      }
      await FirebaseFirestore.instance.collection('deliveries').doc(docId).update({
        'status': decision, 'checkedBy': checkedBy.trim(),
        'reviewNotes': notes.trim(), 'reviewedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(decision == 'Approved'
            ? '✅ Approved! Stock inventory updated.'
            : '❌ Rejected. Revision requested.'),
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

  void _confirmDelete(Map<String, dynamic> d) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Delivery'),
        content: Text('Delete delivery from "${d['supplier']}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await FirebaseFirestore.instance.collection('deliveries').doc(d['id'] as String).delete();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: const Text('Delivery deleted.'), backgroundColor: Colors.red,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}


