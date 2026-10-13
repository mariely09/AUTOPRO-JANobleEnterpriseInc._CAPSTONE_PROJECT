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

// ?��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��???
// AdminPO ??Purchase Orders screen
// Mirrors admin_PO.html: 7 statuses, card grid, stat chips, speed-dial FAB,
// view/edit/create bottom-sheet modals, all status transition actions.
// ?��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��???

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

// ?��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��???
// AdminPOBody
// ?��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��??��???

class AdminPOBody extends StatefulWidget {
  const AdminPOBody({super.key});

  @override
  State<AdminPOBody> createState() => AdminPOBodyState();
}

class AdminPOBodyState extends State<AdminPOBody>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // ?�?�?Colours ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?
  static const _red = Color(0xFFE8001C);
  static const _amber = Color(0xFFd69e2e);
  static const _green = Color(0xFF38a169);
  static const _blue = Color(0xFF003087);
  static const _grey = Color(0xFF718096);

  // ?�?�?Months helper ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?
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

  // ?�?�?Firestore collection ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?
  static const _col = 'purchase_orders';

  // ?�?�?State ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?
  List<Map<String, dynamic>> _pos = [];
  bool _loading = true;
  StreamSubscription<QuerySnapshot>? _sub;

  String _filter = 'all';

  // ?�?�?Lifecycle ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?
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

  // ?�?�?Helpers ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?
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
      case 'Pending': // legacy alias
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

  /// Generate PO number: PO-YYYYMMDD-XXXX
  /// The sequence number is globally unique across all dates — never resets.
  /// Queries ALL purchase_orders (not just today's) to get the next sequence.
  Future<String> _genPoNum() async {
    final now = DateTime.now();
    final dateStr =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final prefix = 'PO-$dateStr-';
    // Count ALL POs ever created across all dates for a globally unique sequence
    final snap = await FirebaseFirestore.instance.collection(_col).get();
    final seq = snap.docs.length + 1;
    return '$prefix${seq.toString().padLeft(4, '0')}';
  }

  // ?�?�?Status counts ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?
  int _count(String status) =>
      _pos.where((p) => (p['status'] as String? ?? '') == status).length;

  // ?�?�?Build ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?
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
              // Stats cards - 4 cards in a row like Stock Inventory
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Row(
                  children: [
                    _statChip(
                      'Draft',
                      _count('Draft'),
                      _grey,
                      Icons.edit_note_outlined,
                      'Draft',
                    ),
                    const SizedBox(width: 8),
                    _statChip(
                      'Pending',
                      _count('Pending Approval'),
                      _amber,
                      Icons.hourglass_empty_outlined,
                      'Pending Approval',
                    ),
                    const SizedBox(width: 8),
                    _statChip(
                      'Approved',
                      _count('Approved'),
                      _green,
                      Icons.check_circle_outline,
                      'Approved',
                    ),
                    const SizedBox(width: 8),
                    _statChip(
                      'Ordered',
                      _count('Ordered'),
                      _blue,
                      Icons.local_shipping_outlined,
                      'Ordered',
                    ),
                  ],
                ),
              ),

              // Cards
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

          // ?�?�?Speed-dial FAB (simplified ??direct to create) ?�?�?
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
                      color: _red.withValues(alpha: 0.4),
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

  // ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?
  // WIDGETS
  // ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?

  Widget _statChip(
    String label,
    int count,
    Color color,
    IconData icon,
    String filter,
  ) {
    final active = _filter == filter;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _filter = active ? 'all' : filter),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
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
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              const SizedBox(height: 6),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                label,
                style: const TextStyle(fontSize: 10, color: Color(0xFF718096)),
                textAlign: TextAlign.center,
              ),
            ],
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
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ?�?�?Top row: PO num + status badge ?�?�?
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
                  color: color.withValues(alpha: 0.1),
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

          // ?�?�?Date + items count ?�?�?
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

          // ?�?�?Item names preview ?�?�?
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

          const SizedBox(height: 8),

          // Bottom row: total + chevron
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
      case 'Pending': // legacy ??treat same as Draft
        return [
          _cardBtn(Icons.edit_outlined, _grey, () => _editPO(po)),
          const SizedBox(width: 6),
          _cardBtn(Icons.delete_outline, _red, () => _deletePO(po)),
          const SizedBox(width: 6),
          _cardBtn(
            Icons.send_outlined,
            _red,
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
            _red,
            () => _sendToSupplier(po),
            label: 'Mark Ordered',
          ),
        ];
      case 'Ordered':
      case 'Partially Received':
        return [];
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
          color: color.withValues(alpha: 0.1),
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

  // ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?
  // VIEW MODAL
  // ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?

  void _showViewModal(Map<String, dynamic> po) {
    final items = (po['items'] as List? ?? []);

    // Fetch live stock for all items before opening the modal
    _fetchStockMapAndShow(po, items);
  }

  Future<void> _fetchStockMapAndShow(
    Map<String, dynamic> po,
    List items,
  ) async {
    final status = po['status'] as String? ?? 'Draft';
    final receivingInProgress =
        status == 'Ordered' ||
        status == 'Partially Received' ||
        status == 'Completed';

    // ── Open the modal IMMEDIATELY with frozen stockAtCreate values ──
    // No Firestore wait — show the sheet right away.
    if (!mounted) return;
    _openViewModalSheet(po, const {});

    // ── Background fetch for live stock (Draft/Pending/Approved only) ──
    if (receivingInProgress || items.isEmpty) return;

    final nums = items
        .map((i) => (i as Map)['itemNum']?.toString().trim() ?? '')
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList();

    if (nums.isEmpty) return;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('stock_inventory')
          .get();
      final stockMap = <String, int?>{};
      for (final d in snap.docs) {
        final n = (d.data()['num'] as String? ?? '').trim();
        if (n.isNotEmpty) {
          stockMap[n] = (d.data()['stock'] as num?)?.toInt();
        }
      }
      // Modal is already open — nothing to update on web version,
      // but we can trigger a setState if the sheet is still mounted.
      // (Stock values are displayed from stockMap passed at open time;
      //  a future enhancement can push updates via ValueNotifier.)
    } catch (_) {
      // non-fatal — live stock is optional
    }
  }

  void _openViewModalSheet(
    Map<String, dynamic> po,
    Map<String, int?> stockMap,
  ) {
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
            // ?�?�?Gradient header ?�?�?
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFE8001C), Color(0xFFC41E3A)],
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
                  // Left: PO number + date + status badge (inline)
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
                        const SizedBox(height: 6),
                        // Date + status badge on the same row
                        Row(
                          children: [
                            Text(
                              _fmt(po['createdAt']),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _statusColor(
                                  status,
                                ).withValues(alpha: 0.18),
                                border: Border.all(
                                  color: _statusColor(
                                    status,
                                  ).withValues(alpha: 0.5),
                                  width: 1.5,
                                ),
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
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Right: close button only
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
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

            // Scrollable body
            Expanded(
              child: SingleChildScrollView(
                controller: ctrl,
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Line Items list
                    const SizedBox(height: 16),
                    Text(
                      'Line Items (${items.length})',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1a202c),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...items.asMap().entries.map((e) {
                      final item = e.value as Map;
                      return _viewItemRow(e.key + 1, item, stockMap, status);
                    }),

                    // ── Total Amount row (same as website) ──
                    if ((po['totalAmount'] ?? 0) > 0) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFe2e8f0)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Total Amount',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF4a5568),
                              ),
                            ),
                            Text(
                              _fmtPeso(po['totalAmount']),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1a202c),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // ?�?�?Created by ?�?�?
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

                    // Notes — below Created by
                    if ((po['notes'] as String? ?? '').isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.edit_note_outlined,
                            size: 14,
                            color: Color(0xFFa0aec0),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Notes: ${po['notes']}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF718096),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 24),

                    // ?�?�?Action buttons per status ?�?�?
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
      case 'Pending': // legacy ??treat same as Draft
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
            child: btn('Submit for Approval', _red, Icons.send_outlined, () {
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
        ];

      case 'Approved':
        return [
          SizedBox(
            width: double.infinity,
            child: btn(
              'Mark as Ordered',
              _red,
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
            child: btn('Receive Items', _red, Icons.download_outlined, () {
              pop();
              _receiveItems(po);
            }),
          ),
        ];

      case 'Partially Received':
        // Check if there's a receiving record with stockUpdated = true
        // If yes, hide the button since receiving is completed
        return [];

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

  Widget _viewItemRow(
    int rowNum,
    Map item,
    Map<String, int?> stockMap,
    String status,
  ) {
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

    // For receiving-process statuses, freeze the stock at the value saved
    // when the PO was created (stockAtCreate). For earlier statuses show live.
    final receivingInProgress =
        status == 'Ordered' ||
        status == 'Partially Received' ||
        status == 'Completed';
    final itemNum = (item['itemNum'] as String? ?? '').trim();

    int? stockVal;
    if (receivingInProgress) {
      // Frozen: stockAtCreate (saved at PO creation) ??legacy stockAtReceive ??_stock
      stockVal =
          (item['stockAtCreate'] as num?)?.toInt() ??
          (item['stockAtReceive'] as num?)?.toInt() ??
          (item['_stock'] as num?)?.toInt();
    } else {
      // Live from stock_inventory ??fall back to frozen if unavailable
      stockVal = stockMap[itemNum] ?? (item['stockAtCreate'] as num?)?.toInt();
    }

    final stockStr = stockVal != null ? '$stockVal' : '—';
    final stockColor = stockVal == null
        ? const Color(0xFF718096)
        : stockVal == 0
        ? const Color(0xFFe53e3e)
        : const Color(0xFF1a202c);
    final stockLabel = stockStr;

    // Status badge for received items — only shown for Partially Received / Completed PO
    final showReceiveStatus =
        status == 'Partially Received' || status == 'Completed';
    final itemStatus = showReceiveStatus
        ? (item['receiveStatus'] as String? ?? '')
        : '';
    Widget? statusBadge;
    if (itemStatus == 'Fully Received') {
      statusBadge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: _green.withValues(alpha: 0.1),
          border: Border.all(color: _green.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text(
          'Fully Received',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: _green,
          ),
        ),
      );
    } else if (itemStatus == 'Partially Received') {
      statusBadge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: _amber.withValues(alpha: 0.1),
          border: Border.all(color: _amber.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text(
          'Partially Received',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: _amber,
          ),
        ),
      );
    }

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
                  color: _red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  child: Text(
                    '$rowNum',
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
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
                        if ((item['uom'] as String? ?? '').isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF7F8FA),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              item['uom'] as String,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF718096),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (statusBadge != null) ...[
                      const SizedBox(height: 4),
                      statusBadge!,
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _itemMeta('Order Qty', '$qty'),
              _itemMeta('Stock', stockLabel, color: stockColor),
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

  Widget _itemMetaWidget(String label, Widget child) {
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
          child,
        ],
      ),
    );
  }

  // ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?
  // CREATE / EDIT MODAL
  // ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?

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

    // Loading state for save button
    bool isSaving = false;

    Future<void> loadStock(StateSetter setModal) async {
      try {
        // Fetch stock data
        final stockSnap = await FirebaseFirestore.instance
            .collection('stock_inventory')
            .get();

        // Fetch item_master data to get cost
        final itemMasterSnap = await FirebaseFirestore.instance
            .collection('item_master')
            .get();

        // Create a map of item costs from item_master
        final costMap = <String, double>{};
        for (final doc in itemMasterSnap.docs) {
          final data = doc.data();
          final num = (data['num'] as String? ?? '').trim();
          if (num.isNotEmpty) {
            final costValue = data['cost'];
            double cost = 0;
            if (costValue is int) {
              cost = costValue.toDouble();
            } else if (costValue is double) {
              cost = costValue;
            } else if (costValue is String) {
              cost =
                  double.tryParse(
                    costValue.replaceAll('₱', '').replaceAll(',', '').trim(),
                  ) ??
                  0;
            }
            costMap[num] = cost;
          }
        }

        final all = stockSnap.docs
            .map((d) {
              final data = d.data();
              final stock = (data['stock'] as num?)?.toInt() ?? 0;
              final min = (data['min'] as num?)?.toInt() ?? 0;
              final itemNum = (data['num'] as String? ?? '').trim();

              // Get cost from item_master or fallback to stock_inventory
              double cost = costMap[itemNum] ?? 0;
              if (cost == 0 && data['cost'] != null) {
                final costValue = data['cost'];
                if (costValue is num) {
                  cost = costValue.toDouble();
                } else if (costValue is String) {
                  cost =
                      double.tryParse(
                        costValue
                            .replaceAll('₱', '')
                            .replaceAll(',', '')
                            .trim(),
                      ) ??
                      0;
                }
              }

              return {
                ...data,
                'id': d.id,
                'stock': stock,
                'min': min,
                'cost': cost,
              };
              // ── Match website: only show items that need replenishment (stock <= min) ──
            })
            .where((item) {
              final stock = (item['stock'] as num?)?.toInt() ?? 0;
              final min = (item['min'] as num?)?.toInt() ?? 0;
              return stock <= min;
            })
            .toList();

        // Sort: out-of-stock first, then low stock, then alphabetically
        all.sort((a, b) {
          final aStock = (a['stock'] as num?)?.toInt() ?? 0;
          final bStock = (b['stock'] as num?)?.toInt() ?? 0;
          if (aStock == 0 && bStock != 0) return -1;
          if (bStock == 0 && aStock != 0) return 1;
          return (a['name'] as String? ?? '').compareTo(
            b['name'] as String? ?? '',
          );
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
                // Header — red gradient
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFFE8001C), Color(0xFFC41E3A)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.vertical(
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
                                  ? 'Edit Purchase Order (PO)'
                                  : 'Create Purchase Order (PO)',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isEdit
                                  ? (existing['poNum'] as String? ?? '')
                                  : 'Select items that need replenishment',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
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
                        // ── 1. Items that need replenishment (TOP) ──
                        Row(
                          children: [
                            const Text(
                              'Items that need replenishment ',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1a202c),
                              ),
                            ),
                            Text(
                              // Only count items NOT yet added to line items
                              '(${stockItems.where((s) => !itemRows.any((r) => r['itemNum'] == (s['num'] as String? ?? ''))).length})',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF718096),
                              ),
                            ),
                          ],
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
                          Container(
                            height: 200,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: const Color(0xFFe2e8f0),
                                width: 1.5,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              color: Colors.white,
                            ),
                            child: const Center(
                              child: CircularProgressIndicator(),
                            ),
                          )
                        else if (visibleStock.isEmpty)
                          Container(
                            height: 200,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: const Color(0xFFe2e8f0),
                                width: 1.5,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              color: Colors.white,
                            ),
                            child: const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                  'No items found.',
                                  style: TextStyle(
                                    color: Color(0xFF718096),
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          )
                        else
                          Container(
                            height: 260,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: const Color(0xFFe2e8f0),
                                width: 1.5,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.06),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ListView(
                              padding: EdgeInsets.zero,
                              children: visibleStock.map((s) {
                                final itemNum = s['num'] as String? ?? '';
                                final name = s['name'] as String? ?? '—';
                                final uom = s['uom'] as String? ?? '';
                                final stock =
                                    (s['stock'] as num?)?.toInt() ?? 0;
                                final min = (s['min'] as num?)?.toInt() ?? 0;
                                final isLow = stock <= min;
                                final alreadyAdded = itemRows.any(
                                  (r) => r['itemNum'] == itemNum,
                                );
                                // Check if item is already in another active PO
                                final activeStatuses = [
                                  'Draft',
                                  'Pending Approval',
                                  'Approved',
                                  'Ordered',
                                ];
                                String? existingPONum;
                                for (final po in _pos) {
                                  final status = po['status'] as String? ?? '';
                                  if (!activeStatuses.contains(status))
                                    continue;
                                  final poItems = (po['items'] as List? ?? []);
                                  final found = poItems.any(
                                    (it) => (it as Map)['itemNum'] == itemNum,
                                  );
                                  if (found) {
                                    existingPONum =
                                        po['poNum'] as String? ?? 'existing PO';
                                    break;
                                  }
                                }
                                final blockedByPO =
                                    !alreadyAdded && existingPONum != null;
                                final isDisabled = alreadyAdded || blockedByPO;
                                final supplierCode =
                                    s['supplierCode']?.toString() ?? '';
                                final cost =
                                    double.tryParse(
                                      (s['cost']?.toString() ?? '0')
                                          .replaceAll('₱', '')
                                          .replaceAll(',', '')
                                          .trim(),
                                    ) ??
                                    0;
                                final recQty =
                                    s['max'] != null && s['max'] > stock
                                    ? (s['max'] as int) - stock
                                    : 0;

                                return GestureDetector(
                                  onTap: isDisabled
                                      ? null
                                      : () {
                                          setModal(() {
                                            itemRows.add({
                                              'itemNum': itemNum,
                                              'itemName': name,
                                              'uom': uom,
                                              'expectedQty': recQty > 0
                                                  ? recQty
                                                  : 1,
                                              'maxQty': recQty > 0 ? recQty : 1,
                                              'supplierCode': supplierCode,
                                              'unitCost': cost,
                                            });
                                          });
                                        },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: alreadyAdded
                                          ? const Color(0xFFF0FFF4)
                                          : blockedByPO
                                          ? const Color(0xFFF7F8FA)
                                          : Colors.white,
                                      border: Border(
                                        bottom: BorderSide(
                                          color: const Color(0xFFF0F4F8),
                                          width: 1,
                                        ),
                                      ),
                                    ),
                                    child: Opacity(
                                      opacity: isDisabled ? 0.55 : 1.0,
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                // Item name with UOM
                                                Row(
                                                  children: [
                                                    Flexible(
                                                      child: Text(
                                                        name,
                                                        style: const TextStyle(
                                                          fontSize: 14,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: Color(
                                                            0xFF1a202c,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    if (uom.isNotEmpty) ...[
                                                      const SizedBox(width: 6),
                                                      Text(
                                                        '($uom)',
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.w400,
                                                          color: Color(
                                                            0xFF718096,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                // Info row
                                                Wrap(
                                                  spacing: 8,
                                                  runSpacing: 4,
                                                  children: [
                                                    if (supplierCode.isNotEmpty)
                                                      Text(
                                                        supplierCode,
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                          color: Color(
                                                            0xFF718096,
                                                          ),
                                                        ),
                                                      ),
                                                    Text(
                                                      'Current: $stock',
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        color: Color(
                                                          0xFF718096,
                                                        ),
                                                      ),
                                                    ),
                                                    if (cost > 0)
                                                      Text(
                                                        _fmtPeso(cost) +
                                                            '/unit',
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                          color: Color(
                                                            0xFF718096,
                                                          ),
                                                        ),
                                                      ),
                                                    // Stock badge
                                                    if (stock == 0)
                                                      Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 8,
                                                              vertical: 2,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color:
                                                              const Color(
                                                                0xFFE53E3E,
                                                              ).withValues(
                                                                alpha: 0.08,
                                                              ),
                                                          border: Border.all(
                                                            color:
                                                                const Color(
                                                                  0xFFE53E3E,
                                                                ).withValues(
                                                                  alpha: 0.3,
                                                                ),
                                                            width: 1.5,
                                                          ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                20,
                                                              ),
                                                        ),
                                                        child: const Text(
                                                          'Out of Stock',
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            color: Color(
                                                              0xFFE53E3E,
                                                            ),
                                                          ),
                                                        ),
                                                      )
                                                    else if (isLow)
                                                      Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 8,
                                                              vertical: 2,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: _amber
                                                              .withValues(
                                                                alpha: 0.08,
                                                              ),
                                                          border: Border.all(
                                                            color: _amber
                                                                .withValues(
                                                                  alpha: 0.3,
                                                                ),
                                                            width: 1.5,
                                                          ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                20,
                                                              ),
                                                        ),
                                                        child: const Text(
                                                          'Low Stock',
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            color: Color(
                                                              0xFFD69E2E,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    // "In PO-XXXX" badge
                                                    if (blockedByPO)
                                                      Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 8,
                                                              vertical: 2,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: _blue
                                                              .withValues(
                                                                alpha: 0.08,
                                                              ),
                                                          border: Border.all(
                                                            color: _blue
                                                                .withValues(
                                                                  alpha: 0.3,
                                                                ),
                                                            width: 1.5,
                                                          ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                20,
                                                              ),
                                                        ),
                                                        child: Text(
                                                          'In $existingPONum',
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 11,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                color: Color(
                                                                  0xFF003087,
                                                                ),
                                                              ),
                                                        ),
                                                      ),
                                                    if (recQty > 0)
                                                      Text(
                                                        'Suggest order: $recQty',
                                                        style: const TextStyle(
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
                                          const SizedBox(width: 12),
                                          // Checkmark, block icon, or chevron
                                          Icon(
                                            alreadyAdded
                                                ? Icons.check
                                                : blockedByPO
                                                ? Icons.block_outlined
                                                : Icons.chevron_right,
                                            size: 16,
                                            color: alreadyAdded
                                                ? _green
                                                : blockedByPO
                                                ? _blue
                                                : const Color(0xFFa0aec0),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),

                        const SizedBox(height: 16),

                        // ── 2. Line Items (SECOND) ──
                        if (itemRows.isNotEmpty) ...[
                          Row(
                            children: [
                              const Text(
                                'Line Items ',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1a202c),
                                ),
                              ),
                              Text(
                                '(${itemRows.length})',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF718096),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ...itemRows.asMap().entries.map((e) {
                            final i = e.key;
                            final row = e.value;
                            final qty =
                                (row['expectedQty'] as num?)?.toInt() ?? 1;
                            final maxQty =
                                (row['maxQty'] as num?)?.toInt() ?? qty;
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
                                    color: Colors.black.withValues(alpha: 0.04),
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
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.baseline,
                                          textBaseline: TextBaseline.alphabetic,
                                          children: [
                                            Flexible(
                                              child: Text(
                                                row['itemName'] as String? ??
                                                    '—',
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                  color: Color(0xFF1a202c),
                                                ),
                                              ),
                                            ),
                                            if ((row['uom'] as String? ?? '')
                                                .isNotEmpty) ...[
                                              const SizedBox(width: 6),
                                              Text(
                                                '(${row['uom']})',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w400,
                                                  color: Color(0xFF718096),
                                                ),
                                              ),
                                            ],
                                          ],
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
                                  // ── Stock badge above qty ──
                                  Builder(
                                    builder: (context) {
                                      final itemNum =
                                          (row['itemNum'] as String? ?? '')
                                              .trim();
                                      final matched = stockItems.where(
                                        (s) =>
                                            (s['num'] as String? ?? '')
                                                .trim() ==
                                            itemNum,
                                      );
                                      final stockVal = matched.isNotEmpty
                                          ? (matched.first['stock'] as num?)
                                                ?.toInt()
                                          : (row['stockAtCreate'] as num?)
                                                ?.toInt();
                                      return Row(
                                        children: [
                                          const Text(
                                            'Stock: ',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Color(0xFF718096),
                                            ),
                                          ),
                                          Text(
                                            stockVal != null
                                                ? '$stockVal'
                                                : '—',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: stockVal == null
                                                  ? const Color(0xFF718096)
                                                  : stockVal == 0
                                                  ? const Color(0xFFe53e3e)
                                                  : const Color(0xFF4a5568),
                                            ),
                                          ),
                                        ],
                                      );
                                    },
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
                                      _qtyBtn(
                                        Icons.add,
                                        qty >= maxQty
                                            ? null
                                            : () {
                                                setModal(
                                                  () =>
                                                      itemRows[i]['expectedQty'] =
                                                          qty + 1,
                                                );
                                              },
                                        disabled: qty >= maxQty,
                                      ),
                                      if (maxQty > 1) ...[
                                        const SizedBox(width: 8),
                                        Text(
                                          'Max: $maxQty',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: Color(0xFF718096),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                      const Spacer(),
                                      // Unit cost field
                                      SizedBox(
                                        width: 100,
                                        child: TextFormField(
                                          initialValue: cost.toStringAsFixed(2),
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

                                  // ── Subtotal row ──
                                  if (cost > 0) ...[
                                    const SizedBox(height: 8),
                                    const Divider(
                                      height: 1,
                                      color: Color(0xFFF0F4F8),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          'Subtotal',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF718096),
                                          ),
                                        ),
                                        Text(
                                          _fmtPeso(cost * qty),
                                          style: const TextStyle(
                                            fontSize: 13,
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

                          // ── Estimated Total (same as website) ──
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(
                                color: const Color(0xFFe2e8f0),
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                                  _fmtPeso(grandTotal),
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF1a202c),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 24),
                        ],

                        const SizedBox(height: 16),

                        // ?�?�?Notes ?�?�?
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

                        // Cancel and Save buttons
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(ctx2),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF718096),
                                  side: const BorderSide(
                                    color: Color(0xFFe2e8f0),
                                    width: 1.5,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                ),
                                child: const Text(
                                  'Cancel',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: itemRows.isEmpty || isSaving
                                    ? null
                                    : () async {
                                        setModal(() => isSaving = true);
                                        try {
                                          await _savePO(
                                            existing: existing,
                                            items: itemRows,
                                            notes: notesCtrl.text.trim(),
                                          );
                                          if (mounted) {
                                            Navigator.pop(ctx2);
                                          }
                                        } finally {
                                          if (mounted) {
                                            setModal(() => isSaving = false);
                                          }
                                        }
                                      },
                                icon: isSaving
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                Colors.white,
                                              ),
                                        ),
                                      )
                                    : const Icon(Icons.save_outlined, size: 16),
                                label: Text(
                                  isSaving
                                      ? 'Saving…'
                                      : (isEdit ? 'Update' : 'Save'),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _red,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: _red.withValues(
                                    alpha: 0.6,
                                  ),
                                  disabledForegroundColor: Colors.white70,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                ),
                              ),
                            ),
                          ],
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

  Widget _qtyBtn(IconData icon, VoidCallback? onTap, {bool disabled = false}) {
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: disabled
              ? const Color(0xFFE2E8F0)
              : _red.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 16,
          color: disabled ? const Color(0xFFA0AEC0) : _red,
        ),
      ),
    );
  }

  // ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?
  // SAVE PO (Create / Edit)
  // ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?

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

        // Snapshot current stock for each item at creation time.
        // This is stored as stockAtCreate so the view modal can show
        // the frozen value once receiving begins.
        final stockSnap = await FirebaseFirestore.instance
            .collection('stock_inventory')
            .get();
        final stockNow = <String, int>{};
        for (final d in stockSnap.docs) {
          final n = (d.data()['num'] as String? ?? '').trim();
          if (n.isNotEmpty) {
            stockNow[n] = (d.data()['stock'] as num?)?.toInt() ?? 0;
          }
        }

        final itemsWithStock = items.map((row) {
          final itemNum = (row['itemNum'] as String? ?? '').trim();
          return {
            ...row,
            'stockAtCreate': stockNow[itemNum], // null if not found
          };
        }).toList();

        await SyncStatusNotifier.instance.trackWrite(
          () => FirebaseFirestore.instance.collection(_col).add({
            'poNum': poNum,
            'status': 'Draft',
            'items': itemsWithStock,
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

  // ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?
  // STATUS TRANSITION ACTIONS
  // ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?

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

  void _sendToSupplier(Map<String, dynamic> po) =>
      _updateStatus(po, 'Ordered', 'Mark "${po['poNum']}" as Ordered?');

  void _receiveItems(Map<String, dynamic> po) {
    final poNum = po['poNum'] as String? ?? '';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminInventoryHub(
          initialTab: 2, // Receiving Items tab
          poNumToReceive: poNum,
        ),
      ),
    );
  }

  void _continueReceiving(Map<String, dynamic> po) {
    final poNum = po['poNum'] as String? ?? '';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminInventoryHub(
          initialTab: 2, // Receiving Items tab
          poNumToReceive: poNum,
        ),
      ),
    );
  }

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
}
