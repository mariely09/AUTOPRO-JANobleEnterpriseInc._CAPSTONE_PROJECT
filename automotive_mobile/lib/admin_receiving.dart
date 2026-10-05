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
// AdminReceiving — Receiving Items screen
//
// Mirrors admin_receiving.html:
//  • Collection: 'receivings'  (NOT the old 'deliveries')
//  • Header statuses:  DRAFT · INPROG · PARTIAL · COMP
//  • Line statuses:    DRAFT · COMP · INCOMP · MISSING · DEFECTIVE
//  • Receiving number: RCV-YYYYMMDD-0001 (sequential per day)
//  • FAB actions:  "New Receiving from PO"  |  "New Blank Receiving"
//  • Copy-from-PO maps purchase_orders.items[] → receivingLines[]
//  • Completing a line (COMP/INCOMP) updates stock_inventory + transactions
// ═══════════════════════════════════════════════════════════════════════════

class AdminReceiving extends StatelessWidget {
  const AdminReceiving({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: const AdminReceivingBody(),
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
                builder: (_) => const AdminInventoryHub(initialTab: 2),
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

// ─────────────────────────────────────────────────────────────────────────
// AdminReceivingBody
// ─────────────────────────────────────────────────────────────────────────

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

  // ── Colours ──────────────────────────────────────────────────────────────
  static const _red = Color(0xFFE8001C);
  static const _amber = Color(0xFFd69e2e);
  static const _green = Color(0xFF38a169);
  static const _blue = Color(0xFF003087);
  static const _grey = Color(0xFF718096);

  // ── Collections ──────────────────────────────────────────────────────────
  static const _col = 'receivings';
  static const _poCol = 'purchase_orders';

  // ── Months ───────────────────────────────────────────────────────────────
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

  // ── Status config (mirrors web _STATUS_CFG) ───────────────────────────────
  // header statuses (order: DRAFT → INPROG → PARTIAL → COMP)
  static const _hdrLabels = {
    'DRAFT': 'Draft',
    'INPROG': 'In Progress',
    'PARTIAL': 'Partial',
    'COMP': 'Complete',
  };
  Color _hdrColor(String s) {
    switch (s) {
      case 'DRAFT':
        return _grey;
      case 'INPROG':
        return _blue;
      case 'PARTIAL':
        return _amber;
      case 'COMP':
        return _green;
      default:
        return _grey;
    }
  }

  // line statuses
  static const _lineLabels = {
    'DRAFT': 'Draft',
    'COMP': 'Complete',
    'INCOMP': 'Incomplete',
    'MISSING': 'Missing',
    'DEFECTIVE': 'Defective',
  };
  Color _lineColor(String s) {
    switch (s) {
      case 'COMP':
        return _green;
      case 'INCOMP':
        return _amber;
      case 'MISSING':
        return _red;
      case 'DEFECTIVE':
        return _red;
      default:
        return _grey;
    }
  }

  // ── State ────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _rcvs = [];
  bool _loading = true;
  StreamSubscription<QuerySnapshot>? _sub;
  String _filter = 'all';
  bool _fabOpen = false;

  // ── Lifecycle ─────────────────────────────────────────────────────────────
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
              _rcvs = snap.docs
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

  String _fmtPeso(double v) {
    final parts = v.toStringAsFixed(2).split('.');
    final int1 = parts[0].replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return '₱$int1.${parts[1]}';
  }

  /// Generate receiving number: RCV-YYYYMMDD-0001
  Future<String> _genRcvNum() async {
    final now = DateTime.now();
    final ds =
        '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    final prefix = 'RCV-$ds-';
    final snap = await FirebaseFirestore.instance
        .collection(_col)
        .where('receivingNum', isGreaterThanOrEqualTo: prefix)
        .where('receivingNum', isLessThan: '${prefix}z')
        .get();
    return '$prefix${(snap.docs.length + 1).toString().padLeft(4, '0')}';
  }

  /// Count header records by status
  int _count(String status) =>
      _rcvs.where((r) => (r['status'] as String? ?? '') == status).length;

  /// Auto-suggest line status from received qty vs PO qty (mirrors rmAutoLineStatus)
  String _autoLineStatus(int receivedQty, int poQty) {
    if (receivedQty == 0) return 'MISSING';
    if (receivedQty < poQty) return 'INCOMP';
    return 'COMP';
  }

  /// Recompute header status from all lines (mirrors web logic)
  String _computeHeaderStatus(List<Map<String, dynamic>> lines) {
    if (lines.isEmpty) return 'INPROG';
    final allDone = lines.every(
      (l) => (l['lineStatus'] as String? ?? 'DRAFT') != 'DRAFT',
    );
    if (!allDone) return 'INPROG';
    final allComp = lines.every(
      (l) => (l['lineStatus'] as String? ?? 'DRAFT') == 'COMP',
    );
    return allComp ? 'COMP' : 'PARTIAL';
  }

  // ── Logged-in user name ───────────────────────────────────────────────────
  Future<String> _currentUserName() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return '';
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      return doc.data()?['name'] as String? ?? '';
    } catch (_) {
      return '';
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    super.build(context);

    final q = widget.searchQuery.toLowerCase();
    final searched = q.isEmpty
        ? _rcvs
        : _rcvs.where((r) {
            final rn = (r['receivingNum'] as String? ?? '').toLowerCase();
            final pn = (r['poNum'] as String? ?? '').toLowerCase();
            final lines = (r['receivingLines'] as List? ?? []);
            final lineMatch = lines.any(
              (l) =>
                  (l['itemName'] as String? ?? '').toLowerCase().contains(q) ||
                  (l['itemNum'] as String? ?? '').toLowerCase().contains(q) ||
                  (l['supplierCode'] as String? ?? '').toLowerCase().contains(
                    q,
                  ),
            );
            return rn.contains(q) || pn.contains(q) || lineMatch;
          }).toList();

    final filtered = _filter == 'all'
        ? searched
        : searched
              .where((r) => (r['status'] as String? ?? '') == _filter)
              .toList();

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
                        _count('DRAFT'),
                        _grey,
                        Icons.edit_note_outlined,
                        'DRAFT',
                      ),
                      const SizedBox(width: 6),
                      _statChip(
                        'In Prog',
                        _count('INPROG'),
                        _blue,
                        Icons.download_outlined,
                        'INPROG',
                      ),
                      const SizedBox(width: 6),
                      _statChip(
                        'Partial',
                        _count('PARTIAL'),
                        _amber,
                        Icons.timelapse_outlined,
                        'PARTIAL',
                      ),
                      const SizedBox(width: 6),
                      _statChip(
                        'Done',
                        _count('COMP'),
                        _green,
                        Icons.task_alt_outlined,
                        'COMP',
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
                      _pill('All', 'all'),
                      const SizedBox(width: 6),
                      _pill('Draft', 'DRAFT'),
                      const SizedBox(width: 6),
                      _pill('In Progress', 'INPROG'),
                      const SizedBox(width: 6),
                      _pill('Partial', 'PARTIAL'),
                      const SizedBox(width: 6),
                      _pill('Complete', 'COMP'),
                    ],
                  ),
                ),
              ),

              // ── List ──
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.inbox_outlined,
                              size: 48,
                              color: Colors.grey.shade300,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'No receiving records found.',
                              style: TextStyle(color: Color(0xFF718096)),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                        itemCount: filtered.length,
                        separatorBuilder: (context, i) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final r = filtered[i];
                          return GestureDetector(
                            onTap: () => _showViewModal(r),
                            child: _rcvCard(r),
                          );
                        },
                      ),
              ),
            ],
          ),

          // ── FAB backdrop ──
          if (_fabOpen)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _fabOpen = false),
                child: Container(color: Colors.black.withValues(alpha: 0.15)),
              ),
            ),

          // ── Speed-dial FAB ──
          Positioned(
            bottom: 20,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (_fabOpen) ...[
                  _fabAction(
                    label: 'New Receiving from PO',
                    icon: Icons.content_paste_outlined,
                    onTap: () {
                      setState(() => _fabOpen = false);
                      _showCopyFromPOModal();
                    },
                  ),
                  const SizedBox(height: 10),
                  _fabAction(
                    label: 'New Blank Receiving',
                    icon: Icons.note_add_outlined,
                    onTap: () {
                      setState(() => _fabOpen = false);
                      _createBlankReceiving();
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
        width: 72,
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

  Widget _pill(String label, String value) {
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

  Widget _rcvCard(Map<String, dynamic> r) {
    final status = r['status'] as String? ?? 'DRAFT';
    final color = _hdrColor(status);
    final label = _hdrLabels[status] ?? status;
    final lines = (r['receivingLines'] as List? ?? []);
    final rcvNum = r['receivingNum'] as String? ?? r['id'] as String;
    final poNum = r['poNum'] as String? ?? '';

    // Count done vs total lines
    final doneCount = lines
        .where((l) => (l['lineStatus'] as String? ?? 'DRAFT') != 'DRAFT')
        .length;

    // Preview: first 2 item names
    final preview = lines
        .take(2)
        .map((l) => (l as Map)['itemName'] as String? ?? '—')
        .join(', ');
    final more = lines.length > 2 ? ' +${lines.length - 2} more' : '';

    // Total value
    double total = 0;
    for (final l in lines) {
      final cost =
          double.tryParse(
            (l['unitCost']?.toString() ?? '0')
                .replaceAll('₱', '')
                .replaceAll(',', '')
                .trim(),
          ) ??
          0;
      final qty = (l['receivedQty'] as num?)?.toInt() ?? 0;
      total += cost * qty;
    }

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
          // ── Header row ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rcvNum,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1a202c),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 11,
                          color: Color(0xFFa0aec0),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _fmt(r['createdAt']),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF718096),
                          ),
                        ),
                        if (poNum.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.receipt_long_outlined,
                            size: 11,
                            color: Color(0xFFa0aec0),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            poNum,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF718096),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),

          const Divider(height: 16, color: Color(0xFFF0F4F8)),

          // ── Meta row ──
          Row(
            children: [
              Expanded(
                child: Text(
                  '${lines.length} item${lines.length == 1 ? '' : 's'}'
                  ' — $doneCount/${lines.length} received',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF718096),
                  ),
                ),
              ),
              // Action button per status
              if (status == 'DRAFT')
                _cardActionBtn('▶ Start', _blue, () => _startReceiving(r))
              else if (status == 'INPROG')
                _cardActionBtn('▶ Continue', _red, () => _showViewModal(r))
              else if (total > 0)
                Text(
                  _fmtPeso(total),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1a202c),
                  ),
                ),
            ],
          ),

          // ── Preview ──
          if (lines.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '$preview$more',
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF4a5568),
                fontStyle: FontStyle.italic,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _cardActionBtn(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: color,
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

  // ─────────────────────────────────────────────────────────────────────────
  // FAB ACTIONS
  // ─────────────────────────────────────────────────────────────────────────

  /// Create a blank receiving record — STATUS=DRAFT
  /// User adds items first, then taps "Start Receiving" to move to INPROG.
  Future<void> _createBlankReceiving() async {
    final rcvNum = await _genRcvNum();
    final name = await _currentUserName();
    try {
      final ref = await SyncStatusNotifier.instance.trackWrite(
        () => FirebaseFirestore.instance.collection(_col).add({
          'receivingNum': rcvNum,
          'status': 'DRAFT',
          'poRef': null,
          'poNum': '',
          'receivingLines': [],
          'createdBy': name,
          'createdAt': FieldValue.serverTimestamp(),
        }),
      );
      if (!mounted) return;
      final doc = await ref.get();
      if (!mounted) return;
      _showViewModal({...doc.data() as Map<String, dynamic>, 'id': doc.id});
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
  // COPY FROM PO MODAL
  // ─────────────────────────────────────────────────────────────────────────

  void _showCopyFromPOModal() async {
    // Fetch POs with status 'Ordered' or 'Pending' (one-shot, not a listener)
    List<Map<String, dynamic>> pos = [];
    bool loadingPOs = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setModal) {
          if (loadingPOs) {
            FirebaseFirestore.instance
                .collection(_poCol)
                .where('status', whereIn: ['Ordered', 'Pending'])
                .orderBy('createdAt', descending: true)
                .get()
                .then((snap) {
                  if (ctx2.mounted) {
                    setModal(() {
                      pos = snap.docs
                          .map((d) => {...d.data(), 'id': d.id})
                          .toList();
                      loadingPOs = false;
                    });
                  }
                })
                .catchError((_) {
                  if (ctx2.mounted) setModal(() => loadingPOs = false);
                });
          }

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.55,
            maxChildSize: 0.88,
            builder: (_, ctrl) => Column(
              children: [
                // Header — blue gradient (matches web)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF003087), Color(0xFF0050c8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'New Receiving from PO',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Select an ordered PO to create a receiving record',
                              style: TextStyle(
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
                  child: loadingPOs
                      ? const Center(child: CircularProgressIndicator())
                      : pos.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'No ordered POs found.\nPOs must be in "Ordered" status.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFF718096),
                                fontSize: 13,
                              ),
                            ),
                          ),
                        )
                      : ListView.separated(
                          controller: ctrl,
                          padding: const EdgeInsets.all(16),
                          itemCount: pos.length,
                          separatorBuilder: (context, i) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final po = pos[i];
                            final items = (po['items'] as List? ?? []);
                            return GestureDetector(
                              onTap: () {
                                Navigator.pop(ctx2);
                                _createReceivingFromPO(po);
                              },
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFFe2e8f0),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.04,
                                      ),
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
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            po['poNum'] as String? ??
                                                po['id'] as String,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13,
                                              color: Color(0xFF1a202c),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${_fmt(po['createdAt'])}  •  '
                                            '${items.length} item${items.length == 1 ? '' : 's'}'
                                            '${(po['totalAmount'] as num? ?? 0) > 0 ? '  •  ${_fmtPeso((po['totalAmount'] as num).toDouble())}' : ''}',
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
          );
        },
      ),
    );
  }

  /// Create a receiving record from a PO document (mirrors web createReceivingFromPO)
  Future<void> _createReceivingFromPO(Map<String, dynamic> po) async {
    final rcvNum = await _genRcvNum();
    final name = await _currentUserName();

    // Map PO items → receiving lines
    final poItems = (po['items'] as List? ?? []);
    final lines = poItems.map((item) {
      final m = item as Map;
      return {
        'itemNum': m['itemNum'] ?? '',
        'itemName': m['itemName'] ?? '',
        'uom': m['uom'] ?? '',
        'supplierCode': m['supplierCode'] ?? '',
        'unitCost':
            double.tryParse(
              (m['unitCost']?.toString() ?? '0')
                  .replaceAll('₱', '')
                  .replaceAll(',', '')
                  .trim(),
            ) ??
            0.0,
        'poQty': (m['expectedQty'] as num?)?.toInt() ?? 0, // source field in PO
        'receivedQty': 0,
        'lineStatus': 'DRAFT',
        'remark': '',
        'receivedAt': null,
        'receivedBy': '',
      };
    }).toList();

    try {
      final ref = await SyncStatusNotifier.instance.trackWrite(
        () => FirebaseFirestore.instance.collection(_col).add({
          'receivingNum': rcvNum,
          'status': 'DRAFT',
          'poRef': po['id'] as String,
          'poNum': po['poNum'] ?? '',
          'receivingLines': lines,
          'createdBy': name,
          'createdAt': FieldValue.serverTimestamp(),
        }),
      );

      // Set PO status to 'Partially Received' (mirrors web)
      try {
        await SyncStatusNotifier.instance.trackWrite(
          () => FirebaseFirestore.instance
              .collection(_poCol)
              .doc(po['id'] as String)
              .update({
                'status': 'Partially Received',
                'updatedAt': FieldValue.serverTimestamp(),
              }),
        );
      } catch (_) {} // non-fatal if PO update fails

      if (!mounted) return;
      final doc = await ref.get();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$rcvNum created from ${po['poNum'] ?? 'PO'}'),
          backgroundColor: _green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );

      _showViewModal({...doc.data() as Map<String, dynamic>, 'id': doc.id});
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
  // START RECEIVING  (DRAFT → INPROG)
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _startReceiving(Map<String, dynamic> r) async {
    try {
      await SyncStatusNotifier.instance.trackWrite(
        () => FirebaseFirestore.instance
            .collection(_col)
            .doc(r['id'] as String)
            .update({
              'status': 'INPROG',
              'startedAt': FieldValue.serverTimestamp(),
            }),
      );
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
  // VIEW MODAL  (card view + line list + actions)
  // ─────────────────────────────────────────────────────────────────────────

  void _showViewModal(Map<String, dynamic> r) {
    final docId = r['id'] as String;
    final rcvNum = r['receivingNum'] as String? ?? r['id'] as String;
    final poNum = r['poNum'] as String? ?? '';
    final createdAt = r['createdAt'];

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
        builder: (_, ctrl) => StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection(_col)
              .doc(docId)
              .snapshots(),
          builder: (ctx2, snap) {
            final data = snap.hasData && snap.data!.exists
                ? {...(snap.data!.data() as Map<String, dynamic>), 'id': docId}
                : r;

            final status = data['status'] as String? ?? 'DRAFT';
            final color = _hdrColor(status);
            final label = _hdrLabels[status] ?? status;
            final lines = List<Map<String, dynamic>>.from(
              (data['receivingLines'] as List? ?? []).map(
                (l) => Map<String, dynamic>.from(l as Map),
              ),
            );
            double total = 0;
            for (final l in lines) {
              final c = double.tryParse(
                    (l['unitCost']?.toString() ?? '0')
                        .replaceAll('₱', '')
                        .replaceAll(',', '')
                        .trim(),
                  ) ??
                  0;
              total += c * ((l['receivedQty'] as num?)?.toInt() ?? 0);
            }

            return Column(
              children: [
                // ── Gradient header ──
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [color.withValues(alpha: 1.0), color],
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
                              rcvNum,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white24,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    label,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (poNum.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Text(
                                    'PO: $poNum',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: Container(
                          width: 32, height: 32,
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
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Summary row ──
                        Row(
                          children: [
                            Expanded(
                              child: _infoCard('CREATED', _fmt(createdAt)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _infoCard(
                                'LINES',
                                '${lines.where((l) => (l['lineStatus'] as String? ?? 'DRAFT') != 'DRAFT').length}/${lines.length} done',
                              ),
                            ),
                            if (total > 0) ...[
                              const SizedBox(width: 10),
                              Expanded(
                                child: _infoCard(
                                  'TOTAL',
                                  _fmtPeso(total),
                                  valueColor: _red,
                                ),
                              ),
                            ],
                          ],
                        ),

                        // ── Lines list ──
                        const SizedBox(height: 16),
                        Text(
                          'Receiving Lines (${lines.length})',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1a202c),
                          ),
                        ),
                        const SizedBox(height: 8),

                        if (lines.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF7F8FA),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFe2e8f0)),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.inbox_outlined,
                                  size: 18,
                                  color: Color(0xFFa0aec0),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'No items — add lines to receive.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF718096),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          ...lines.asMap().entries.map((e) {
                            final i = e.key;
                            final line = e.value;
                            final lst = line['lineStatus'] as String? ?? 'DRAFT';
                            final lc = _lineColor(lst);
                            final ll = _lineLabels[lst] ?? lst;
                            final pQty = (line['poQty'] as num?)?.toInt() ?? 0;
                            final rQty = (line['receivedQty'] as num?)?.toInt() ?? 0;
                            final canReceive =
                                (status == 'INPROG' || status == 'DRAFT') &&
                                lst == 'DRAFT';

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFe2e8f0)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.03),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 20, height: 20,
                                        decoration: BoxDecoration(
                                          color: _red.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Center(
                                          child: Text(
                                            '${i + 1}',
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
                                        child: RichText(
                                          text: TextSpan(
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF1a202c),
                                            ),
                                            children: [
                                              TextSpan(
                                                text: line['itemName'] as String? ?? '—',
                                              ),
                                              if ((line['uom'] as String? ?? '').isNotEmpty)
                                                TextSpan(
                                                  text: '  (${line['uom']})',
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
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: lc.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          ll,
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                            color: lc,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      _lineMeta('Order Qty', '$pQty'),
                                      _lineMeta(
                                        'Rcv Qty',
                                        lst == 'DRAFT' ? '—' : '$rQty',
                                        color: lst != 'DRAFT'
                                            ? (rQty >= pQty ? _green : _amber)
                                            : null,
                                      ),
                                      _lineMeta('Item #', line['itemNum'] as String? ?? '—'),
                                      _lineMeta('OEM #', line['oem'] as String? ?? '—'),
                                    ],
                                  ),
                                  if ((line['remark'] as String? ?? '').isNotEmpty) ...[
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
                                        line['remark'] as String,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Color(0xFF92400E),
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (canReceive) ...[
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: () {
                                              Navigator.pop(ctx);
                                              _showReceiveLineModal(data, i);
                                            },
                                            icon: const Icon(
                                              Icons.download_outlined,
                                              size: 14,
                                            ),
                                            label: const Text(
                                              'Receive Item',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: _red,
                                              side: BorderSide(
                                                color: _red.withValues(alpha: 0.4),
                                              ),
                                              padding: const EdgeInsets.symmetric(
                                                vertical: 10,
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(20),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        OutlinedButton(
                                          onPressed: () async {
                                            final updated = List<Map<String, dynamic>>.from(lines);
                                            updated.removeAt(i);
                                            try {
                                              await SyncStatusNotifier.instance.trackWrite(
                                                () => FirebaseFirestore.instance
                                                    .collection(_col)
                                                    .doc(docId)
                                                    .update({'receivingLines': updated}),
                                              );
                                            } catch (e) {
                                              if (ctx.mounted) {
                                                ScaffoldMessenger.of(ctx).showSnackBar(
                                                  SnackBar(
                                                    content: Text('Error: $e'),
                                                    backgroundColor: _red,
                                                  ),
                                                );
                                              }
                                            }
                                          },
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: _red,
                                            side: BorderSide(
                                              color: _red.withValues(alpha: 0.4),
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 10,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.delete_outline,
                                            size: 16,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            );
                          }),

                        const SizedBox(height: 20),

                        // ── Footer actions ──
                        if (status == 'DRAFT') ...[
                          if (poNum.isEmpty) ...[
                            // Blank receiving: Start & Add Items + Delete in one row
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () async {
                                      Navigator.pop(ctx);
                                      await _startReceiving(data);
                                      if (mounted) _showAddItemModal(data);
                                    },
                                    icon: const Icon(Icons.add_circle_outline, size: 15),
                                    label: const Text(
                                      'Start & Add Items',
                                      style: TextStyle(fontWeight: FontWeight.w700),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _red,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 13),
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(30)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                OutlinedButton(
                                  onPressed: () async {
                                    final ok = await showDialog<bool>(
                                      context: ctx,
                                      builder: (dctx) => AlertDialog(
                                        shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(16)),
                                        title: const Text(
                                          'Delete this record?',
                                          style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700),
                                        ),
                                        content: const Text(
                                            'This will permanently delete the receiving record.'),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(dctx, false),
                                            child: const Text('Cancel',
                                                style: TextStyle(
                                                    color: Color(0xFF718096))),
                                          ),
                                          ElevatedButton(
                                            onPressed: () => Navigator.pop(dctx, true),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: _red,
                                              foregroundColor: Colors.white,
                                            ),
                                            child: const Text('Delete'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (ok != true || !ctx.mounted) return;
                                    Navigator.pop(ctx);
                                    try {
                                      await SyncStatusNotifier.instance.trackWrite(
                                        () => FirebaseFirestore.instance
                                            .collection(_col)
                                            .doc(docId)
                                            .delete(),
                                      );
                                    } catch (e) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('Error: $e'),
                                            backgroundColor: _red,
                                          ),
                                        );
                                      }
                                    }
                                  },
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: _red,
                                    side: BorderSide(
                                        color: _red.withValues(alpha: 0.4)),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 13),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                  ),
                                  child: const Icon(Icons.delete_outline, size: 16),
                                ),
                              ],
                            ),
                          ],
                          if (poNum.isNotEmpty) ...[
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _startReceiving(data);
                                },
                                icon: const Icon(Icons.play_arrow_outlined, size: 16),
                                label: const Text(
                                  'Start Receiving',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _blue,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                        ] else if (status == 'INPROG') ...[
                          if (poNum.isEmpty) ...[
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () => _showAddItemModal(data),
                                icon: const Icon(Icons.add_circle_outline, size: 16),
                                label: const Text('Add Item',
                                    style: TextStyle(fontWeight: FontWeight.w700)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _red,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(30)),
                                ),
                              ),
                            ),
                          ],
                        ] else if (status == 'COMP' || status == 'PARTIAL') ...[
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _archiveReceiving(data);
                              },
                              icon: const Icon(
                                Icons.archive_outlined,
                                size: 14,
                                color: Color(0xFF718096),
                              ),
                              label: const Text(
                                'Archive',
                                style: TextStyle(
                                  color: Color(0xFF718096),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFFcbd5e0)),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _infoCard(String label, String value, {Color? valueColor}) =>
      Container(
        padding: const EdgeInsets.all(11),
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
            const SizedBox(height: 3),
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: valueColor ?? const Color(0xFF1a202c),
              ),
            ),
          ],
        ),
      );

  Widget _lineMeta(String label, String value, {Color? color}) => Expanded(
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

  // ─────────────────────────────────────────────────────────────────────────
  // ADD ITEM MODAL  (blank receivings only)
  // ─────────────────────────────────────────────────────────────────────────

  void _showAddItemModal(Map<String, dynamic> r) async {
    final docId = r['id'] as String;
    List<Map<String, dynamic>> allItems = [];
    List<Map<String, dynamic>> filtered = [];
    bool loadingItems = true;
    final searchCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setModal) {
          // Load items once
          if (loadingItems) {
            FirebaseFirestore.instance
                .collection('item_master')
                .get()
                .then((snap) {
                  if (ctx2.mounted) {
                    final items = snap.docs
                        .map((d) => {...d.data(), 'id': d.id})
                        .toList();
                    setModal(() {
                      allItems = items;
                      filtered = items;
                      loadingItems = false;
                    });
                  }
                })
                .catchError((_) {
                  if (ctx2.mounted) setModal(() => loadingItems = false);
                });
          }

          void onSearch(String q) {
            final lq = q.toLowerCase();
            setModal(() {
              filtered = lq.isEmpty
                  ? allItems
                  : allItems.where((i) {
                      final name = (i['name'] as String? ?? '').toLowerCase();
                      final num = (i['num'] as String? ?? '').toLowerCase();
                      final sc = (i['supplierCode'] as String? ?? '').toLowerCase();
                      return name.contains(lq) || num.contains(lq) || sc.contains(lq);
                    }).toList();
            });
          }

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.75,
            maxChildSize: 0.95,
            builder: (_, ctrl) => Column(
              children: [
                // ── Header ──
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFFE8001C), Color(0xFFC41E3A)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Add Item',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700)),
                            SizedBox(height: 2),
                            Text('Select an item to add as a receiving line',
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 11)),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx2),
                        child: Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(
                              color: Colors.white24, shape: BoxShape.circle),
                          child: const Icon(Icons.close,
                              color: Colors.white, size: 18),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Search box ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: TextField(
                    controller: searchCtrl,
                    onChanged: onSearch,
                    decoration: InputDecoration(
                      hintText: 'Search by name, item #, supplier code…',
                      hintStyle: const TextStyle(
                          fontSize: 12, color: Color(0xFFa0aec0)),
                      prefixIcon: const Icon(Icons.search,
                          size: 18, color: Color(0xFFa0aec0)),
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 10),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: Color(0xFFe2e8f0))),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: Color(0xFFe2e8f0))),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: Color(0xFFE8001C))),
                    ),
                  ),
                ),

                // ── List ──
                Expanded(
                  child: loadingItems
                      ? const Center(child: CircularProgressIndicator())
                      : filtered.isEmpty
                      ? const Center(
                          child: Text('No items found.',
                              style: TextStyle(color: Color(0xFF718096))))
                      : ListView.separated(
                          controller: ctrl,
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final item = filtered[i];
                            final name = item['name'] as String? ?? '—';
                            final num = item['num'] as String? ?? '';
                            final uom = item['uom'] as String? ?? '';
                            final sc =
                                item['supplierCode'] as String? ?? '';
                            final cost = double.tryParse(
                                  (item['cost']?.toString() ?? '0')
                                      .replaceAll('₱', '')
                                      .replaceAll(',', '')
                                      .trim(),
                                ) ??
                                0.0;

                            return GestureDetector(
                              onTap: () async {
                                Navigator.pop(ctx2);
                                // Build the new line
                                final newLine = <String, dynamic>{
                                  'itemNum': num,
                                  'itemName': name,
                                  'uom': uom,
                                  'supplierCode': sc,
                                  'unitCost': cost,
                                  'poQty': 1,
                                  'receivedQty': 0,
                                  'lineStatus': 'DRAFT',
                                  'remark': '',
                                  'receivedAt': null,
                                  'receivedBy': '',
                                };
                                // Append to existing lines
                                final existingLines =
                                    List<Map<String, dynamic>>.from(
                                  (r['receivingLines'] as List? ?? []).map(
                                    (l) => Map<String, dynamic>.from(
                                        l as Map),
                                  ),
                                );
                                existingLines.add(newLine);
                                try {
                                  await SyncStatusNotifier.instance
                                      .trackWrite(
                                    () => FirebaseFirestore.instance
                                        .collection(_col)
                                        .doc(docId)
                                        .update({
                                      'receivingLines': existingLines,
                                    }),
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            '${name} added to receiving'),
                                        backgroundColor: _green,
                                        behavior:
                                            SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(
                                      SnackBar(
                                        content: Text('Error: $e'),
                                        backgroundColor: _red,
                                      ),
                                    );
                                  }
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: const Color(0xFFe2e8f0)),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black
                                          .withValues(alpha: 0.03),
                                      blurRadius: 4,
                                    ),
                                  ],
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
                                                fontWeight: FontWeight.w700,
                                                fontSize: 13,
                                                color: Color(0xFF1a202c),
                                              ),
                                              children: [
                                                TextSpan(text: name),
                                                if (uom.isNotEmpty)
                                                  TextSpan(
                                                    text: '  ($uom)',
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w400,
                                                      color:
                                                          Color(0xFF718096),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            [
                                              if (num.isNotEmpty) num,
                                              if (sc.isNotEmpty) sc,
                                              if (cost > 0)
                                                _fmtPeso(cost),
                                            ].join('  ·  '),
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFF718096)),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.add_circle_outline,
                                        size: 20, color: _red),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // RECEIVE LINE MODAL
  // ─────────────────────────────────────────────────────────────────────────

  void _showReceiveLineModal(Map<String, dynamic> r, int lineIdx) async {
    final allLines = List<Map<String, dynamic>>.from(
      (r['receivingLines'] as List? ?? []).map(
        (l) => Map<String, dynamic>.from(l as Map),
      ),
    );
    if (lineIdx >= allLines.length) return;

    final line = allLines[lineIdx];
    final poQty = (line['poQty'] as num?)?.toInt() ?? 0;
    final name = await _currentUserName();
    if (!mounted) return;

    final qtyCtrl = TextEditingController(text: '$poQty');
    final remarkCtrl = TextEditingController();
    String lineStatus = _autoLineStatus(poQty, poQty);
    bool submitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setModal) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx2).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              children: [
                // ── Red header ──
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
                            const Text(
                              'Receive Item',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              r['receivingNum'] as String? ?? '',
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

                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Item card ──
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF90cdf4)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Name + uom
                            RichText(
                              text: TextSpan(
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: Color(0xFF1a202c),
                                ),
                                children: [
                                  TextSpan(
                                    text: line['itemName'] as String? ?? '—',
                                  ),
                                  if ((line['uom'] as String? ?? '').isNotEmpty)
                                    TextSpan(
                                      text: '  (${line['uom']})',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w400,
                                        color: Color(0xFF718096),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if ((line['supplierCode'] as String? ?? '')
                                .isNotEmpty)
                              Text(
                                line['supplierCode'] as String,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF718096),
                                ),
                              ),
                            const SizedBox(height: 4),
                            Text(
                              'PO Qty: $poQty',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF718096),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // ── Received qty input ──
                            TextField(
                              controller: qtyCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Received Qty *',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              onChanged: (v) {
                                final qty = int.tryParse(v) ?? 0;
                                setModal(
                                  () =>
                                      lineStatus = _autoLineStatus(qty, poQty),
                                );
                              },
                            ),
                            const SizedBox(height: 12),

                            // ── Line status buttons (mirrors web) ──
                            const Text(
                              'Line Status',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF4a5568),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                _statusBtn(
                                  '✅ Complete',
                                  'COMP',
                                  lineStatus,
                                  setModal,
                                  (v) => lineStatus = v,
                                ),
                                _statusBtn(
                                  '⚠️ Incomplete',
                                  'INCOMP',
                                  lineStatus,
                                  setModal,
                                  (v) => lineStatus = v,
                                ),
                                _statusBtn(
                                  '❌ Missing',
                                  'MISSING',
                                  lineStatus,
                                  setModal,
                                  (v) => lineStatus = v,
                                ),
                                _statusBtn(
                                  '🔴 Defective',
                                  'DEFECTIVE',
                                  lineStatus,
                                  setModal,
                                  (v) => lineStatus = v,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // ── Remarks ──
                            TextField(
                              controller: remarkCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Remarks (optional)',
                                hintText: 'e.g. 2 units damaged packaging',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // ── Received By (read-only) ──
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7F8FA),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFe2e8f0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Received By',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF4a5568),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(
                                  Icons.person_outline,
                                  size: 15,
                                  color: Color(0xFF718096),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  name.isNotEmpty ? name : '—',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1a202c),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Submit ──
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(ctx2),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 13,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                              ),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton.icon(
                              onPressed: submitting
                                  ? null
                                  : () async {
                                      setModal(() => submitting = true);
                                      await _submitLine(
                                        ctx: ctx2,
                                        r: r,
                                        lineIdx: lineIdx,
                                        allLines: allLines,
                                        receivedQty:
                                            int.tryParse(qtyCtrl.text) ?? 0,
                                        lineStatus: lineStatus,
                                        remark: remarkCtrl.text.trim(),
                                        receivedBy: name,
                                      );
                                      if (ctx2.mounted) {
                                        setModal(() => submitting = false);
                                      }
                                    },
                              icon: submitting
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
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
                                submitting ? 'Saving…' : 'Submit',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _red,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 13,
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusBtn(
    String label,
    String value,
    String current,
    StateSetter setModal,
    ValueChanged<String> onChange,
  ) {
    final active = current == value;
    final color = _lineColor(value);
    return GestureDetector(
      onTap: () => setModal(() => onChange(value)),
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

  // ─────────────────────────────────────────────────────────────────────────
  // SUBMIT LINE  (mirrors web submitReceiving)
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _submitLine({
    required BuildContext ctx,
    required Map<String, dynamic> r,
    required int lineIdx,
    required List<Map<String, dynamic>> allLines,
    required int receivedQty,
    required String lineStatus,
    required String remark,
    required String receivedBy,
  }) async {
    final docId = r['id'] as String;

    // Snapshot current stock (for the record)
    int? stockAtReceive;
    final itemNum = allLines[lineIdx]['itemNum'] as String? ?? '';
    try {
      final ss = await FirebaseFirestore.instance
          .collection('stock_inventory')
          .where('num', isEqualTo: itemNum)
          .limit(1)
          .get();
      if (ss.docs.isNotEmpty) {
        stockAtReceive = (ss.docs.first['stock'] as num?)?.toInt();
      }
    } catch (_) {}

    // Update the line
    allLines[lineIdx] = {
      ...allLines[lineIdx],
      'receivedQty': receivedQty,
      'lineStatus': lineStatus,
      'remark': remark,
      'receivedBy': receivedBy,
      'receivedAt': DateTime.now().toIso8601String(),
      'stockAtReceive': stockAtReceive,
    };

    // Recompute header status
    final newHeaderStatus = _computeHeaderStatus(allLines);

    final update = <String, dynamic>{
      'receivingLines': allLines,
      'status': newHeaderStatus,
      'receivedBy': receivedBy,
      'receivedAt': FieldValue.serverTimestamp(),
    };
    if (newHeaderStatus == 'COMP' || newHeaderStatus == 'PARTIAL') {
      update['completedAt'] = FieldValue.serverTimestamp();
    }

    try {
      await SyncStatusNotifier.instance.trackWrite(
        () => FirebaseFirestore.instance
            .collection(_col)
            .doc(docId)
            .update(update),
      );

      // ── Auto-update stock if line is COMP or INCOMP ──
      if ((lineStatus == 'COMP' || lineStatus == 'INCOMP') && receivedQty > 0) {
        await _updateStock(
          itemNum: itemNum,
          itemName: allLines[lineIdx]['itemName'] as String? ?? '',
          uom: allLines[lineIdx]['uom'] as String? ?? '',
          qty: receivedQty,
          receivedBy: receivedBy,
        );
      }

      if (ctx.mounted) {
        Navigator.pop(ctx);
        final msg = newHeaderStatus == 'COMP'
            ? '${r['receivingNum'] ?? ''} completed!'
            : 'Line saved — ${newHeaderStatus == 'PARTIAL' ? 'Partially received' : 'In progress'}';
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: newHeaderStatus == 'COMP' ? _green : _amber,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
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
  // STOCK UPDATE  (mirrors web _rcvUpdateStock)
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _updateStock({
    required String itemNum,
    required String itemName,
    required String uom,
    required int qty,
    required String receivedBy,
  }) async {
    if (itemNum.isEmpty) return;
    try {
      final now = DateTime.now();
      final dateStr = '${_months[now.month - 1]} ${now.day}, ${now.year}';

      final stockSnap = await FirebaseFirestore.instance
          .collection('stock_inventory')
          .where('num', isEqualTo: itemNum)
          .limit(1)
          .get();

      if (stockSnap.docs.isNotEmpty) {
        final doc = stockSnap.docs.first;
        final cur = (doc['stock'] as num?)?.toInt() ?? 0;
        final minLevel = (doc['min'] as num?)?.toInt() ?? 0;
        final newStock = cur + qty;
        await doc.reference.update({
          'stock': newStock,
          'status': newStock >= minLevel ? 'OK' : 'Low',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        // Create stock entry if it doesn't exist
        await FirebaseFirestore.instance.collection('stock_inventory').add({
          'num': itemNum,
          'name': itemName,
          'uom': uom,
          'stock': qty,
          'min': 0,
          'max': 0,
          'reorder': 0,
          'status': 'OK',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      // Write transaction record
      await FirebaseFirestore.instance.collection('transactions').add({
        'item': itemName,
        'desc': 'Stock received — receiving',
        'type': 'IN',
        'qty': '+$qty',
        'date': dateStr,
        'by': receivedBy,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Non-fatal — stock update failure shouldn't block the receiving flow
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ARCHIVE
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _archiveReceiving(Map<String, dynamic> r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Archive this record?',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'Archived records are hidden from the list but not deleted.',
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
            .doc(r['id'] as String)
            .update({
              'archived': true,
              'archivedAt': FieldValue.serverTimestamp(),
            }),
      );
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

  /// Called externally (e.g. from AdminInventoryHub via GlobalKey).
  void openReceiveModal(Map<String, dynamic> receiving, {int? itemIdx}) =>
      _showViewModal(receiving);

  /// Called when navigating from the PO page (Receive Items / Continue Receiving).
  /// Finds the receiving record linked to [poNum] and opens its session modal.
  /// Retries for up to 4 seconds while the stream listener is still loading.
  void openSessionForPO(String poNum) {
    _findAndOpenForPO(poNum, attempts: 0);
  }

  void _findAndOpenForPO(String poNum, {required int attempts}) {
    // Search loaded records
    final match = _rcvs.firstWhere(
      (r) =>
          (r['poNum'] as String? ?? '') == poNum &&
          ((r['status'] as String? ?? '') == 'DRAFT' ||
           (r['status'] as String? ?? '') == 'INPROG' ||
           (r['status'] as String? ?? '') == 'PARTIAL'),
      orElse: () => {},
    );

    if (match.isNotEmpty) {
      // Found — open the session view modal
      if (mounted) _showViewModal(match);
      return;
    }

    // Not found yet — retry if still loading (max 20 attempts × 200ms = 4s)
    if (attempts < 20) {
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) _findAndOpenForPO(poNum, attempts: attempts + 1);
      });
    }
  }
}
