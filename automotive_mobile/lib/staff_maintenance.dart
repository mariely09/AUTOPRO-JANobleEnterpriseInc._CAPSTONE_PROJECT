import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'barcode_scanner_screen.dart';

class StaffMaintenance extends StatefulWidget {
  final Map<String, dynamic>? bookingData;
  final Map<String, dynamic>? materialData; // pre-fill a material in the add modal
  const StaffMaintenance({super.key, this.bookingData, this.materialData});

  @override
  State<StaffMaintenance> createState() => _StaffMaintenanceState();
}

class _StaffMaintenanceState extends State<StaffMaintenance> {
  final _bodyKey = GlobalKey<StaffMaintenanceBodyState>();
  bool _searching = false;
  final _searchCtrl = TextEditingController();
  String _sortBy = 'date-desc';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFE8001C),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: _searching
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Search services...',
                  hintStyle: TextStyle(color: Colors.white54),
                  border: InputBorder.none,
                ),
              )
            : const Text('Vehicle Maintenance',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close : Icons.search, color: Colors.white),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) _searchCtrl.clear();
            }),
          ),
          if (!_searching)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onSelected: (val) => setState(() => _sortBy = val),
              itemBuilder: (_) => [
                const PopupMenuItem(enabled: false, child: Text('Sort By', style: TextStyle(fontSize: 11, color: Color(0xFF718096), fontWeight: FontWeight.w700))),
                _sortItem('date-desc',    'Date ↓ Newest',   Icons.arrow_downward),
                _sortItem('date-asc',     'Date ↑ Oldest',   Icons.arrow_upward),
                _sortItem('plate-asc',    'Plate A→Z',        Icons.sort_by_alpha),
                _sortItem('plate-desc',   'Plate Z→A',        Icons.sort_by_alpha),
                _sortItem('mechanic-asc', 'Mechanic A→Z',     Icons.person_outline),
                _sortItem('cost-desc',    'Cost ↑ Highest',   Icons.trending_up),
                _sortItem('cost-asc',     'Cost ↓ Lowest',    Icons.trending_down),
              ],
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _bodyKey.currentState?.triggerAdd(),
        backgroundColor: const Color(0xFFE8001C),
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
      body: StaffMaintenanceBody(key: _bodyKey, bookingData: widget.bookingData, materialData: widget.materialData, searchQuery: _searchCtrl.text.toLowerCase(), sortBy: _sortBy),
    );
  }

  PopupMenuItem<String> _sortItem(String val, String label, IconData icon) {
    final active = _sortBy == val;
    return PopupMenuItem(
      value: val,
      child: Row(children: [
        Icon(icon, size: 16, color: active ? const Color(0xFFE8001C) : const Color(0xFF718096)),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(fontWeight: active ? FontWeight.w700 : FontWeight.normal, color: active ? const Color(0xFFE8001C) : const Color(0xFF1a202c))),
        if (active) ...[const Spacer(), const Icon(Icons.check, size: 14, color: Color(0xFFE8001C))],
      ]),
    );
  }
}

// ── Embeddable body (used inside StaffVehicleList tabs) ──────────
class StaffMaintenanceBody extends StatefulWidget {
  final String searchQuery;
  final String sortBy;
  final Map<String, dynamic>? bookingData;
  final Map<String, dynamic>? materialData; // pre-fill a material row
  const StaffMaintenanceBody({super.key, this.searchQuery = '', this.sortBy = 'date-desc', this.bookingData, this.materialData});

  @override
  State<StaffMaintenanceBody> createState() => StaffMaintenanceBodyState();
}

class StaffMaintenanceBodyState extends State<StaffMaintenanceBody> {
  static const _red = Color(0xFFE8001C);
  static const _col = 'maintenance';

  final _searchCtrl = TextEditingController();
  final String _searchQuery = '';
  String _statusFilter = 'all';

  CollectionReference get _db => FirebaseFirestore.instance.collection(_col);

  Map<String, Map<String, dynamic>> _vehicleMap = {};
  Map<String, Map<String, dynamic>> _itemMasterMap = {};
  List<String> _serviceItems = [];
  bool _lookupLoaded = false;
  String _currentUserName = '';

  @override
  void initState() {
    super.initState();
    _loadLookups();
  }

  /// Called by parent Scaffold FAB to open the add modal.
  void triggerAdd() {
    if (!_lookupLoaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Loading data, please wait...'), duration: Duration(seconds: 1)));
      return;
    }
    _showAddServiceModal();
  }

  Future<void> _loadLookups() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final vSnap = await FirebaseFirestore.instance.collection('vehicles').get();
    final iSnap = await FirebaseFirestore.instance.collection('item_master').get();
    if (!mounted) return;
    _vehicleMap = {
      for (final d in vSnap.docs)
        (d['plate'] as String? ?? ''): d.data()
    };
    _itemMasterMap = {
      for (final d in iSnap.docs)
        (d['name'] as String? ?? ''): d.data()
    };
    _serviceItems = _itemMasterMap.entries
        .where((e) => e.value['type'] == 'Service')
        .map((e) => e.key).toList()..sort();
    // Fetch logged-in staff name
    if (uid != null) {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      _currentUserName = (userDoc.data()?['name'] as String?) ?? '';
    }
    setState(() => _lookupLoaded = true);

    // Auto-open add modal if booking data was passed
    if (widget.bookingData != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showAddServiceModal(bookingData: widget.bookingData);
      });
    }
    // Auto-open add modal if material data was passed (from scan)
    if (widget.materialData != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showAddServiceModal(materialData: widget.materialData);
      });
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Completed': return Colors.green;
      case 'Ongoing':   return Colors.orange;
      default:          return const Color(0xFF718096);
    }
  }

  Future<String> _nextSvcId() async {
    final snap = await _db.orderBy('createdAt', descending: true).limit(1).get();
    if (snap.docs.isEmpty) return 'SVC-001';
    final last = snap.docs.first['id'] as String? ?? 'SVC-000';
    final n = int.tryParse(last.replaceAll('SVC-', '')) ?? 0;
    return 'SVC-${(n + 1).toString().padLeft(3, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
        stream: _db.orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final docs = snapshot.data?.docs ?? [];
          final services = docs.map((d) {
            final data = d.data() as Map<String, dynamic>;
            return {
              'docId': d.id,
              'id': data['id'] as String? ?? d.id,
              'plate': data['plate'] as String? ?? '',
              'desc': data['desc'] as String? ?? '',
              'mechanic': data['mechanic'] as String? ?? '',
              'date': data['date'] as String? ?? '',
              'cost': data['cost'] as String? ?? '0',
              'status': data['status'] as String? ?? 'Ongoing',
              'odometer': data['odometer'],
              'svcRows': data['svcRows'],
              'matRows': data['matRows'],
              'issues': data['issues'],
            };
          }).toList();

          final activeQuery = widget.searchQuery.isNotEmpty ? widget.searchQuery : _searchQuery;
          final filtered = activeQuery.isEmpty
              ? services
              : services.where((s) =>
                  (s['id'] as String).toLowerCase().contains(activeQuery) ||
                  (s['plate'] as String).toLowerCase().contains(activeQuery) ||
                  (s['mechanic'] as String).toLowerCase().contains(activeQuery)).toList();

          final afterStatusFilter = _statusFilter == 'all'
              ? filtered
              : filtered.where((s) => s['status'] == _statusFilter).toList();

          // ── Sort ──
          final sorted = List<Map<String, dynamic>>.from(afterStatusFilter);
          sorted.sort((a, b) {
            switch (widget.sortBy) {
              case 'date-asc':  return (a['date'] as String).compareTo(b['date'] as String);
              case 'plate-asc': return (a['plate'] as String).compareTo(b['plate'] as String);
              case 'plate-desc':return (b['plate'] as String).compareTo(a['plate'] as String);
              case 'mechanic-asc': return (a['mechanic'] as String).compareTo(b['mechanic'] as String);
              case 'cost-asc':
                final ca = double.tryParse((a['cost'] as String).replaceAll(RegExp(r'[₱,]'),'')) ?? 0;
                final cb = double.tryParse((b['cost'] as String).replaceAll(RegExp(r'[₱,]'),'')) ?? 0;
                return ca.compareTo(cb);
              case 'cost-desc':
                final ca2 = double.tryParse((a['cost'] as String).replaceAll(RegExp(r'[₱,]'),'')) ?? 0;
                final cb2 = double.tryParse((b['cost'] as String).replaceAll(RegExp(r'[₱,]'),'')) ?? 0;
                return cb2.compareTo(ca2);
              default: return (b['date'] as String).compareTo(a['date'] as String); // date-desc
            }
          });

          final total = services.length;
          final ongoing = services.where((s) => s['status'] == 'Ongoing').length;
          final completed = services.where((s) => s['status'] == 'Completed').length;

          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(children: [
                _statChip('Total', '$total', Colors.blue, 'all'),
                const SizedBox(width: 8),
                _statChip('Ongoing', '$ongoing', Colors.orange, 'Ongoing'),
                const SizedBox(width: 8),
                _statChip('Completed', '$completed', Colors.green, 'Completed'),
              ]),
            ),
            Expanded(
              child: sorted.isEmpty
                ? const Center(child: Text('No services found.', style: TextStyle(color: Color(0xFF718096))))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: sorted.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _serviceCard(sorted[i]),
                  ),
            ),
          ]);
        },
      );
  }

  Widget _statChip(String label, String value, Color color, String filter) {
    IconData icon;
    switch (label) {
      case 'Total': icon = Icons.build_circle_outlined; break;
      case 'Ongoing': icon = Icons.autorenew_outlined; break;
      case 'Completed': icon = Icons.check_circle_outline; break;
      case 'Pending': icon = Icons.pending_outlined; break;
      default: icon = Icons.info_outline;
    }
    final isActive = _statusFilter == filter;
    
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _statusFilter = _statusFilter == filter ? 'all' : filter),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? color.withValues(alpha: 0.08) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isActive ? color : Colors.transparent, width: 1.5),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)]),
          child: Column(children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: const TextStyle(fontSize: 9, color: Color(0xFF718096))),
          ]),
        ),
      ),
    );
  }

  Widget _serviceCard(Map<String, dynamic> s) {
    final sc = _statusColor(s['status'] as String);
    return GestureDetector(
      onTap: () => _showServiceDetails(s),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)]),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s['plate'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            Text((s['desc'] as String).isNotEmpty ? s['desc'] as String : s['plate'] as String,
              style: const TextStyle(fontSize: 12, color: Color(0xFF4a5568))),
            Text('${s['mechanic']} - ${s['date']}', style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_formatCost(s['cost'] as String), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: sc.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
              child: Text(s['status'] as String, style: TextStyle(fontSize: 10, color: sc, fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, size: 20, color: Color(0xFFa0aec0)),
        ]),
      ),
    );
  }

  void _showServiceDetails(Map<String, dynamic> s) {
    final sc = _statusColor(s['status'] as String);
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => AnimatedPadding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
          duration: const Duration(milliseconds: 150),
          child: SingleChildScrollView(
            child: Column(children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                decoration: const BoxDecoration(color: _red, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s['plate'] as String, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    Text(s['desc'] as String, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ])),
                  GestureDetector(onTap: () => Navigator.pop(sheetCtx),
                    child: const Icon(Icons.close, color: Colors.white)),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _detailRow('Plate Number', s['plate'] as String),
                  _detailRow('Mechanic', s['mechanic'] as String),
                  _detailRow('Service Date', s['date'] as String),
                  _detailRow('Odometer Reading', (s['odometer'] != null && (s['odometer'] as num?) != 0) ? '${s['odometer']} km' : '—'),
                  _detailRow('Total Cost', _formatCost(s['cost'] as String)),
                  Row(children: [
                    const SizedBox(width: 130, child: Text('Status', style: TextStyle(fontSize: 12, color: Color(0xFF718096), fontWeight: FontWeight.w500))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: sc.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                      child: Text(s['status'] as String, style: TextStyle(fontSize: 12, color: sc, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  // ── Issues Tags ──
                  if ((s['issues'] as List?)?.isNotEmpty == true) ...[
                    const Text('Vehicle Issues Reported', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF4a5568))),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: (s['issues'] as List).map<Widget>((issue) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF5F5),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFFED7D7), width: 1.5),
                        ),
                        child: Text(issue.toString(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFE8001C))),
                      )).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if ((s['svcRows'] as List?)?.isNotEmpty == true) ...[
                    const Text('Services Rendered', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF4a5568))),
                    const SizedBox(height: 8),
                    ...(s['svcRows'] as List).where((r) => (r['name'] as String? ?? '').isNotEmpty).map((r) => _rowDetailCard(r, isService: true)),
                    const SizedBox(height: 12),
                  ],
                  if ((s['matRows'] as List?)?.isNotEmpty == true) ...[
                    const Text('Materials Used', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF4a5568))),
                    const SizedBox(height: 8),
                    ...(s['matRows'] as List).where((r) => (r['name'] as String? ?? '').isNotEmpty).map((r) => _rowDetailCard(r, isService: false)),
                    const SizedBox(height: 12),
                  ],
                  if (s['status'] == 'Ongoing') ...[
                    SizedBox(width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('Complete Service'),
                              content: Text('Mark service for ${s['plate']} as Completed?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                TextButton(onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Complete', style: TextStyle(color: Colors.green))),
                              ],
                            ),
                          );
                          if (confirm != true) return;
                          // 1. Update status immediately
                          await _db.doc(s['docId'] as String).update({'status': 'Completed'});

                          // 2. Close modal + show success right away
                          if (mounted) {
                            Navigator.pop(sheetCtx);
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Row(children: const [Icon(Icons.check_circle_outline, color: Colors.white, size: 18), SizedBox(width: 8), Text('Service marked as Completed!')]),
                              backgroundColor: Colors.green, behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
                          }

                          // 3. Run the rest in the background (non-blocking)
                          () async {
                          final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
                          final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
                          final byName = (userDoc.data()?['name'] as String?) ?? 'Staff';
                          final now = DateTime.now();
                          const txnMonths = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
                          final dateStr = '${txnMonths[now.month - 1]} ${now.day}, ${now.year}';
                          final plate = (s['plate'] as String).trim().toUpperCase();
                          final matRows = s['matRows'] as List<dynamic>? ?? [];
                          for (final r in matRows) {
                            final name = r['name'] as String? ?? '';
                            final qty = int.tryParse(r['qty'] as String? ?? '1') ?? 1;
                            final uom = r['uom'] as String? ?? '';
                            final cost = double.tryParse(r['cost'] as String? ?? '0') ?? 0;
                            if (name.isEmpty || qty <= 0) continue;
                            final iSnap = await FirebaseFirestore.instance
                                .collection('item_master').where('name', isEqualTo: name).limit(1).get();
                            final iData = iSnap.docs.isNotEmpty ? iSnap.docs.first.data() : <String, dynamic>{};
                            await FirebaseFirestore.instance.collection('issuances').add({
                              'id': 'ISS-AUTO-${DateTime.now().millisecondsSinceEpoch}',
                              'date': dateStr, 'plate': plate,
                              'assetDesc': s['desc'] ?? '', 'itemNum': iData['num'] ?? '',
                              'itemName': name, 'itemType': 'Material',
                              'commodityGroup': iData['group'] ?? '', 'uom': uom,
                              'qty': '$qty', 'unitCost': cost.toStringAsFixed(2),
                              'subtotal': (cost * qty).toStringAsFixed(2),
                              'createdBy': byName, 'maintenanceId': s['id'],
                              'createdAt': FieldValue.serverTimestamp(),
                            });
                            final stockSnap = await FirebaseFirestore.instance
                                .collection('stock_inventory').where('name', isEqualTo: name).limit(1).get();
                            if (stockSnap.docs.isNotEmpty) {
                              final stockDoc = stockSnap.docs.first;
                              final currentStock = (stockDoc['stock'] as num?)?.toInt() ?? 0;
                              final newStock = (currentStock - qty).clamp(0, 99999);
                              final minLevel = (stockDoc['min'] as num?)?.toInt() ?? 0;
                              await stockDoc.reference.update({
                                'stock': newStock,
                                'status': newStock >= minLevel ? 'OK' : 'Low',
                                'updatedAt': FieldValue.serverTimestamp(),
                              });
                            }
                            await FirebaseFirestore.instance.collection('transactions').add({
                              'item': name,
                              'desc': 'Issued for maintenance ${s['id']} - $plate',
                              'type': 'OUT', 'qty': '-$qty', 'date': dateStr, 'by': byName,
                              'createdAt': FieldValue.serverTimestamp(),
                            });
                          }
                          final svcRows = s['svcRows'] as List<dynamic>? ?? [];
                          for (final r in svcRows) {
                            final name = r['name'] as String? ?? '';
                            final qty = int.tryParse(r['qty'] as String? ?? '1') ?? 1;
                            final uom = r['uom'] as String? ?? '';
                            final cost = double.tryParse(r['cost'] as String? ?? '0') ?? 0;
                            if (name.isEmpty) continue;
                            final iSnap = await FirebaseFirestore.instance
                                .collection('item_master').where('name', isEqualTo: name).limit(1).get();
                            final iData = iSnap.docs.isNotEmpty ? iSnap.docs.first.data() : <String, dynamic>{};
                            await FirebaseFirestore.instance.collection('issuances').add({
                              'id': 'ISS-AUTO-${DateTime.now().millisecondsSinceEpoch}-S',
                              'date': dateStr, 'plate': plate,
                              'assetDesc': s['desc'] ?? '', 'itemNum': iData['num'] ?? '',
                              'itemName': name, 'itemType': 'Service',
                              'commodityGroup': iData['group'] ?? '', 'uom': uom,
                              'qty': '$qty', 'unitCost': cost.toStringAsFixed(2),
                              'subtotal': (cost * qty).toStringAsFixed(2),
                              'createdBy': byName, 'maintenanceId': s['id'],
                              'createdAt': FieldValue.serverTimestamp(),
                            });
                          }
                          final vSnap = await FirebaseFirestore.instance
                              .collection('vehicles').where('plate', isEqualTo: plate).limit(1).get();
                          if (vSnap.docs.isNotEmpty) {
                            final vUpdate = <String, dynamic>{
                              'status': 'Completed',
                              'completedAt': FieldValue.serverTimestamp(),
                              'lastSvcDate': '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
                            };
                            // Also update odometer fields from the maintenance record
                            final mainDoc = await _db.doc(s['docId'] as String).get();
                            final mainData = mainDoc.data() as Map<String, dynamic>? ?? {};
                            final odoReading = mainData['odometer'];
                            if (odoReading != null) {
                              final odoInt = int.tryParse(odoReading.toString()) ?? 0;
                              if (odoInt > 0) {
                                vUpdate['lastSvcOdo'] = odoInt;
                                vUpdate['lastServiceOdometer'] = odoInt;
                                vUpdate['odometer'] = odoInt;
                                vUpdate['odo'] = '$odoInt km';
                              }
                            }
                            await vSnap.docs.first.reference.update(vUpdate);
                          }

                          // Also update linked service booking to "Completed" if exists
                          final mainDoc3 = await _db.doc(s['docId'] as String).get();
                          final mainData3 = mainDoc3.data() as Map<String, dynamic>? ?? {};
                          final bookingId = mainData3['bookingId'] as String?;
                          if (bookingId != null && bookingId.isNotEmpty) {
                            await FirebaseFirestore.instance.collection('service_bookings').doc(bookingId).update({'status': 'Completed'}).catchError((_) {});
                          }
                          }(); // end background lambda
                        },
                        icon: const Icon(Icons.done_all, size: 16),
                        label: const Text('Mark as Completed'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                      )),
                    const SizedBox(height: 8),
                  ],
                  if (s['status'] != 'Completed')
                    SizedBox(width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () { Navigator.pop(sheetCtx); _showAddServiceModal(service: s); },
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('Edit'),
                      )),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _rowDetailCard(dynamic r, {required bool isService}) {
    final name = r['name'] as String? ?? '';
    final qty = r['qty'] as String? ?? '1';
    final uom = r['uom'] as String? ?? '';
    final cost = r['cost'] as String? ?? '0';
    final subtotal = (double.tryParse(cost) ?? 0) * (double.tryParse(qty) ?? 1);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFe2e8f0)),
      ),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          Text('$qty $uom  -  $cost / unit', style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
        ])),
        Text(_fmtMoney(subtotal),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1a202c))),
      ]),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 130, child: Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF718096), fontWeight: FontWeight.w500))),
        Expanded(child: Text(value.isNotEmpty ? value : '-', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1a202c)))),
      ]),
    );
  }

  void _showAddServiceModal({Map<String, dynamic>? service, Map<String, dynamic>? bookingData, Map<String, dynamic>? materialData}) async {
    final isEdit = service != null;

    // Pre-fill from booking data if available
    String prefillPlate = service?['plate'] as String? ?? '';
    String prefillDate  = service?['date']  as String? ??
        '${_monthName(DateTime.now().month)} ${DateTime.now().day}, ${DateTime.now().year}';
    List<dynamic>? prefillServices;
    String? bookingId;

    if (bookingData != null) {
      prefillPlate = bookingData['plate'] as String? ?? '';
      final bookingDateStr = bookingData['preferredDate'] as String? ?? '';
      if (bookingDateStr.isNotEmpty) {
        final dt = DateTime.tryParse(bookingDateStr);
        if (dt != null) prefillDate = '${_monthName(dt.month)} ${dt.day}, ${dt.year}';
      }
      prefillServices = bookingData['services'] as List?;
      bookingId       = bookingData['bookingId'] as String?;
    }

    final plateCtrl    = TextEditingController(text: prefillPlate);
    final mechanicCtrl = TextEditingController(text: service?['mechanic'] as String? ?? (isEdit ? '' : _currentUserName));
    final dateCtrl     = TextEditingController(text: prefillDate);
    final odoCtrl      = TextEditingController(text: () {
      final raw = (service?['odometer'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
      return (raw == '0' || raw.isEmpty) ? '' : raw;
    }());
    Map<String, dynamic>? foundVehicle = isEdit ? _vehicleMap[service!['plate']] : _vehicleMap[prefillPlate.toUpperCase()];

    // ── Issue tags ──
    const presetIssues = [
      'Engine Problem', 'Brake Issue', 'Tire/Wheel', 'Battery', 'Overheating',
      'Oil Leak', 'Transmission', 'Suspension', 'Electrical', 'AC/Cooling',
      'Exhaust', 'Steering', 'Fuel System', 'Body Damage', 'Lights/Signals',
    ];
    final selectedIssues = List<String>.from(
      (service?['issues'] as List<dynamic>?)?.map((e) => e.toString()) ?? [],
    );
    final customIssueCtrl = TextEditingController();

    List<Map<String, TextEditingController>> makeRows(List<dynamic>? saved) {
      if (saved != null && saved.isNotEmpty) {
        return saved.map<Map<String, TextEditingController>>((r) => {
          'name': TextEditingController(text: r['name'] ?? ''),
          'qty':  TextEditingController(text: r['qty']  ?? ''),
          'uom':  TextEditingController(text: r['uom']  ?? ''),
          'cost': TextEditingController(text: r['cost'] ?? ''),
          'maxStock':   TextEditingController(text: '99999'),
          'searchText': TextEditingController(text: r['name'] ?? ''),
        }).toList();
      }
      return [{'name': TextEditingController(), 'qty': TextEditingController(), 'uom': TextEditingController(), 'cost': TextEditingController()}];
    }

    // Pre-fill service rows from booking if available
    List<Map<String, TextEditingController>> svcRows;
    if (bookingData != null && prefillServices != null && prefillServices.isNotEmpty) {
      svcRows = prefillServices.map<Map<String, TextEditingController>>((svcName) {
        final name = svcName.toString();
        final d    = _itemMasterMap[name];
        return {
          'name': TextEditingController(text: name),
          'qty':  TextEditingController(text: '1'),
          'uom':  TextEditingController(text: (d?['uom'] ?? 'job').toString()),
          'cost': TextEditingController(text: (d?['cost'] ?? '0').toString().replaceAll('₱','').replaceAll(',','').trim()),
        };
      }).toList();
    } else {
      svcRows = makeRows(service?['svcRows'] as List<dynamic>?);
    }

    // Pre-fill material rows from scan if available
    List<Map<String, TextEditingController>> matRows;
    if (materialData != null) {
      final matName = materialData['name'] as String? ?? '';
      final d = _itemMasterMap[matName];
      final rawCost = (d?['cost'] ?? materialData['cost'] ?? '0').toString().replaceAll('₱','').replaceAll(',','').trim();
      final uom = (d?['uom'] ?? materialData['uom'] ?? '').toString();
      final maxStockCtrl = TextEditingController(text: '99999');
      matRows = [{
        'name':       TextEditingController(text: matName),
        'qty':        TextEditingController(text: '1'),
        'uom':        TextEditingController(text: uom),
        'cost':       TextEditingController(text: rawCost),
        'maxStock':   maxStockCtrl,
        'searchText': TextEditingController(text: matName),
      }];
      // Look up stock immediately so the badge shows the correct value
      FirebaseFirestore.instance
          .collection('stock_inventory')
          .where('name', isEqualTo: matName)
          .limit(1)
          .get()
          .then((snap) {
        final available = snap.docs.isNotEmpty
            ? (snap.docs.first['stock'] as num?)?.toInt() ?? 0
            : -1;
        maxStockCtrl.text = '$available';
      }).catchError((_) {});
    } else {
      matRows = makeRows(service?['matRows'] as List<dynamic>?);
      // Look up stock for each existing material row (edit mode)
      for (final row in matRows) {
        final name = row['name']!.text;
        if (name.isEmpty) continue;
        final maxStockCtrl = row['maxStock']!;
        FirebaseFirestore.instance
            .collection('stock_inventory').where('name', isEqualTo: name).limit(1).get()
            .then((snap) {
          maxStockCtrl.text = snap.docs.isNotEmpty
              ? '${(snap.docs.first['stock'] as num?)?.toInt() ?? 0}'
              : '-1';
        }).catchError((_) {});
      }
    }

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) {
          double totalCost() {
            double t = 0;
            for (final r in [...svcRows, ...matRows]) {
              t += (double.tryParse(r['cost']!.text) ?? 0) * (double.tryParse(r['qty']!.text) ?? 1);
            }
            return t;
          }
          return AnimatedPadding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            duration: const Duration(milliseconds: 150),
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                  decoration: const BoxDecoration(color: _red, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                  child: Row(children: [
                    const SizedBox(width: 12),
                    Expanded(child: Text(isEdit ? 'Edit Service' : 'New Service',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
                    GestureDetector(onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.close, color: Colors.white)),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Autocomplete<String>(
                      initialValue: TextEditingValue(text: plateCtrl.text),
                      optionsBuilder: (value) {
                        final q = value.text.trim().toUpperCase();
                        if (q.isEmpty) return _vehicleMap.keys;
                        return _vehicleMap.keys.where((p) => p.contains(q));
                      },
                      onSelected: (plate) {
                        plateCtrl.text = plate;
                        setModal(() => foundVehicle = _vehicleMap[plate]);
                      },
                      fieldViewBuilder: (ctx2, ctrl, focusNode, onSubmit) => TextField(
                        controller: ctrl,
                        focusNode: focusNode,
                        textCapitalization: TextCapitalization.characters,
                        onChanged: (v) => setModal(() => foundVehicle = _vehicleMap[v.trim().toUpperCase()]),
                        decoration: InputDecoration(
                          labelText: 'Plate Number *',
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF718096)),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.qr_code_scanner, color: Color(0xFF718096)),
                            onPressed: () async {
                              final result = await Navigator.push<String>(context,
                                MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()));
                              if (result != null) {
                                ctrl.text = result.toUpperCase();
                                plateCtrl.text = result.toUpperCase();
                                setModal(() => foundVehicle = _vehicleMap[result.toUpperCase()]);
                              }
                            },
                          ),
                        ),
                      ),
                      optionsViewBuilder: (ctx2, onSelected, options) => Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 6,
                          borderRadius: BorderRadius.circular(10),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 200),
                            child: ListView.separated(
                              padding: EdgeInsets.zero, shrinkWrap: true,
                              itemCount: options.length,
                              separatorBuilder: (_, _) => const Divider(height: 1),
                              itemBuilder: (_, i) {
                                final plate = options.elementAt(i);
                                final v = _vehicleMap[plate];
                                return ListTile(
                                  dense: true,
                                  title: Text(plate, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  subtitle: Text(v?['desc'] as String? ?? '', style: const TextStyle(fontSize: 11)),
                                  onTap: () => onSelected(plate),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (foundVehicle != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFe2e8f0)),
                        ),
                        child: Row(children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(foundVehicle!['desc'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            Text(foundVehicle!['owner'] as String? ?? '', style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
                          ])),
                        ]),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(controller: mechanicCtrl,
                      decoration: const InputDecoration(labelText: 'Mechanic Name *', hintText: 'Search or type name...', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person_outline, size: 20, color: Color(0xFF718096)))),
                    const SizedBox(height: 10),
                    TextField(
                      controller: dateCtrl, readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'Service Date *',
                        hintText: 'Select date',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.calendar_today_outlined, color: Color(0xFF718096)),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: ctx, initialDate: DateTime.now(),
                              firstDate: DateTime(2020), lastDate: DateTime(2030),
                              builder: (c, child) => Theme(
                                data: Theme.of(c).copyWith(colorScheme: const ColorScheme.light(primary: _red)),
                                child: child!),
                            );
                            if (picked != null) {
                              dateCtrl.text = '${_monthName(picked.month)} ${picked.day}, ${picked.year}';
                              setModal(() {});
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // ── Odometer Reading ──
                    TextField(controller: odoCtrl, keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Odometer Reading (km)', border: OutlineInputBorder(), suffixText: 'km')),
                    const SizedBox(height: 16),
                    // ── Vehicle Issues ──
                    const Text('Vehicle Issues', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF4a5568))),
                    const SizedBox(height: 4),
                    Text('Optional — select all that apply', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ...presetIssues.map((issue) {
                          final sel = selectedIssues.contains(issue);
                          return GestureDetector(
                            onTap: () => setModal(() {
                              if (sel) selectedIssues.remove(issue);
                              else selectedIssues.add(issue);
                            }),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: sel ? _red : Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: sel ? _red : const Color(0xFFe2e8f0), width: 1.5),
                              ),
                              child: Text(issue, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: sel ? Colors.white : const Color(0xFF4a5568))),
                            ),
                          );
                        }),
                        // Custom issues not in preset
                        ...selectedIssues.where((i) => !presetIssues.contains(i)).map((issue) =>
                          GestureDetector(
                            onTap: () => setModal(() => selectedIssues.remove(issue)),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(color: _red, borderRadius: BorderRadius.circular(20), border: Border.all(color: _red, width: 1.5)),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Text(issue, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                                const SizedBox(width: 4),
                                const Icon(Icons.close, size: 12, color: Colors.white),
                              ]),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: TextField(
                        controller: customIssueCtrl,
                        decoration: const InputDecoration(
                          hintText: 'Add custom issue...',
                          hintStyle: TextStyle(fontSize: 12),
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          isDense: true,
                        ),
                        onSubmitted: (v) {
                          final val = v.trim();
                          if (val.isNotEmpty && !selectedIssues.contains(val)) {
                            setModal(() { selectedIssues.add(val); customIssueCtrl.clear(); });
                          }
                        },
                      )),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          final val = customIssueCtrl.text.trim();
                          if (val.isNotEmpty && !selectedIssues.contains(val)) {
                            setModal(() { selectedIssues.add(val); customIssueCtrl.clear(); });
                          }
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
                        child: const Text('+ Add', style: TextStyle(fontSize: 12)),
                      ),
                    ]),
                    const SizedBox(height: 16),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('Services Rendered', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF4a5568))),
                      TextButton.icon(
                        onPressed: () => setModal(() => svcRows.add({'name': TextEditingController(), 'qty': TextEditingController(), 'uom': TextEditingController(), 'cost': TextEditingController()})),
                        icon: const Icon(Icons.add, size: 16), label: const Text('Add Row', style: TextStyle(fontSize: 12)),
                      ),
                    ]),
                    ...svcRows.asMap().entries.map((e) => _svcRow(e.value, () => setModal(() => svcRows.removeAt(e.key)), setModal, svcRows, ctx)),
                    const SizedBox(height: 12),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('Materials Used', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF4a5568))),
                      TextButton.icon(
                        onPressed: () => setModal(() => matRows.add({'name': TextEditingController(), 'qty': TextEditingController(), 'uom': TextEditingController(), 'cost': TextEditingController()})),
                        icon: const Icon(Icons.add, size: 16), label: const Text('Add Row', style: TextStyle(fontSize: 12)),
                      ),
                    ]),
                    ...matRows.asMap().entries.map((e) => _matRow(e.value, () => setModal(() => matRows.removeAt(e.key)), setModal, ctx, matRows)),
                    const SizedBox(height: 12),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('Total Cost:', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF2c5282), fontSize: 14)),
                      Text(_fmtMoney(totalCost()),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2b6cb0))),
                    ]),
                    const SizedBox(height: 20),
                    Row(children: [
                      Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))),
                      const SizedBox(width: 12),
                      Expanded(child: ElevatedButton(
                        onPressed: () async {
                          if (plateCtrl.text.trim().isEmpty || mechanicCtrl.text.trim().isEmpty) return;
                          final odoValue = int.tryParse(odoCtrl.text.trim()) ?? 0;

                          // Validate material quantities against stock
                          for (final r in matRows) {
                            final name = r['name']!.text.trim();
                            final qty = int.tryParse(r['qty']!.text.trim()) ?? 0;
                            if (name.isEmpty || qty <= 0) continue;
                            final stockSnap = await FirebaseFirestore.instance
                                .collection('stock_inventory').where('name', isEqualTo: name).limit(1).get();
                            if (stockSnap.docs.isNotEmpty) {
                              final available = (stockSnap.docs.first['stock'] as num?)?.toInt() ?? 0;
                              if (qty > available) {
                                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text('Insufficient stock for "$name". Available: $available, Requested: $qty'),
                                  backgroundColor: Colors.orange, behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
                                return;
                              }
                            }
                          }

                          // Duplicate plate check — prevent adding if plate already has Pending/Ongoing service
                          if (!isEdit) {
                            final dupCheck = await _db
                                .where('plate', isEqualTo: plateCtrl.text.trim().toUpperCase())
                                .where('status', whereIn: ['Ongoing'])
                                .limit(1)
                                .get();
                            if (dupCheck.docs.isNotEmpty) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Row(children: const [
                                    Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
                                    SizedBox(width: 8),
                                    Expanded(child: Text('This plate already has an Ongoing service. Complete or delete it first.')),
                                  ]),
                                  backgroundColor: Colors.orange, behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
                              }
                              return;
                            }
                          }

                          final svcId = isEdit ? service['id'] as String : await _nextSvcId();
                          final data = <String, dynamic>{
                            'id': svcId,
                            'plate': plateCtrl.text.trim().toUpperCase(),
                            'desc': foundVehicle?['desc'] as String? ?? '',
                            'mechanic': mechanicCtrl.text.trim(),
                            'date': dateCtrl.text.trim(),
                            'odometer': odoValue,
                            'cost': _fmtMoney(totalCost()),
                            'status': isEdit ? service['status'] as String : 'Ongoing',
                            'issues': selectedIssues,
                            'svcRows': svcRows.map((r) => {'name': r['name']!.text, 'qty': r['qty']!.text, 'uom': r['uom']!.text, 'cost': r['cost']!.text}).toList(),
                            'matRows': matRows.map((r) => {'name': r['name']!.text, 'qty': r['qty']!.text, 'uom': r['uom']!.text, 'cost': r['cost']!.text}).toList(),
                            if (bookingId != null && bookingId.isNotEmpty) 'bookingId': bookingId,
                          };
                          try {
                            if (isEdit) {
                              await _db.doc(service['docId'] as String).update(data);
                              await _updateVehicleOdometer(
                                plateCtrl.text.trim().toUpperCase(), odoValue);
                              if (context.mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Row(children: const [Icon(Icons.check_circle_outline, color: Colors.white, size: 18), SizedBox(width: 8), Text('Updated successfully!')]),
                                  backgroundColor: Colors.green, behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
                              }
                            } else {
                              data['createdAt'] = FieldValue.serverTimestamp();
                              await _db.add(data);
                              await _updateVehicleOdometer(
                                plateCtrl.text.trim().toUpperCase(), odoValue);
                              // Set vehicle status to Under Maintenance when Ongoing service is created
                              final pSnap = await FirebaseFirestore.instance
                                  .collection('vehicles')
                                  .where('plate', isEqualTo: plateCtrl.text.trim().toUpperCase())
                                  .limit(1).get();
                              if (pSnap.docs.isNotEmpty) {
                                await pSnap.docs.first.reference.update({'status': 'Under Maintenance'});
                              }
                              if (context.mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Row(children: const [Icon(Icons.check_circle_outline, color: Colors.white, size: 18), SizedBox(width: 8), Text('Added successfully!')]),
                                  backgroundColor: Colors.green, behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
                              }
                            }
                          } catch (e) {
                            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                          }
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white),
                        child: Text(isEdit ? 'Update' : 'Save'),
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

  Widget _svcRow(Map<String, TextEditingController> row, VoidCallback onRemove, StateSetter setModal, List<Map<String, TextEditingController>> allSvcRows, BuildContext ctx) {
    row.putIfAbsent('searchText', () => TextEditingController(text: row['name']!.text));

    Future<void> applyService(String name) async {
      final alreadyUsed = allSvcRows.any((r) => r != row && r['name']!.text == name);
      if (alreadyUsed) {
        showDialog(
          context: ctx,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: const Row(children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 22),
              SizedBox(width: 8),
              Text('Duplicate Service', style: TextStyle(fontSize: 15)),
            ]),
            content: const Text('This service is already added.'),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
          ),
        );
        return;
      }
      row['name']!.text = name;
      row['searchText']!.text = name;
      final d = _itemMasterMap[name];
      row['uom']!.text = (d?['uom'] ?? 'job').toString();
      row['cost']!.text = (d?['cost'] ?? '0').toString().replaceAll('₱', '').replaceAll(',', '').trim();
      if (row['qty']!.text.isEmpty) row['qty']!.text = '1';
      setModal(() {});
    }

    final isSelected = row['name']!.text.isNotEmpty;
    final q = row['searchText']!.text.trim().toLowerCase();
    final svcResults = isSelected ? <String>[] : (q.isEmpty
        ? <String>[]
        : _serviceItems.where((n) => n.toLowerCase().contains(q)).toList());

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: isSelected
              ? Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFe2e8f0)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(row['name']!.text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                      GestureDetector(
                        onTap: () {
                          row['name']!.text = '';
                          row['searchText']!.text = '';
                          row['uom']!.text = '';
                          row['cost']!.text = '';
                          setModal(() {});
                        },
                        child: const Icon(Icons.close, size: 14, color: Color(0xFF718096)),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Text('${row['uom']!.text}  •  ₱${row['cost']!.text}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
                    const SizedBox(height: 8),
                    TextField(controller: row['qty'], keyboardType: TextInputType.number, onChanged: (_) => setModal(() {}),
                      decoration: const InputDecoration(labelText: 'Quantity *', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8), isDense: true)),
                  ]),
                )
              : TextField(
                  controller: row['searchText']!,
                  onChanged: (_) => setModal(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Service Name *',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    isDense: true,
                    prefixIcon: Icon(Icons.search, size: 18, color: Color(0xFF718096)),
                  ),
                ),
          ),
          SizedBox(width: 32, child: IconButton(icon: const Icon(Icons.close, size: 16, color: Colors.red), padding: EdgeInsets.zero, onPressed: onRemove)),
        ]),
        if (!isSelected) ...[
          if (svcResults.isEmpty && q.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFF7F8FA), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFe2e8f0))),
                child: const Center(child: Text('No services found.', style: TextStyle(fontSize: 12, color: Color(0xFFa0aec0)))),
              ),
            )
          else
            ...svcResults.take(6).map((name) {
              final d = _itemMasterMap[name];
              return GestureDetector(
                onTap: () => applyService(name),
                child: Container(
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFe2e8f0)),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4)]),
                  child: Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF1a202c))),
                      if (d != null) Text('${d['uom'] ?? ''}  •  ₱${(d['cost'] ?? '0').toString().replaceAll('₱','').replaceAll(',','').trim()}',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
                    ])),
                    const Icon(Icons.add_circle_outline, size: 16, color: Color(0xFF718096)),
                  ]),
                ),
              );
            }),
        ],
      ]),
    );
  }

  Widget _matRow(Map<String, TextEditingController> row, VoidCallback onRemove, StateSetter setModal, BuildContext ctx, List<Map<String, TextEditingController>> allMatRows) {
    row.putIfAbsent('maxStock', () => TextEditingController(text: '99999'));
    row.putIfAbsent('searchText', () => TextEditingController());

    // Material names from item master (type == Material)
    final materialNames = _itemMasterMap.entries
        .where((e) => (e.value['type'] as String? ?? '').toLowerCase() == 'material')
        .map((e) => e.key)
        .toList()..sort();

    Future<void> applyMaterial(String name) async {
      final alreadyUsed = allMatRows.any((r) => r != row && r['name']!.text == name);
      if (alreadyUsed) {
        showDialog(
          context: ctx,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: const Row(children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 22),
              SizedBox(width: 8),
              Text('Duplicate Material', style: TextStyle(fontSize: 15)),
            ]),
            content: const Text('This material is already added.'),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
          ),
        );
        return;
      }
      final d = _itemMasterMap[name];
      if (d == null) return;
      row['name']!.text = name;
      row['searchText']!.text = name;
      row['uom']!.text = (d['uom'] ?? '').toString();
      final rawCost = d['cost'];
      row['cost']!.text = rawCost == null
          ? '0'
          : rawCost.toString().replaceAll('₱', '').replaceAll(',', '').trim();
      if (row['qty']!.text.isEmpty) row['qty']!.text = '1';
      final stockSnap = await FirebaseFirestore.instance
          .collection('stock_inventory').where('name', isEqualTo: name).limit(1).get();
      final available = stockSnap.docs.isNotEmpty
          ? (stockSnap.docs.first['stock'] as num?)?.toInt() ?? 0
          : -1; // -1 means no stock record found
      row['maxStock']!.text = '$available';
      final currentQty = int.tryParse(row['qty']!.text) ?? 1;
      if (available >= 0 && currentQty > available) row['qty']!.text = '$available';
      setModal(() {});
    }

    final maxStock = int.tryParse(row['maxStock']!.text) ?? 99999;
    final isSelected = row['name']!.text.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: isSelected
              ? Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFe2e8f0)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(row['name']!.text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                      GestureDetector(
                        onTap: () {
                          row['name']!.text = '';
                          row['searchText']!.text = '';
                          row['uom']!.text = '';
                          row['cost']!.text = '';
                          row['maxStock']!.text = '99999';
                          setModal(() {});
                        },
                        child: const Icon(Icons.close, size: 14, color: Color(0xFF718096)),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Text('${row['uom']!.text}  •  ₱${row['cost']!.text}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
                    const SizedBox(height: 4),
                    // Always show stock badge once material is selected
                    Builder(builder: (_) {
                      final ms = int.tryParse(row['maxStock']!.text) ?? 99999;
                      if (ms == 99999) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: const Color(0xFFF7F8FA), borderRadius: BorderRadius.circular(20)),
                          child: const Text('Checking stock...', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF718096))),
                        );
                      }
                      if (ms < 0) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: const Color(0xFFF7F8FA), borderRadius: BorderRadius.circular(20)),
                          child: const Text('No stock record', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF718096))),
                        );
                      }
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: ms == 0 ? const Color(0xFFFFF5F5) : ms <= 5 ? const Color(0xFFFFFBEB) : const Color(0xFFF0FFF4),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          ms == 0 ? '⚠ Out of stock' : 'Available stock: $ms',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                            color: ms == 0 ? Colors.red : ms <= 5 ? Colors.orange : Colors.green),
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                    TextField(
                      controller: row['qty'],
                      keyboardType: TextInputType.number,
                      enabled: maxStock != 0,
                      inputFormatters: (maxStock > 0 && maxStock < 99999)
                          ? [
                              FilteringTextInputFormatter.digitsOnly,
                              _MaxValueFormatter(maxStock),
                            ]
                          : [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (_) => setModal(() {}),
                      decoration: InputDecoration(
                        labelText: (maxStock > 0 && maxStock < 99999)
                            ? 'Quantity * (max $maxStock)'
                            : 'Quantity *',
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        isDense: true,
                        errorText: maxStock == 0 ? 'Out of stock' : null,
                      ),
                    ),
                  ]),
                )
              : TextField(
                  controller: row['searchText']!,
                  onChanged: (_) => setModal(() {}),
                  decoration: InputDecoration(
                    labelText: 'Material Name *',
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF718096)),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.qr_code_scanner, size: 18, color: Color(0xFF003087)),
                      padding: EdgeInsets.zero,
                      onPressed: () async {
                        final result = await Navigator.push<String>(ctx,
                          MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()));
                        if (result != null) {
                          final match = _itemMasterMap.entries.firstWhere(
                            (e) => e.value['barcode'] == result || e.value['qr'] == result,
                            orElse: () => MapEntry('', {}),
                          );
                          if (match.key.isNotEmpty) applyMaterial(match.key);
                        }
                      },
                    ),
                  ),
                ),
          ),
          SizedBox(width: 32, child: IconButton(
            icon: const Icon(Icons.close, size: 16, color: Colors.red),
            padding: EdgeInsets.zero,
            onPressed: onRemove,
          )),
        ]),
        // ── Inline material results ──
        if (!isSelected) ...[
          if (row['searchText']!.text.trim().isNotEmpty &&
              materialNames.where((n) => n.toLowerCase().contains(row['searchText']!.text.trim().toLowerCase())).isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFF7F8FA), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFe2e8f0))),
                child: const Center(child: Text('No materials found.', style: TextStyle(fontSize: 12, color: Color(0xFFa0aec0)))),
              ),
            )
          else
            ...(() {
              final q = row['searchText']!.text.trim().toLowerCase();
              final res = q.isEmpty ? <String>[] : materialNames.where((n) => n.toLowerCase().contains(q)).toList();
              return res.take(6).map((name) {
                final d = _itemMasterMap[name];
                return GestureDetector(
                  onTap: () => applyMaterial(name),
                  child: Container(
                    margin: const EdgeInsets.only(top: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFe2e8f0)),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4)]),
                    child: Row(children: [
                      Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF1a202c)))),
                    ]),
                  ),
                );
              });
            })(),
        ],
      ]),
    );
  }

  /// Updates the vehicle's odometer fields in Firestore immediately when a
  /// maintenance record is saved (Pending status), so the odo column stays current.
  Future<void> _updateVehicleOdometer(String plate, int odoValue) async {
    if (plate.isEmpty || odoValue <= 0) return;
    try {
      final vSnap = await FirebaseFirestore.instance
          .collection('vehicles')
          .where('plate', isEqualTo: plate)
          .limit(1)
          .get();
      if (vSnap.docs.isEmpty) {
        final all = await FirebaseFirestore.instance.collection('vehicles').get();
        final match = all.docs.where((d) =>
            (d['plate'] as String? ?? '').toUpperCase() == plate.toUpperCase()).toList();
        if (match.isNotEmpty) {
          await match.first.reference.update({
            'odometer': odoValue,
            'odo': '$odoValue km',
          });
        }
      } else {
        await vSnap.docs.first.reference.update({
          'odometer': odoValue,
          'odo': '$odoValue km',
        });
      }
    } catch (_) {}
  }

  String _formatCost(String raw) {
    final clean = raw.replaceAll('₱', '').replaceAll(',', '').trim();
    final val = double.tryParse(clean);
    if (val == null) return raw.startsWith('₱') ? raw : '₱$raw';
    return _fmtMoney(val);
  }

  String _fmtMoney(double val) {
    final parts = val.toStringAsFixed(2).split('.');
    final intPart = parts[0];
    final decPart = parts[1];
    final buffer = StringBuffer();
    for (int i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buffer.write(',');
      buffer.write(intPart[i]);
    }
    return '₱$buffer.$decPart';
  }

  String _monthName(int m) => const ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][m - 1];
}

/// Blocks input that would result in a value exceeding [max].
class _MaxValueFormatter extends TextInputFormatter {
  final int max;
  const _MaxValueFormatter(this.max);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;
    final entered = int.tryParse(newValue.text);
    if (entered == null) return oldValue;
    if (entered > max) return oldValue; // block — don't apply the new value
    return newValue;
  }
}
