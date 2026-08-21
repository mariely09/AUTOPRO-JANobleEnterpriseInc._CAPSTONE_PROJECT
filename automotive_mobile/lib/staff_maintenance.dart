import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'barcode_scanner_screen.dart';
import 'sync_indicator.dart';

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
          const SyncIndicator(),
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
      body: OfflineSaveListener(
        child: StaffMaintenanceBody(key: _bodyKey, bookingData: widget.bookingData, materialData: widget.materialData, searchQuery: _searchCtrl.text.toLowerCase(), sortBy: _sortBy)),
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
  List<Map<String, dynamic>> _allItems = []; // full list preserving duplicates
  List<String> _serviceItems = [];
  bool _lookupLoaded = false;
  String _currentUserName = '';
  Set<String> _inactiveItemNames = {}; // names of Inactive stock items
  Map<String, int> _stockMap = {};    // name.lower → current stock qty (for dropdown oos badge)
  // Stable GlobalKeys for _ItemSearchField — keyed by row object identity
  final _rowKeys = <int, GlobalKey>{};

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
    _vehicleMap = {};
    for (final d in vSnap.docs) {
      final data = d.data();
      // Index by BOTH plateNumber (canonical) and plate (legacy) so lookups
      // work regardless of which field was written by the creation path.
      final plateNumber = (data['plateNumber'] as String? ?? '').trim().toUpperCase();
      final plateLegacy = (data['plate']       as String? ?? '').trim().toUpperCase();
      final entry = {
        ...data,
        '_docId':  d.id,                // vehicle document ID (= vehicleId)
        'ownerId': data['ownerId'] ?? '',
      };
      if (plateNumber.isNotEmpty) _vehicleMap[plateNumber] = entry;
      if (plateLegacy.isNotEmpty && plateLegacy != plateNumber) {
        _vehicleMap[plateLegacy] = entry;
      }
    }
    _itemMasterMap = {
      for (final d in iSnap.docs)
        (d['name'] as String? ?? ''): d.data()
    };
    _allItems = iSnap.docs.map((d) {
      final data = d.data();
      // Support both 'type' and 'itemType' field names
      final type = (data['type'] as String? ?? data['itemType'] as String? ?? 'Material');
      return {
        'name': data['name'] as String? ?? '',
        'type': type,
        'uom':  data['uom']  as String? ?? '',
        'cost': data['cost'] ?? '0',
        'num':  data['num']  as String? ?? '',
        'supplierCode': data['supplierCode'] as String? ?? '',
        'barcode': data['barcode'] as String? ?? '',
        'qr':    data['qr']  as String? ?? '',
      };
    }).toList();
    _serviceItems = _itemMasterMap.entries
        .where((e) {
          final t = (e.value['type'] as String? ?? e.value['itemType'] as String? ?? '').toLowerCase();
          return t == 'service';
        })
        .map((e) => e.key).toList()..sort();
    // Fetch logged-in staff name
    if (uid != null) {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      _currentUserName = (userDoc.data()?['name'] as String?) ?? '';
    }
    // Load stock inventory — build stockMap (name→qty) and inactiveItemNames
    try {
      final stockSnap = await FirebaseFirestore.instance
          .collection('stock_inventory').get();
      _stockMap = {
        for (final d in stockSnap.docs)
          (d['name'] as String? ?? '').toLowerCase():
            (d['stock'] as num?)?.toInt() ?? 0
      };
      _inactiveItemNames = stockSnap.docs
          .where((d) => (d['status'] as String? ?? '') == 'Inactive')
          .map((d) => (d['name'] as String? ?? '').toLowerCase())
          .where((n) => n.isNotEmpty).toSet();
    } catch (_) {}
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
    // Timestamp-based ID — zero network calls, always instant.
    final now = DateTime.now();
    final stamp = '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}'
        '-'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    return 'SVC-$stamp';
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
            // Skip archived records
            if (data['archived'] == true) return null;
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
          }).whereType<Map<String, dynamic>>().toList();

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
          // Parse "Jan 5, 2026" style dates to milliseconds for correct ordering
          int dateMs(String d) {
            try {
              const months = {'Jan':1,'Feb':2,'Mar':3,'Apr':4,'May':5,'Jun':6,'Jul':7,'Aug':8,'Sep':9,'Oct':10,'Nov':11,'Dec':12};
              final parts = d.replaceAll(',', '').split(' ');
              if (parts.length < 3) return 0;
              final m = months[parts[0]] ?? 0;
              final day = int.tryParse(parts[1]) ?? 0;
              final yr  = int.tryParse(parts[2]) ?? 0;
              return DateTime(yr, m, day).millisecondsSinceEpoch;
            } catch (_) { return 0; }
          }
          final sorted = List<Map<String, dynamic>>.from(afterStatusFilter);
          sorted.sort((a, b) {
            switch (widget.sortBy) {
              case 'date-asc':  return dateMs(a['date'] as String).compareTo(dateMs(b['date'] as String));
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
              default: return dateMs(b['date'] as String).compareTo(dateMs(a['date'] as String)); // date-desc newest first
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
    final plate = s['plate'] as String;
    // Look up vehicle description from live vehicles data (stays in sync with edits)
    final liveDesc = _vehicleMap[plate]?['desc'] as String? ?? s['desc'] as String;
    final displayDesc = liveDesc.isNotEmpty ? liveDesc : plate;
    return GestureDetector(
      onTap: () => _showServiceDetails(s),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)]),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s['date'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            Text(plate, style: const TextStyle(fontSize: 12, color: Color(0xFF4a5568))),
            Text(displayDesc, style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
            Text(s['mechanic'] as String, style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
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
    final plate = s['plate'] as String;
    // Look up vehicle description from live vehicles data (stays in sync with edits)
    final liveDesc = _vehicleMap[plate]?['desc'] as String? ?? s['desc'] as String;
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
                    Text(plate, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    Text(liveDesc, style: const TextStyle(color: Colors.white70, fontSize: 12)),
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
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              title: const Row(children: [
                                Icon(Icons.check_circle_outline, color: Colors.green, size: 22),
                                SizedBox(width: 8),
                                Text('Complete Service', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                              ]),
                              content: Text(
                                'Are you sure you want to mark service for "${s['plate']}" as Completed?',
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
                                    backgroundColor: Colors.green, foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  child: const Text('Yes, Complete'),
                                ),
                              ],
                            ),
                          );
                          if (confirm != true) return;
                          // 1. Update status immediately
                          await SyncStatusNotifier.instance.trackWrite(() => _db.doc(s['docId'] as String).update({'status': 'Completed'}));

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
                          // Update vehicle on completion — prefer vehicleId direct lookup
                          final mainDocForVeh = await _db.doc(s['docId'] as String).get();
                          final mainDataForVeh = mainDocForVeh.data() as Map<String, dynamic>? ?? {};
                          final completionVehicleId = mainDataForVeh['vehicleId'] as String? ?? '';
                          final completionDate = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
                          final vUpdate = <String, dynamic>{
                            'status': 'Completed',
                            'completedAt': FieldValue.serverTimestamp(),
                            // Canonical lastServiceDate + legacy lastSvcDate
                            'lastServiceDate': completionDate,
                            'lastSvcDate':     completionDate,
                          };
                          final odoReading = mainDataForVeh['odometer'];
                          if (odoReading != null) {
                            final odoInt = int.tryParse(odoReading.toString()) ?? 0;
                            if (odoInt > 0) {
                              vUpdate['lastServiceOdometer'] = odoInt;
                              vUpdate['lastSvcOdo']          = odoInt;
                              vUpdate['odometer']            = odoInt;
                              vUpdate['odo']                 = '$odoInt km';
                            }
                          }
                          if (completionVehicleId.isNotEmpty) {
                            await FirebaseFirestore.instance
                                .collection('vehicles')
                                .doc(completionVehicleId)
                                .update(vUpdate);
                          } else {
                            // Fallback: plate scan
                            var vSnap = await FirebaseFirestore.instance
                                .collection('vehicles')
                                .where('plateNumber', isEqualTo: plate)
                                .limit(1).get();
                            if (vSnap.docs.isEmpty) {
                              vSnap = await FirebaseFirestore.instance
                                  .collection('vehicles')
                                  .where('plate', isEqualTo: plate)
                                  .limit(1).get();
                            }
                            if (vSnap.docs.isNotEmpty) {
                              await vSnap.docs.first.reference.update(vUpdate);
                            }
                          }

                          // Also update linked service booking to "Completed" if exists
                          final bookingId = mainDataForVeh['bookingId'] as String?;
                          if (bookingId != null && bookingId.isNotEmpty) {
                            await FirebaseFirestore.instance.collection('service_bookings').doc(bookingId).update({'status': 'Completed'}).catchError((_) {});
                          }

                          // Notify customer — Completed
                          String customerUid = mainDataForVeh['ownerId'] as String? ?? '';
                          if (customerUid.isEmpty && bookingId != null && bookingId.isNotEmpty) {
                            final bDoc = await FirebaseFirestore.instance.collection('service_bookings').doc(bookingId).get();
                            customerUid = (bDoc.data()?['customerId'] as String?) ?? '';
                          }
                          if (customerUid.isEmpty) {
                            // Fallback: look up vehicle owner by plate
                            final plate2 = (s['plate'] as String).trim().toUpperCase();
                            var vFall = await FirebaseFirestore.instance.collection('vehicles').where('plateNumber', isEqualTo: plate2).limit(1).get();
                            if (vFall.docs.isEmpty) vFall = await FirebaseFirestore.instance.collection('vehicles').where('plate', isEqualTo: plate2).limit(1).get();
                            if (vFall.docs.isNotEmpty) customerUid = (vFall.docs.first.data()['ownerId'] as String?) ?? '';
                          }
                          if (customerUid.isNotEmpty) {
                            final alertSnap = await FirebaseFirestore.instance
                                .collection('users').doc(customerUid).collection('settings').doc('alerts').get();
                            final prefs = alertSnap.data() ?? {};
                            final inAppOn = prefs['vehicleUnderMaint'] != false;
                            if (inAppOn) {
                              await FirebaseFirestore.instance.collection('notifications').add({
                                'title': '✅ Service Completed',
                                'message': 'Your vehicle ${(s['plate'] as String).trim().toUpperCase()} has been serviced and is ready for pickup.',
                                'type': 'success',
                                'targetRole': '', 'targetUid': customerUid,
                                'createdAt': FieldValue.serverTimestamp(), 'readBy': <String, bool>{}, 'isRead': false,
                              });
                            }
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
          Text(uom.isNotEmpty ? '$name ($uom)' : name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          Text('$qty  -  $cost', style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
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
      // Query by item number (unique) to handle same-name different-UOM items correctly
      for (final row in matRows) {
        final name = row['name']!.text;
        if (name.isEmpty) continue;
        final uomVal = row['uom']!.text;
        final maxStockCtrl = row['maxStock']!;
        // Match name+uom in _allItems (preserves duplicates) for correct num lookup
        final matchedItem = _allItems.firstWhere(
          (e) => (e['name'] as String).toLowerCase() == name.toLowerCase()
              && (e['uom'] as String? ?? '').toLowerCase() == uomVal.toLowerCase(),
          orElse: () => _itemMasterMap[name] ?? {},
        );
        final itemNum = ((matchedItem['num'] ?? _itemMasterMap[name]?['num']) as String? ?? '').trim();
        final Future<QuerySnapshot> stockFuture;
        if (itemNum.isNotEmpty) {
          stockFuture = FirebaseFirestore.instance
              .collection('stock_inventory').where('num', isEqualTo: itemNum).limit(1).get();
        } else if (uomVal.isNotEmpty) {
          stockFuture = FirebaseFirestore.instance
              .collection('stock_inventory')
              .where('name', isEqualTo: name)
              .where('uom', isEqualTo: uomVal)
              .limit(1).get();
        } else {
          stockFuture = FirebaseFirestore.instance
              .collection('stock_inventory').where('name', isEqualTo: name).limit(1).get();
        }
        stockFuture.then((snap) {
          maxStockCtrl.text = snap.docs.isNotEmpty
              ? '${(snap.docs.first['stock'] as num?)?.toInt() ?? 0}'
              : '-1';
        }).catchError((_) {});
      }
    }

    bool saving = false;

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
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
            curve: Curves.easeOut,
            child: DraggableScrollableSheet(
            initialChildSize: 0.92,
            minChildSize: 0.5,
            maxChildSize: 1.0,
            expand: false,
            builder: (ctx2, scrollCtrl) => Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(children: [
                // ── Sticky header ──
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                  decoration: const BoxDecoration(
                    color: _red,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Row(children: [
                    const SizedBox(width: 12),
                    Expanded(child: Text(isEdit ? 'Edit Service' : 'New Service',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
                    GestureDetector(onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.close, color: Colors.white)),
                  ]),
                ),
                // ── Scrollable content ──
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollCtrl,
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
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
                        onPressed: saving ? null : () async {
                          if (plateCtrl.text.trim().isEmpty || mechanicCtrl.text.trim().isEmpty) return;
                          setModal(() => saving = true);
                          final odoValue = int.tryParse(odoCtrl.text.trim()) ?? 0;

                          // Validate material quantities using cached maxStock (already fetched when
                          // user selected the material — no extra network round-trip needed).
                          for (final r in matRows) {
                            final name = r['name']!.text.trim();
                            final qty = int.tryParse(r['qty']!.text.trim()) ?? 0;
                            if (name.isEmpty || qty <= 0) continue;
                            final available = int.tryParse(r['maxStock']?.text ?? '99999') ?? 99999;
                            if (available >= 0 && available < 99999 && qty > available) {
                              setModal(() => saving = false);
                              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text('Insufficient stock for "$name". Available: $available, Requested: $qty'),
                                backgroundColor: Colors.orange, behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
                              return;
                            }
                          }

                          // Duplicate plate check — cache only, no server fallback (keeps save instant).
                          if (!isEdit) {
                            final plateUpper = plateCtrl.text.trim().toUpperCase();
                            bool hasDuplicate = false;
                            try {
                              final dupCheck = await _db
                                  .where('plate', isEqualTo: plateUpper)
                                  .where('status', whereIn: ['Ongoing'])
                                  .limit(1)
                                  .get(const GetOptions(source: Source.cache));
                              hasDuplicate = dupCheck.docs.isNotEmpty;
                            } catch (_) { /* cache miss — skip duplicate check */ }
                            if (hasDuplicate) {
                              setModal(() => saving = false);
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

                          final svcId      = isEdit ? service['id'] as String : await _nextSvcId();
                          final plateUpper = plateCtrl.text.trim().toUpperCase();

                          // ── Resolve vehicleId + ownerId from the vehicle ──
                          // The staff selects a plate; we derive the authoritative
                          // vehicleId and ownerId from the vehicle document so they
                          // are NEVER entered manually.
                          String resolvedVehicleId = '';
                          String resolvedOwnerId   = '';

                          if (isEdit) {
                            // Preserve existing links on edit if already set
                            resolvedVehicleId = (service['vehicleId'] as String? ?? '').trim();
                            resolvedOwnerId   = (service['ownerId']   as String? ?? '').trim();
                          }

                          // Always try to look up from the vehicle document
                          // (covers new records AND edits where links were missing)
                          try {
                            // Try canonical plateNumber first, then legacy plate
                            var vSnap = await FirebaseFirestore.instance
                                .collection('vehicles')
                                .where('plateNumber', isEqualTo: plateUpper)
                                .limit(1).get();
                            if (vSnap.docs.isEmpty) {
                              vSnap = await FirebaseFirestore.instance
                                  .collection('vehicles')
                                  .where('plate', isEqualTo: plateUpper)
                                  .limit(1).get();
                            }
                            if (vSnap.docs.isNotEmpty) {
                              final vDoc  = vSnap.docs.first;
                              final vData = vDoc.data() as Map<String, dynamic>;
                              resolvedVehicleId = vDoc.id;
                              // ownerId is authoritative from the vehicle — never
                              // trust a client-supplied value over the vehicle's own
                              final vehicleOwnerId = (vData['ownerId'] as String? ?? '').trim();
                              if (vehicleOwnerId.isNotEmpty) {
                                resolvedOwnerId = vehicleOwnerId;
                              }
                            }
                          } catch (_) {
                            // Non-fatal — migration script fills gaps later.
                          }

                          final data = <String, dynamic>{
                            'id':       svcId,
                            // ── Relational keys (authoritative) ─────────────
                            if (resolvedVehicleId.isNotEmpty) 'vehicleId': resolvedVehicleId,
                            if (resolvedOwnerId.isNotEmpty)   'ownerId':   resolvedOwnerId,
                            // ── Plate (display / historical snapshot) ───────
                            'plateNumber': plateUpper,
                            'plate':       plateUpper,   // legacy alias
                            // ── Rest of record ───────────────────────────────
                            'desc':     foundVehicle?['desc'] as String? ?? '',
                            'mechanic': mechanicCtrl.text.trim(),
                            'date':     dateCtrl.text.trim(),
                            'odometer': odoValue,
                            'cost':     _fmtMoney(totalCost()),
                            'status':   isEdit ? service['status'] as String : 'Ongoing',
                            'issues':   selectedIssues,
                            'svcRows':  svcRows.map((r) => {'name': r['name']!.text, 'qty': r['qty']!.text, 'uom': r['uom']!.text, 'cost': r['cost']!.text}).toList(),
                            'matRows':  matRows.map((r) => {'name': r['name']!.text, 'qty': r['qty']!.text, 'uom': r['uom']!.text, 'cost': r['cost']!.text}).toList(),
                            if (bookingId != null && bookingId.isNotEmpty) 'bookingId': bookingId,
                          };
                          try {
                            if (isEdit) {
                              // 1. Write the main record
                              await SyncStatusNotifier.instance.trackWrite(
                                () => _db.doc(service['docId'] as String).update(data));

                              // 2. Close modal + show success immediately
                              if (context.mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Row(children: const [Icon(Icons.check_circle_outline, color: Colors.white, size: 18), SizedBox(width: 8), Text('Updated successfully!')]),
                                  backgroundColor: Colors.green, behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
                              }

                              // 3. Odometer update runs in background (non-blocking)
                              _updateVehicleOdometer(plateUpper, odoValue);
                            } else {
                              data['createdAt'] = FieldValue.serverTimestamp();

                              // 1. Write the main record
                              await SyncStatusNotifier.instance.trackWrite(() => _db.add(data));

                              // 2. Close modal + show success immediately
                              if (context.mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Row(children: const [Icon(Icons.check_circle_outline, color: Colors.white, size: 18), SizedBox(width: 8), Text('Added successfully!')]),
                                  backgroundColor: Colors.green, behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
                              }

                              // 3. Odometer + vehicle status update in background (non-blocking)
                              () async {
                                _updateVehicleOdometer(plateUpper, odoValue);
                                // Use vehicleId directly if we resolved it
                                if (resolvedVehicleId.isNotEmpty) {
                                  await FirebaseFirestore.instance
                                      .collection('vehicles')
                                      .doc(resolvedVehicleId)
                                      .update({'status': 'Under Maintenance'});
                                } else {
                                  // Fallback: look up by plate
                                  final pSnap = await FirebaseFirestore.instance
                                      .collection('vehicles')
                                      .where('plate', isEqualTo: plateUpper)
                                      .limit(1).get();
                                  if (pSnap.docs.isNotEmpty) {
                                    await pSnap.docs.first.reference.update({'status': 'Under Maintenance'});
                                  }
                                }
                                // Notify customer — Under Maintenance
                                String maintCustomerUid = resolvedOwnerId;
                                if (maintCustomerUid.isEmpty && bookingId != null && bookingId.isNotEmpty) {
                                  final bDoc = await FirebaseFirestore.instance.collection('service_bookings').doc(bookingId).get();
                                  maintCustomerUid = (bDoc.data()?['customerId'] as String?) ?? '';
                                }
                                if (maintCustomerUid.isNotEmpty) {
                                  final alertSnap = await FirebaseFirestore.instance
                                      .collection('users').doc(maintCustomerUid).collection('settings').doc('alerts').get();
                                  final prefs = alertSnap.data() ?? {};
                                  final inAppOn = prefs['vehicleUnderMaint'] != false;
                                  if (inAppOn) {
                                    await FirebaseFirestore.instance.collection('notifications').add({
                                      'title': '🔧 Vehicle Under Maintenance',
                                      'message': 'Your vehicle $plateUpper is now under maintenance. We will notify you once the service is completed.',
                                      'type': 'info',
                                      'targetRole': '', 'targetUid': maintCustomerUid,
                                      'createdAt': FieldValue.serverTimestamp(), 'readBy': <String, bool>{}, 'isRead': false,
                                    });
                                  }
                                }
                              }();
                            }
                          } catch (e) {
                            setModal(() => saving = false);
                            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                          }
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white),
                        child: saving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(isEdit ? 'Update' : 'Save'),
                      )),
                    ]),         // Row([Cancel, Save])
                  ]),           // Column children end
                  ),          // SingleChildScrollView
                ),            // Expanded
              ]),             // Column([header, Expanded])
            ),                // Container
            ),                // DraggableScrollableSheet
          );                  // AnimatedPadding
        },
      ),
    );
  }

  Widget _svcRow(Map<String, TextEditingController> row, VoidCallback onRemove, StateSetter setModal, List<Map<String, TextEditingController>> allSvcRows, BuildContext ctx) {
    row.putIfAbsent('searchText', () => TextEditingController(text: row['name']!.text));
    final svcFieldKey = _rowKeys.putIfAbsent(identityHashCode(row), () => GlobalKey());

    // All service items preserving same-name different-UOM entries
    final serviceItems = _allItems
        .where((e) => (e['type'] as String? ?? '').toLowerCase() == 'service')
        .toList()
      ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

    Future<void> applyService(String name, String uom) async {
      final alreadyUsed = allSvcRows.any((r) => r != row && r['name']!.text == name && r['uom']!.text == uom);
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
      row['uom']!.text = uom.isNotEmpty ? uom : ((_itemMasterMap[name]?['uom']) ?? 'job').toString();
      row['cost']!.text = ((_itemMasterMap[name]?['cost']) ?? '0').toString().replaceAll('₱', '').replaceAll(',', '').trim();
      if (row['qty']!.text.isEmpty) row['qty']!.text = '1';
      setModal(() {});
    }

    final isSelected = row['name']!.text.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
            : _ItemSearchField(
                key: svcFieldKey,
                controller: row['searchText']!,
                label: 'Service Name *',
                items: serviceItems,
                filter: (item, q) {
                  final n = (item['name'] as String).toLowerCase();
                  final num = (item['num'] as String? ?? '').toLowerCase();
                  return n.contains(q) || num.contains(q);
                },
                isOutOfStock: (_) => false,
                onSelected: (item) => applyService(item['name'] as String, item['uom'] as String? ?? ''),
                onChanged: () => setModal(() {}),
              ),
        ),
        SizedBox(width: 32, child: IconButton(icon: const Icon(Icons.close, size: 16, color: Colors.red), padding: EdgeInsets.zero, onPressed: onRemove)),
      ]),
    );
  }

  Widget _matRow(Map<String, TextEditingController> row, VoidCallback onRemove, StateSetter setModal, BuildContext ctx, List<Map<String, TextEditingController>> allMatRows) {
    row.putIfAbsent('maxStock', () => TextEditingController(text: '99999'));
    row.putIfAbsent('searchText', () => TextEditingController());
    final matFieldKey = _rowKeys.putIfAbsent(identityHashCode(row) + 1, () => GlobalKey());

    // All material items from item master (type == Material), excluding Inactive stock items
    // Use _allItems to preserve items with same name but different UOM
    final materialItems = _allItems
        .where((e) => (e['type'] as String? ?? '').toLowerCase() == 'material')
        .where((e) => !_inactiveItemNames.contains((e['name'] as String).toLowerCase()))
        .toList()
      ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

    Future<void> applyMaterial(String name, String uom) async {
      // Block items marked Inactive or with zero stock
      final nameKey = name.toLowerCase();
      final isInactive = _inactiveItemNames.contains(nameKey);
      final stockQty = _stockMap[nameKey];
      final isZeroStock = stockQty != null && stockQty == 0;
      if (isInactive || isZeroStock) {
        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
          content: Text('⚠ This item is out of stock and cannot be added.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }
      final alreadyUsed = allMatRows.any((r) => r != row && r['name']!.text == name && r['uom']!.text == uom);
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
      row['uom']!.text = uom.isNotEmpty ? uom : (d['uom'] ?? '').toString();
      final rawCost = d['cost'];
      row['cost']!.text = rawCost == null
          ? '0'
          : rawCost.toString().replaceAll('₱', '').replaceAll(',', '').trim();
      if (row['qty']!.text.isEmpty) row['qty']!.text = '1';
      // Look up stock by item number — match name+uom from _allItems (which preserves duplicates)
      // so same-name different-UOM items get the correct distinct stock record
      final uomForLookup = uom.isNotEmpty ? uom : (d['uom'] ?? '').toString();
      final matchedItem = _allItems.firstWhere(
        (e) => (e['name'] as String).toLowerCase() == name.toLowerCase()
            && (e['uom'] as String? ?? '').toLowerCase() == uomForLookup.toLowerCase(),
        orElse: () => d,
      );
      final itemNum = ((matchedItem['num'] ?? d['num']) as String? ?? '').trim();
      final QuerySnapshot stockSnap;
      if (itemNum.isNotEmpty) {
        stockSnap = await FirebaseFirestore.instance
            .collection('stock_inventory').where('num', isEqualTo: itemNum).limit(1).get();
      } else {
        // Fallback: query by name + uom together
        stockSnap = await FirebaseFirestore.instance
            .collection('stock_inventory')
            .where('name', isEqualTo: name)
            .where('uom', isEqualTo: uomForLookup)
            .limit(1).get();
      }
      final available = stockSnap.docs.isNotEmpty
          ? (stockSnap.docs.first['stock'] as num?)?.toInt() ?? 0
          : -1;
      // Block if actual stock is 0 (covers Low-status items with 0 qty)
      if (available == 0) {
        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
          content: Text('⚠ This item is out of stock and cannot be added.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }
      row['maxStock']!.text = '$available';
      final currentQty = int.tryParse(row['qty']!.text) ?? 1;
      if (available >= 0 && currentQty > available) row['qty']!.text = '$available';
      setModal(() {});
    }

    final maxStock = int.tryParse(row['maxStock']!.text) ?? 99999;
    final isSelected = row['name']!.text.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                        ? [FilteringTextInputFormatter.digitsOnly, _MaxValueFormatter(maxStock)]
                        : [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setModal(() {}),
                    decoration: InputDecoration(
                      labelText: 'Quantity *',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      isDense: true,
                      errorText: maxStock == 0 ? 'Out of stock' : null,
                    ),
                  ),
                ]),
              )
            : _ItemSearchField(
                key: matFieldKey,
                controller: row['searchText']!,
                label: 'Material Name *',
                items: materialItems,
                filter: (item, q) {
                  final n = (item['name'] as String).toLowerCase();
                  final num = (item['num'] as String? ?? '').toLowerCase();
                  final sc = (item['supplierCode'] as String? ?? '').toLowerCase();
                  return n.contains(q) || num.contains(q) || sc.contains(q);
                },
                isOutOfStock: (item) {
                  final n = (item['name'] as String).toLowerCase();
                  return (_stockMap[n] ?? -1) == 0 || _inactiveItemNames.contains(n);
                },
                onSelected: (item) => applyMaterial(item['name'] as String, item['uom'] as String? ?? ''),
                onChanged: () => setModal(() {}),
                trailing: IconButton(
                  icon: const Icon(Icons.qr_code_scanner, size: 18, color: Color(0xFF003087)),
                  padding: EdgeInsets.zero,
                  onPressed: () async {
                    final result = await Navigator.push<String>(ctx,
                      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()));
                    if (result != null) {
                      final match = _allItems.firstWhere(
                        (e) => e['barcode'] == result || e['qr'] == result,
                        orElse: () => {},
                      );
                      if ((match['name'] as String? ?? '').isNotEmpty) {
                        applyMaterial(match['name'] as String, match['uom'] as String? ?? '');
                      }
                    }
                  },
                ),
              ),
        ),
        SizedBox(width: 32, child: IconButton(
          icon: const Icon(Icons.close, size: 16, color: Colors.red),
          padding: EdgeInsets.zero,
          onPressed: onRemove,
        )),
      ]),
    );
  }

  /// Updates the vehicle's odometer fields in Firestore immediately when a
  /// maintenance record is saved, so the odo column stays current.
  /// Prefers vehicleId direct lookup; falls back to plate-based scan.
  Future<void> _updateVehicleOdometer(String plate, int odoValue) async {
    if (plate.isEmpty || odoValue <= 0) return;
    try {
      // Prefer direct doc update via cached vehicleId from _vehicleMap
      final vehicleEntry = _vehicleMap[plate.toUpperCase()];
      final vehicleDocId = vehicleEntry?['_docId'] as String? ?? '';
      if (vehicleDocId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('vehicles')
            .doc(vehicleDocId)
            .update({'odometer': odoValue, 'odo': '$odoValue km'});
        return;
      }
      // Fallback: query by plateNumber (canonical) then plate (legacy)
      var vSnap = await FirebaseFirestore.instance
          .collection('vehicles')
          .where('plateNumber', isEqualTo: plate.toUpperCase())
          .limit(1)
          .get();
      if (vSnap.docs.isEmpty) {
        vSnap = await FirebaseFirestore.instance
            .collection('vehicles')
            .where('plate', isEqualTo: plate.toUpperCase())
            .limit(1)
            .get();
      }
      if (vSnap.docs.isNotEmpty) {
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


/// Search field with overlay dropdown that survives StatefulBuilder rebuilds.
/// Pass a stable [key] (stored on the row map) to keep State alive.
class _ItemSearchField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final List<Map<String, dynamic>> items;
  final bool Function(Map<String, dynamic>, String) filter;
  final bool Function(Map<String, dynamic>) isOutOfStock;
  final void Function(Map<String, dynamic>) onSelected;
  final Widget? trailing;
  final VoidCallback? onChanged;

  const _ItemSearchField({
    required super.key,
    required this.controller,
    required this.label,
    required this.items,
    required this.filter,
    required this.isOutOfStock,
    required this.onSelected,
    this.trailing,
    this.onChanged,
  });

  @override
  State<_ItemSearchField> createState() => _ItemSearchFieldState();
}

class _ItemSearchFieldState extends State<_ItemSearchField> {
  final _layerLink = LayerLink();
  final _focusNode = FocusNode();
  OverlayEntry? _overlay;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_rebuild);
    _focusNode.addListener(_onFocus);
  }

  @override
  void dispose() {
    _close();
    widget.controller.removeListener(_rebuild);
    _focusNode.removeListener(_onFocus);
    _focusNode.dispose();
    super.dispose();
  }

  void _rebuild() {
    widget.onChanged?.call();
    if (_focusNode.hasFocus) _open();
  }

  void _onFocus() {
    if (_focusNode.hasFocus) {
      _open();
    } else {
      Future.delayed(const Duration(milliseconds: 180), _close);
    }
  }

  List<Map<String, dynamic>> get _results {
    final q = widget.controller.text.trim().toLowerCase();
    if (q.isEmpty) return [];
    return widget.items.where((e) => widget.filter(e, q)).take(8).toList();
  }

  void _open() {
    _close();
    final results = _results;
    final q = widget.controller.text.trim();
    if (results.isEmpty && q.isEmpty) return;
    final overlay = Overlay.of(context);
    _overlay = OverlayEntry(builder: (_) => _buildOverlay(results));
    overlay.insert(_overlay!);
  }

  void _close() {
    _overlay?.remove();
    _overlay?.dispose();
    _overlay = null;
  }

  Widget _buildOverlay(List<Map<String, dynamic>> results) {
    final mq = MediaQuery.of(context);
    final w = mq.size.width - 48;
    return Positioned(
      width: 0,
      child: CompositedTransformFollower(
        link: _layerLink,
        showWhenUnlinked: false,
        offset: const Offset(0, 46),
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: w, maxHeight: 260),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: results.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    child: Text(
                      widget.label.contains('Service') ? 'No services found.' : 'No materials found.',
                      style: const TextStyle(fontSize: 12, color: Color(0xFFa0aec0)),
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: results.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFe2e8f0)),
                    itemBuilder: (_, i) {
                      final item = results[i];
                      final name = item['name'] as String;
                      final uom = item['uom'] as String? ?? '';
                      final rawCost = item['cost'];
                      final cost = rawCost == null ? 0.0
                          : double.tryParse(rawCost.toString().replaceAll('₱','').replaceAll(',','').trim()) ?? 0.0;
                      final oos = widget.isOutOfStock(item);
                      return InkWell(
                        onTap: oos ? null : () {
                          _close();
                          _focusNode.unfocus();
                          widget.onSelected(item);
                        },
                        child: Container(
                          color: oos ? const Color(0xFFF8F8F8) : null,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Row(children: [
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(name, style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13,
                                color: oos ? const Color(0xFFa0aec0) : const Color(0xFF1a202c))),
                              if (uom.isNotEmpty || cost > 0)
                                Text('${uom.isNotEmpty ? uom : '—'}  •  ₱${cost.toStringAsFixed(2)}',
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
                              if (oos)
                                Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFF5F5),
                                      borderRadius: BorderRadius.circular(20)),
                                    child: const Text('⚠ Out of stock — cannot add',
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.red)),
                                  ),
                                ),
                            ])),
                            oos
                              ? const Icon(Icons.block_outlined, size: 16, color: Color(0xFFa0aec0))
                              : const Icon(Icons.add_circle_outline, size: 16, color: Color(0xFF718096)),
                          ]),
                        ),
                      );
                    },
                  ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        decoration: InputDecoration(
          labelText: widget.label,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          isDense: true,
          prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF718096)),
          suffixIcon: widget.trailing,
        ),
      ),
    );
  }
}
