import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'sync_indicator.dart';
import 'admin_bottomnavbar.dart';
import 'admin_dashboard.dart';
import 'admin_inventory_hub.dart';
import 'admin_vehicles_list.dart';
import 'profile.dart';

// ═══════════════════════════════════════════════════════════════════════════
// AdminPO — Purchase Orders screen
// Mirrors admin_PO.html: 7 statuses, card grid, stat chips, speed-dial FAB,
// view/edit/create bottom-sheet modals, all status transition actions.
// ═══════════════════════════════════════════════════════════════════════════

class AdminPO extends StatelessWidget {
  const AdminPO({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF004B5F), Color(0xFFEE152A)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(
                      Icons.arrow_back_ios,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Purchase Orders',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.receipt_long_outlined,
                    color: Colors.white70,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: const AdminPOBody(),
      bottomNavigationBar: AdminBottomNavBar(
        currentIndex: 1,
        onTap: (i) {
          if (i == 0) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const AdminDashboard()),
            );
          } else if (i == 1) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => const AdminInventoryHub(initialTab: 3),
              ),
            );
          } else if (i == 2) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const AdminVehiclesList()),
            );
          } else if (i == 3) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => const UserProfile(role: UserRole.admin),
              ),
            );
          }
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// AdminPOBody
// ═══════════════════════════════════════════════════════════════════════════

class AdminPOBody extends StatefulWidget {
  const AdminPOBody({super.key});

  @override
  State<AdminPOBody> createState() => AdminPOBodyState();
}

class AdminPOBodyState extends State<AdminPOBody>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // ── Colours ──────────────────────────────────────────────────────────────
  static const _red = Color(0xFFE8001C);
  static const _amber = Color(0xFFd69e2e);
  static const _green = Color(0xFF38a169);
  static const _blue = Color(0xFF003087);
  static const _grey = Color(0xFF718096);

  // ── Months helper ────────────────────────────────────────────────────────
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

  // ── Firestore collection ─────────────────────────────────────────────────
  static const _col = 'purchase_orders';

  // ── State ────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _pos = [];
  bool _loading = true;
  StreamSubscription<QuerySnapshot>? _sub;

  String _filter = 'all';

  // ── Lifecycle ────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _sub = FirebaseFirestore.instance
        .collection(_col)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snap) {
          if (mounted) {
            setState(() {
              _pos = snap.docs
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

  // ── Helpers ───────────────────────────────────────────────────────────────
  String _fmt(dynamic raw) {
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

  String _fmtPeso(dynamic v) {
    if (v == null) return '₱0.00';
    final d =
        double.tryParse(
          v.toString().replaceAll('₱', '').replaceAll(',', '').trim(),
        ) ??
        0;
    final parts = d.toStringAsFixed(2).split('.');
    final intPart = parts[0].replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return '₱$intPart.${parts[1]}';
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'Draft':
        return _grey;
      case 'Pending Approval':
        return _amber;
      case 'Approved':
        return _green;
      case 'Ordered':
        return _blue;
      case 'Partially Received':
        return _amber;
      case 'Completed':
        return _green;
      case 'Cancelled':
        return _red;
      default:
        return _grey;
    }
  }

  /// Generate PO number: PO-YYYYMMDD-XXXX (sequential per day)
  Future<String> _genPoNum() async {
    final now = DateTime.now();
    final dateStr =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final prefix = 'PO-$dateStr-';
    final snap = await FirebaseFirestore.instance
        .collection(_col)
        .where('poNum', isGreaterThanOrEqualTo: prefix)
        .where('poNum', isLessThan: '${prefix}z')
        .get();
    final seq = snap.docs.length + 1;
    return '$prefix${seq.toString().padLeft(4, '0')}';
  }

  // ── Status counts ─────────────────────────────────────────────────────────
  int _count(String status) =>
      _pos.where((p) => (p['status'] as String? ?? '') == status).length;

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    super.build(context);

    final filtered = _filter == 'all'
        ? _pos
        : _pos.where((p) => (p['status'] as String? ?? '') == _filter).toList();

    return OfflineSaveListener(
      child: Stack(
        children: [
          Column(
            children: [
              // ── Stat chips ──
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _statChip(
                        'Draft',
                        _count('Draft'),
                        _grey,
                        Icons.edit_note_outlined,
                        'Draft',
                      ),
                      const SizedBox(width: 6),
                      _statChip(
                        'Pending',
                        _count('Pending Approval'),
                        _amber,
                        Icons.hourglass_empty_outlined,
                        'Pending Approval',
                      ),
                      const SizedBox(width: 6),
                      _statChip(
                        'Approved',
                        _count('Approved'),
                        _green,
                        Icons.check_circle_outline,
                        'Approved',
                      ),
                      const SizedBox(width: 6),
                      _statChip(
                        'Ordered',
                        _count('Ordered'),
                        _blue,
                        Icons.local_shipping_outlined,
                        'Ordered',
                      ),
                      const SizedBox(width: 6),
                      _statChip(
                        'Partial',
                        _count('Partially Received'),
                        _amber,
                        Icons.inventory_outlined,
                        'Partially Received',
                      ),
                      const SizedBox(width: 6),
                      _statChip(
                        'Done',
                        _count('Completed'),
                        _green,
                        Icons.task_alt_outlined,
                        'Completed',
                      ),
                      const SizedBox(width: 6),
                      _statChip(
                        'Cancelled',
                        _count('Cancelled'),
                        _red,
                        Icons.cancel_outlined,
                        'Cancelled',
                      ),
                    ],
                  ),
                ),
              ),

              // ── Filter pills ──
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterPill('All', 'all'),
                      const SizedBox(width: 6),
                      _filterPill('Draft', 'Draft'),
                      const SizedBox(width: 6),
                      _filterPill('Pending', 'Pending Approval'),
                      const SizedBox(width: 6),
                      _filterPill('Approved', 'Approved'),
                      const SizedBox(width: 6),
                      _filterPill('Ordered', 'Ordered'),
                      const SizedBox(width: 6),
                      _filterPill('Partial', 'Partially Received'),
                      const SizedBox(width: 6),
                      _filterPill('Completed', 'Completed'),
                      const SizedBox(width: 6),
                      _filterPill('Cancelled', 'Cancelled'),
                    ],
                  ),
                ),
              ),

              // ── Cards ──
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.receipt_long_outlined,
                              size: 48,
                              color: Colors.grey.shade300,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'No purchase orders found.',
                              style: TextStyle(color: Color(0xFF718096)),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                        itemCount: filtered.length,
                        separatorBuilder: (context, s) =>
                            const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final po = filtered[i];
                          return GestureDetector(
                            onTap: () => _showViewModal(po),
                            child: _poCard(po),
                          );
                        },
                      ),
              ),
            ],
          ),

          // ── Speed-dial FAB (simplified — direct to create) ──
          Positioned(
            bottom: 20,
            right: 16,
            child: GestureDetector(
              onTap: _showCreateModal,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: _red,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _red.withOpacity(0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.add, color: Colors.white, size: 28),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // WIDGETS
  // ─────────────────────────────────────────────────────────────────────────

  Widget _statChip(
    String label,
    int count,
    Color color,
    IconData icon,
    String filter,
  ) {
    final active = _filter == filter;
    return GestureDetector(
      onTap: () => setState(() => _filter = active ? 'all' : filter),
      child: Container(
        width: 70,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: active ? color.withOpacity(0.08) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? color : Colors.transparent,
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 14),
            ),
            const SizedBox(height: 4),
            Text(
              '$count',
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterPill(String label, String value) {
    final active = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? _red : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? _red : const Color(0xFFe2e8f0),
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : const Color(0xFF718096),
          ),
        ),
      ),
    );
  }

  Widget _poCard(Map<String, dynamic> po) {
    final status = po['status'] as String? ?? 'Draft';
    final color = _statusColor(status);
    final poNum = po['poNum'] as String? ?? '—';
    final items = (po['items'] as List? ?? []);
    final total = po['totalAmount'] ?? 0;
    final notes = po['notes'] as String? ?? '';

    // Build preview of item names (first 2)
    final itemNames = items
        .take(2)
        .map((i) => (i as Map)['itemName'] as String? ?? '—')
        .join(', ');
    final moreItems = items.length > 2 ? ' +${items.length - 2} more' : '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF0F4F8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top row: PO num + status badge ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  poNum,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1a202c),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status,
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

          // ── Date + items count ──
          Row(
            children: [
              const Icon(
                Icons.calendar_today_outlined,
                size: 12,
                color: Color(0xFFa0aec0),
              ),
              const SizedBox(width: 4),
              Text(
                _fmt(po['createdAt']),
                style: const TextStyle(fontSize: 11, color: Color(0xFF718096)),
              ),
              const SizedBox(width: 12),
              const Icon(
                Icons.inventory_2_outlined,
                size: 12,
                color: Color(0xFFa0aec0),
              ),
              const SizedBox(width: 4),
              Text(
                '${items.length} item${items.length == 1 ? '' : 's'}',
                style: const TextStyle(fontSize: 11, color: Color(0xFF718096)),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // ── Item names preview ──
          if (items.isNotEmpty)
            Text(
              '$itemNames$moreItems',
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF4a5568),
                fontStyle: FontStyle.italic,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),

          if (notes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              notes,
              style: const TextStyle(fontSize: 11, color: Color(0xFF718096)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          const SizedBox(height: 8),

          // ── Bottom row: total + chevron ──
          Row(
            children: [
              Text(
                _fmtPeso(total),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1a202c),
                ),
              ),
              const Spacer(),
              // Quick action buttons per status (shown on card)
              ..._cardActions(po),
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: Color(0xFFa0aec0),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Quick action buttons shown directly on the card
  List<Widget> _cardActions(Map<String, dynamic> po) {
    final status = po['status'] as String? ?? 'Draft';
    switch (status) {
      case 'Draft':
        return [
          _cardBtn(Icons.edit_outlined, _grey, () => _editPO(po)),
          const SizedBox(width: 6),
          _cardBtn(Icons.delete_outline, _red, () => _deletePO(po)),
          const SizedBox(width: 6),
          _cardBtn(
            Icons.send_outlined,
            _blue,
            () => _submitForApproval(po),
            label: 'Submit',
          ),
        ];
      case 'Pending Approval':
        return [
          _cardBtn(
            Icons.check_circle_outline,
            _green,
            () => _approve(po),
            label: 'Approve',
          ),
          const SizedBox(width: 6),
          _cardBtn(Icons.undo_outlined, _amber, () => _revise(po)),
        ];
      case 'Approved':
        return [
          _cardBtn(
            Icons.local_shipping_outlined,
            _blue,
            () => _sendToSupplier(po),
            label: 'Order',
          ),
        ];
      case 'Ordered':
      case 'Partially Received':
        return [
          _cardBtn(
            Icons.download_outlined,
            _green,
            () => _receiveItems(po),
            label: 'Receive',
          ),
        ];
      case 'Completed':
      case 'Cancelled':
        return [];
      default:
        return [];
    }
  }

  Widget _cardBtn(
    IconData icon,
    Color color,
    VoidCallback onTap, {
    String? label,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: label != null ? 8 : 6,
          vertical: 5,
        ),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            if (label != null) ...[
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ],
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
                  color: Colors.black.withOpacity(0.12),
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
                  color: Colors.black.withOpacity(0.15),
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

  // ─────────────────────────────────────────────────────────────────────────
  // VIEW MODAL
  // ─────────────────────────────────────────────────────────────────────────

  void _showViewModal(Map<String, dynamic> po) {
    final status = po['status'] as String? ?? 'Draft';
    final items = (po['items'] as List? ?? []);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (_, ctrl) => Column(
          children: [
            // ── Gradient header ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [const Color(0xFF004B5F), _red],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          po['poNum'] as String? ?? '—',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.25),
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
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
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

            // ── Scrollable body ──
            Expanded(
              child: SingleChildScrollView(
                controller: ctrl,
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Info row ──
                    Row(
                      children: [
                        Expanded(
                          child: _viewInfoCard(
                            'CREATED',
                            _fmt(po['createdAt']),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _viewInfoCard(
                            'TOTAL',
                            _fmtPeso(po['totalAmount']),
                            valueColor: _red,
                          ),
                        ),
                      ],
                    ),
                    if ((po['notes'] as String? ?? '').isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFFFFD54F),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.notes_outlined,
                              size: 14,
                              color: Color(0xFFd69e2e),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                po['notes'] as String,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF92400E),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // ── Items list ──
                    const SizedBox(height: 16),
                    Text(
                      'Items (${items.length})',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1a202c),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...items.asMap().entries.map((e) {
                      final item = e.value as Map;
                      return _viewItemRow(e.key + 1, item);
                    }),

                    // ── Created by ──
                    if ((po['createdBy'] as String? ?? '').isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Icon(
                            Icons.person_outline,
                            size: 14,
                            color: Color(0xFFa0aec0),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Created by: ${po['createdBy']}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF718096),
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 24),

                    // ── Action buttons per status ──
                    ..._viewModalActions(po, ctx),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Action buttons shown in the view modal footer, per status
  List<Widget> _viewModalActions(Map<String, dynamic> po, BuildContext ctx) {
    final status = po['status'] as String? ?? 'Draft';

    Widget btn(
      String label,
      Color bg,
      IconData icon,
      VoidCallback onTap, {
      bool outlined = false,
    }) {
      if (outlined) {
        return OutlinedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 14),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            foregroundColor: bg,
            side: BorderSide(color: bg),
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
          ),
        );
      }
      return ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
      );
    }

    void pop() => Navigator.pop(ctx);

    switch (status) {
      case 'Draft':
        return [
          Row(
            children: [
              Expanded(
                child: btn('Edit', _grey, Icons.edit_outlined, () {
                  pop();
                  _editPO(po);
                }, outlined: true),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: btn('Delete', _red, Icons.delete_outline, () {
                  pop();
                  _deletePO(po);
                }, outlined: true),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: btn('Submit for Approval', _blue, Icons.send_outlined, () {
              pop();
              _submitForApproval(po);
            }),
          ),
        ];

      case 'Pending Approval':
        return [
          Row(
            children: [
              Expanded(
                child: btn('Revise', _amber, Icons.undo_outlined, () {
                  pop();
                  _revise(po);
                }, outlined: true),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: btn('Approve', _green, Icons.check_circle_outline, () {
                  pop();
                  _approve(po);
                }),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: btn('Cancel PO', _red, Icons.cancel_outlined, () {
              pop();
              _cancelPO(po);
            }, outlined: true),
          ),
        ];

      case 'Approved':
        return [
          SizedBox(
            width: double.infinity,
            child: btn(
              'Send to Supplier / Mark as Ordered',
              _blue,
              Icons.local_shipping_outlined,
              () {
                pop();
                _sendToSupplier(po);
              },
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: btn('Cancel PO', _red, Icons.cancel_outlined, () {
              pop();
              _cancelPO(po);
            }, outlined: true),
          ),
        ];

      case 'Ordered':
        return [
          SizedBox(
            width: double.infinity,
            child: btn('Receive Items', _green, Icons.download_outlined, () {
              pop();
              _receiveItems(po);
            }),
          ),
        ];

      case 'Partially Received':
        return [
          SizedBox(
            width: double.infinity,
            child: btn(
              'Continue Receiving',
              _green,
              Icons.download_outlined,
              () {
                pop();
                _continueReceiving(po);
              },
            ),
          ),
        ];

      case 'Completed':
        return [
          SizedBox(
            width: double.infinity,
            child: btn('Archive', _grey, Icons.archive_outlined, () {
              pop();
              _archive(po);
            }, outlined: true),
          ),
        ];

      case 'Cancelled':
        return [];

      default:
        return [];
    }
  }

  Widget _viewInfoCard(String label, String value, {Color? valueColor}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFe2e8f0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: Color(0xFFa0aec0),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: valueColor ?? const Color(0xFF1a202c),
            ),
          ),
        ],
      ),
    );
  }

  Widget _viewItemRow(int num, Map item) {
    final qty = item['expectedQty'] ?? 0;
    final cost =
        double.tryParse(
          (item['unitCost']?.toString() ?? '0')
              .replaceAll('₱', '')
              .replaceAll(',', '')
              .trim(),
        ) ??
        0;
    final subtotal = qty * cost;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFe2e8f0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: _red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  child: Text(
                    '$num',
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: _red,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item['itemName'] as String? ?? '—',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1a202c),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _itemMeta('Qty', '$qty ${item['uom'] ?? ''}'),
              _itemMeta('Unit Cost', _fmtPeso(cost)),
              _itemMeta('Subtotal', _fmtPeso(subtotal), color: _red),
            ],
          ),
          if ((item['supplierCode'] as String? ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Code: ${item['supplierCode']}',
              style: const TextStyle(fontSize: 10, color: Color(0xFFa0aec0)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _itemMeta(String label, String value, {Color? color}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              color: Color(0xFFa0aec0),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color ?? const Color(0xFF4a5568),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CREATE / EDIT MODAL
  // ─────────────────────────────────────────────────────────────────────────

  void _showCreateModal() => _showFormModal(null);
  void _editPO(Map<String, dynamic> po) => _showFormModal(po);

  void _showFormModal(Map<String, dynamic>? existing) {
    final isEdit = existing != null;
    final notesCtrl = TextEditingController(
      text: isEdit ? (existing['notes'] as String? ?? '') : '',
    );

    // Items: each entry = {itemNum, itemName, uom, expectedQty, supplierCode, unitCost}
    final List<Map<String, dynamic>> itemRows = isEdit
        ? List<Map<String, dynamic>>.from(
            (existing['items'] as List? ?? []).map(
              (i) => Map<String, dynamic>.from(i as Map),
            ),
          )
        : [];

    // Low/out-of-stock items from stock_inventory for quick add
    List<Map<String, dynamic>> stockItems = [];
    bool stockLoading = true;

    // Item-level search in quick-add list
    final searchCtrl = TextEditingController();

    Future<void> loadStock(StateSetter setModal) async {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('stock_inventory')
            .get();
        final all = snap.docs.map((d) {
          final data = d.data();
          final stock = (data['stock'] as num?)?.toInt() ?? 0;
          final min = (data['min'] as num?)?.toInt() ?? 0;
          return {...data, 'id': d.id, 'stock': stock, 'min': min};
        }).toList();
        // Show low/out-of-stock first, then rest
        all.sort((a, b) {
          final aLow = (a['stock'] as int) <= (a['min'] as int);
          final bLow = (b['stock'] as int) <= (b['min'] as int);
          if (aLow && !bLow) return -1;
          if (!aLow && bLow) return 1;
          return 0;
        });
        if (mounted == false) return; // unreachable guard
        setModal(() {
          stockItems = all;
          stockLoading = false;
        });
      } catch (_) {
        setModal(() => stockLoading = false);
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setModal) {
          // Load stock items once
          if (stockLoading && stockItems.isEmpty) {
            loadStock(setModal);
          }

          final query = searchCtrl.text.toLowerCase();
          final visibleStock = query.isEmpty
              ? stockItems
              : stockItems.where((s) {
                  final name = (s['name'] as String? ?? '').toLowerCase();
                  final num = (s['num'] as String? ?? '').toLowerCase();
                  return name.contains(query) || num.contains(query);
                }).toList();

          double grandTotal = 0;
          for (final row in itemRows) {
            final qty = (row['expectedQty'] as num?)?.toInt() ?? 0;
            final cost =
                double.tryParse(
                  (row['unitCost']?.toString() ?? '0')
                      .replaceAll('₱', '')
                      .replaceAll(',', '')
                      .trim(),
                ) ??
                0;
            grandTotal += qty * cost;
          }

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.85,
            maxChildSize: 0.97,
            builder: (_, ctrl) => Column(
              children: [
                // ── Header ──
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF004B5F), Color(0xFFEE152A)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
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
                                  ? 'Edit ${existing['poNum'] ?? 'PO'}'
                                  : 'Create Purchase Order',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (itemRows.isNotEmpty)
                              Text(
                                '${itemRows.length} item${itemRows.length == 1 ? '' : 's'}  •  ${_fmtPeso(grandTotal)}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
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

                Expanded(
                  child: SingleChildScrollView(
                    controller: ctrl,
                    padding: EdgeInsets.only(
                      left: 20,
                      right: 20,
                      top: 16,
                      bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Current items in PO ──
                        if (itemRows.isNotEmpty) ...[
                          const Text(
                            'PO Items',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1a202c),
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...itemRows.asMap().entries.map((e) {
                            final i = e.key;
                            final row = e.value;
                            final qty =
                                (row['expectedQty'] as num?)?.toInt() ?? 1;
                            final cost =
                                double.tryParse(
                                  (row['unitCost']?.toString() ?? '0')
                                      .replaceAll('₱', '')
                                      .replaceAll(',', '')
                                      .trim(),
                                ) ??
                                0;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFFe2e8f0),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          row['itemName'] as String? ?? '—',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF1a202c),
                                          ),
                                        ),
                                      ),
                                      GestureDetector(
                                        onTap: () => setModal(
                                          () => itemRows.removeAt(i),
                                        ),
                                        child: const Icon(
                                          Icons.close,
                                          size: 18,
                                          color: Color(0xFFa0aec0),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      // Qty stepper
                                      const Text(
                                        'Qty',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF718096),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      _qtyBtn(Icons.remove, () {
                                        setModal(() {
                                          if (qty > 1) {
                                            itemRows[i]['expectedQty'] =
                                                qty - 1;
                                          }
                                        });
                                      }),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                        ),
                                        child: Text(
                                          '$qty',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      _qtyBtn(Icons.add, () {
                                        setModal(
                                          () => itemRows[i]['expectedQty'] =
                                              qty + 1,
                                        );
                                      }),
                                      const Spacer(),
                                      // Unit cost field
                                      SizedBox(
                                        width: 100,
                                        child: TextFormField(
                                          initialValue: cost == 0
                                              ? ''
                                              : cost.toStringAsFixed(2),
                                          keyboardType: TextInputType.number,
                                          decoration: const InputDecoration(
                                            isDense: true,
                                            prefixText: '₱',
                                            hintText: '0.00',
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 8,
                                                ),
                                            border: OutlineInputBorder(),
                                          ),
                                          onChanged: (v) {
                                            itemRows[i]['unitCost'] =
                                                double.tryParse(
                                                  v.replaceAll('₱', '').trim(),
                                                ) ??
                                                0;
                                            setModal(() {});
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  if ((row['supplierCode'] as String? ?? '')
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Code: ${row['supplierCode']}',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFFa0aec0),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          }),
                          const Divider(height: 24),
                        ],

                        // ── Search quick-add ──
                        const Text(
                          'Add Items from Inventory',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1a202c),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: searchCtrl,
                          decoration: InputDecoration(
                            hintText: 'Search item…',
                            prefixIcon: const Icon(
                              Icons.search,
                              size: 18,
                              color: Color(0xFFa0aec0),
                            ),
                            suffixIcon: searchCtrl.text.isNotEmpty
                                ? GestureDetector(
                                    onTap: () =>
                                        setModal(() => searchCtrl.clear()),
                                    child: const Icon(
                                      Icons.close,
                                      size: 16,
                                      color: Color(0xFFa0aec0),
                                    ),
                                  )
                                : null,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 10,
                              horizontal: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                color: Color(0xFFe2e8f0),
                              ),
                            ),
                            filled: true,
                            fillColor: const Color(0xFFF7F8FA),
                          ),
                          onChanged: (_) => setModal(() {}),
                        ),
                        const SizedBox(height: 8),

                        if (stockLoading)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (visibleStock.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              'No items found.',
                              style: TextStyle(
                                color: Color(0xFF718096),
                                fontSize: 12,
                              ),
                            ),
                          )
                        else
                          ...visibleStock.map((s) {
                            final itemNum = s['num'] as String? ?? '';
                            final name = s['name'] as String? ?? '—';
                            final uom = s['uom'] as String? ?? '';
                            final stock = (s['stock'] as num?)?.toInt() ?? 0;
                            final min = (s['min'] as num?)?.toInt() ?? 0;
                            final isLow = stock <= min;
                            final alreadyAdded = itemRows.any(
                              (r) => r['itemNum'] == itemNum,
                            );

                            return Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isLow
                                    ? const Color(0xFFFFF5F5)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isLow
                                      ? _red.withOpacity(0.3)
                                      : const Color(0xFFe2e8f0),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF1a202c),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            if (uom.isNotEmpty) ...[
                                              Text(
                                                uom,
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  color: Color(0xFF718096),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                            ],
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: isLow
                                                    ? _red.withOpacity(0.1)
                                                    : _green.withOpacity(0.1),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              child: Text(
                                                'Stock: $stock',
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w700,
                                                  color: isLow ? _red : _green,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: alreadyAdded
                                        ? null
                                        : () {
                                            setModal(() {
                                              itemRows.add({
                                                'itemNum': itemNum,
                                                'itemName': name,
                                                'uom': uom,
                                                'expectedQty': 1,
                                                'supplierCode':
                                                    s['supplierCode']
                                                        ?.toString() ??
                                                    '',
                                                'unitCost':
                                                    double.tryParse(
                                                      (s['cost']?.toString() ??
                                                              '0')
                                                          .replaceAll('₱', '')
                                                          .replaceAll(',', '')
                                                          .trim(),
                                                    ) ??
                                                    0,
                                              });
                                            });
                                          },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: alreadyAdded
                                            ? const Color(0xFFe2e8f0)
                                            : _red,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        alreadyAdded ? 'Added' : '+ Add',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: alreadyAdded
                                              ? const Color(0xFF718096)
                                              : Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),

                        const SizedBox(height: 16),

                        // ── Notes ──
                        const Text(
                          'Notes (Optional)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF4a5568),
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: notesCtrl,
                          maxLines: 3,
                          decoration: InputDecoration(
                            hintText: 'Add remarks or special instructions…',
                            isDense: true,
                            contentPadding: const EdgeInsets.all(12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                color: Color(0xFFe2e8f0),
                              ),
                            ),
                            filled: true,
                            fillColor: const Color(0xFFF7F8FA),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // ── Save button ──
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: itemRows.isEmpty
                                ? null
                                : () async {
                                    Navigator.pop(ctx2);
                                    await _savePO(
                                      existing: existing,
                                      items: itemRows,
                                      notes: notesCtrl.text.trim(),
                                    );
                                  },
                            icon: Icon(
                              isEdit
                                  ? Icons.save_outlined
                                  : Icons.add_circle_outline,
                              size: 16,
                            ),
                            label: Text(
                              isEdit ? 'Save Changes' : 'Create PO (Draft)',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _red,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
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

  Widget _qtyBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: _red.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: _red),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SAVE PO (Create / Edit)
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _savePO({
    Map<String, dynamic>? existing,
    required List<Map<String, dynamic>> items,
    required String notes,
  }) async {
    final isEdit = existing != null;
    double total = 0;
    for (final row in items) {
      final qty = (row['expectedQty'] as num?)?.toInt() ?? 0;
      final cost =
          double.tryParse(
            (row['unitCost']?.toString() ?? '0')
                .replaceAll('₱', '')
                .replaceAll(',', '')
                .trim(),
          ) ??
          0;
      total += qty * cost;
    }

    try {
      if (isEdit) {
        await SyncStatusNotifier.instance.trackWrite(
          () => FirebaseFirestore.instance
              .collection(_col)
              .doc(existing['id'] as String)
              .update({
                'items': items,
                'notes': notes,
                'totalAmount': total,
                'updatedAt': FieldValue.serverTimestamp(),
              }),
        );
      } else {
        final poNum = await _genPoNum();
        final uid = FirebaseAuth.instance.currentUser?.uid;
        String createdBy = '';
        if (uid != null) {
          final doc = await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .get();
          createdBy = doc.data()?['name'] as String? ?? '';
        }
        await SyncStatusNotifier.instance.trackWrite(
          () => FirebaseFirestore.instance.collection(_col).add({
            'poNum': poNum,
            'status': 'Draft',
            'items': items,
            'notes': notes,
            'totalAmount': total,
            'createdBy': createdBy,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }),
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEdit ? 'PO updated!' : 'PO created as Draft!'),
            backgroundColor: _green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: _red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STATUS TRANSITION ACTIONS
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _updateStatus(
    Map<String, dynamic> po,
    String newStatus,
    String confirmMsg,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          confirmMsg,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF718096)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await SyncStatusNotifier.instance.trackWrite(
        () => FirebaseFirestore.instance
            .collection(_col)
            .doc(po['id'] as String)
            .update({
              'status': newStatus,
              'updatedAt': FieldValue.serverTimestamp(),
            }),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Status updated to "$newStatus"'),
            backgroundColor: _statusColor(newStatus),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: _red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _submitForApproval(Map<String, dynamic> po) => _updateStatus(
    po,
    'Pending Approval',
    'Submit "${po['poNum']}" for approval?',
  );

  void _approve(Map<String, dynamic> po) =>
      _updateStatus(po, 'Approved', 'Approve "${po['poNum']}"?');

  void _revise(Map<String, dynamic> po) =>
      _updateStatus(po, 'Draft', 'Revise "${po['poNum']}" (back to Draft)?');

  void _sendToSupplier(Map<String, dynamic> po) => _updateStatus(
    po,
    'Ordered',
    'Mark "${po['poNum']}" as Ordered / Sent to Supplier?',
  );

  void _receiveItems(Map<String, dynamic> po) =>
      _showReceiveModal(po, continuing: false);

  void _continueReceiving(Map<String, dynamic> po) =>
      _showReceiveModal(po, continuing: true);

  void _cancelPO(Map<String, dynamic> po) =>
      _updateStatus(po, 'Cancelled', 'Cancel "${po['poNum']}"?');

  Future<void> _archive(Map<String, dynamic> po) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Archive this PO?',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'Archived POs are hidden from the main list but not deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF718096)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _grey,
              foregroundColor: Colors.white,
            ),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await SyncStatusNotifier.instance.trackWrite(
        () => FirebaseFirestore.instance
            .collection(_col)
            .doc(po['id'] as String)
            .update({
              'archived': true,
              'archivedAt': FieldValue.serverTimestamp(),
            }),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PO archived.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: _red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _deletePO(Map<String, dynamic> po) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete this PO?',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'This will permanently delete "${po['poNum']}". This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF718096)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await SyncStatusNotifier.instance.trackWrite(
        () => FirebaseFirestore.instance
            .collection(_col)
            .doc(po['id'] as String)
            .delete(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('PO deleted.'),
            backgroundColor: _red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: _red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // RECEIVE ITEMS MODAL
  // ─────────────────────────────────────────────────────────────────────────

  void _showReceiveModal(Map<String, dynamic> po, {bool continuing = false}) {
    final items = List<Map<String, dynamic>>.from(
      (po['items'] as List? ?? []).map(
        (i) => Map<String, dynamic>.from(i as Map),
      ),
    );

    // Pre-fill actual qty from expectedQty for new receiving
    final qtyCtrlrs = items
        .map(
          (i) => TextEditingController(
            text:
                '${(i['actualQty'] as num?)?.toInt() ?? (i['expectedQty'] as num?)?.toInt() ?? 0}',
          ),
        )
        .toList();
    final notesCtrl = TextEditingController();
    bool submitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setModal) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          maxChildSize: 0.97,
          builder: (_, ctrl) => Column(
            children: [
              // Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF004B5F), Color(0xFFEE152A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            continuing ? 'Continue Receiving' : 'Receive Items',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            po['poNum'] as String? ?? '',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
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

              Expanded(
                child: SingleChildScrollView(
                  controller: ctrl,
                  padding: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    top: 16,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Enter Actual Quantities Received',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1a202c),
                        ),
                      ),
                      const SizedBox(height: 12),

                      ...items.asMap().entries.map((e) {
                        final i = e.key;
                        final item = e.value;
                        final exp = (item['expectedQty'] as num?)?.toInt() ?? 0;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFe2e8f0)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item['itemName'] as String? ?? '—',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF1a202c),
                                      ),
                                    ),
                                    Text(
                                      'Expected: $exp ${item['uom'] ?? ''}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF718096),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 80,
                                child: TextFormField(
                                  controller: qtyCtrlrs[i],
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.center,
                                  decoration: InputDecoration(
                                    isDense: true,
                                    hintText: '$exp',
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                      horizontal: 8,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),

                      const SizedBox(height: 8),
                      TextField(
                        controller: notesCtrl,
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText: 'Receiving notes (optional)…',
                          isDense: true,
                          contentPadding: const EdgeInsets.all(12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF7F8FA),
                        ),
                      ),
                      const SizedBox(height: 20),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: submitting
                              ? null
                              : () async {
                                  setModal(() => submitting = true);
                                  // Build updated items with actualQty
                                  final updatedItems = items
                                      .asMap()
                                      .entries
                                      .map((e) {
                                        final i = e.key;
                                        final item = e.value;
                                        final actual =
                                            int.tryParse(qtyCtrlrs[i].text) ??
                                            (item['expectedQty'] as num?)
                                                ?.toInt() ??
                                            0;
                                        return {...item, 'actualQty': actual};
                                      })
                                      .toList();

                                  // Determine new status
                                  final allFull = updatedItems.every((item) {
                                    final exp =
                                        (item['expectedQty'] as num?)
                                            ?.toInt() ??
                                        0;
                                    final act =
                                        (item['actualQty'] as num?)?.toInt() ??
                                        0;
                                    return act >= exp;
                                  });
                                  final newStatus = allFull
                                      ? 'Completed'
                                      : 'Partially Received';

                                  try {
                                    await SyncStatusNotifier.instance.trackWrite(
                                      () => FirebaseFirestore.instance
                                          .collection(_col)
                                          .doc(po['id'] as String)
                                          .update({
                                            'items': updatedItems,
                                            'status': newStatus,
                                            'receiveNotes': notesCtrl.text
                                                .trim(),
                                            'receivedAt':
                                                FieldValue.serverTimestamp(),
                                            'updatedAt':
                                                FieldValue.serverTimestamp(),
                                          }),
                                    );
                                    if (ctx2.mounted) {
                                      Navigator.pop(ctx2);
                                      ScaffoldMessenger.of(ctx2).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Items received! Status: $newStatus',
                                          ),
                                          backgroundColor: _statusColor(
                                            newStatus,
                                          ),
                                          behavior: SnackBarBehavior.floating,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                        ),
                                      );
                                    }
                                  } catch (err) {
                                    setModal(() => submitting = false);
                                    if (ctx2.mounted) {
                                      ScaffoldMessenger.of(ctx2).showSnackBar(
                                        SnackBar(
                                          content: Text('Error: $err'),
                                          backgroundColor: _red,
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    }
                                  }
                                },
                          icon: submitting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.check_circle_outline,
                                  size: 16,
                                ),
                          label: Text(
                            submitting ? 'Saving…' : 'Confirm Receipt',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
