import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'staff_maintenance.dart';
import 'staff_service_bookings.dart';
import 'sync_indicator.dart';
import 'staff_bottomnavbar.dart';
import 'staff_inventory.dart';
import 'profile.dart';
import 'barcode_scanner_screen.dart';

class StaffVehicleList extends StatefulWidget {
  const StaffVehicleList({super.key});

  @override
  State<StaffVehicleList> createState() => _StaffVehicleListState();
}

class _StaffVehicleListState extends State<StaffVehicleList> {
  static const _red = Color(0xFFE8001C);
  static const _col = 'vehicles';

  int _tab = 0; // 0 = Vehicles, 1 = Maintenance, 2 = Bookings
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  bool _searching = false;
  String _typeFilter = 'all';
  List<String>? _cachedTypes;
  final _maintBodyKey = GlobalKey<StaffMaintenanceBodyState>();
  String _maintSortBy = 'date-desc';
  String _vehicleSortBy = 'plate-asc';

  PopupMenuItem<String> _sortItem(
    String val,
    String label,
    IconData icon,
    String activeSortBy,
  ) {
    final active = activeSortBy == val;
    return PopupMenuItem(
      value: val,
      child: Row(
        children: [
          Icon(icon, size: 16, color: active ? _red : const Color(0xFF718096)),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontWeight: active ? FontWeight.w700 : FontWeight.normal,
              color: active ? _red : const Color(0xFF1a202c),
            ),
          ),
          if (active) ...[
            const Spacer(),
            const Icon(Icons.check, size: 14, color: _red),
          ],
        ],
      ),
    );
  }

  CollectionReference get _db => FirebaseFirestore.instance.collection(_col);

  Future<List<String>> _fetchVehicleTypes() async {
    if (_cachedTypes != null) return _cachedTypes!;
    final snap = await FirebaseFirestore.instance
        .collection('domains')
        .doc('vehicle_types')
        .collection('items')
        .orderBy('name')
        .get();
    _cachedTypes = snap.docs.map((d) => d['name'] as String).toList();
    return _cachedTypes!;
  }

  String _computeStatus(String lastSvcDate, String svcFreq) {
    if (lastSvcDate.isEmpty || svcFreq.isEmpty) return 'Active';
    final date = DateTime.tryParse(lastSvcDate);
    final months = int.tryParse(svcFreq);
    if (date == null || months == null) return 'Active';
    final nextPms = DateTime(date.year, date.month + months, date.day);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final nextMidnight = DateTime(nextPms.year, nextPms.month, nextPms.day);
    final daysUntil = nextMidnight.difference(today).inDays;
    if (daysUntil < 0) return 'Overdue';
    if (daysUntil <= 30) return 'PMS Due Soon';
    return 'Active';
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Active':
        return Colors.green;
      case 'Under Maintenance':
        return Colors.orange;
      case 'Overdue':
        return _red;
      case 'PMS Due Soon':
        return Colors.amber.shade700;
      case 'Completed':
        return const Color(0xFF003087);
      default:
        return Colors.grey;
    }
  }

  String _calcNextPms(String lastSvcDate, String svcFreq) {
    if (lastSvcDate.isEmpty || svcFreq.isEmpty) return '—';
    final date = DateTime.tryParse(lastSvcDate);
    final months = int.tryParse(svcFreq);
    if (date == null || months == null) return '—';
    final next = DateTime(date.year, date.month + months, date.day);
    return '${next.year}-${next.month.toString().padLeft(2, '0')}-${next.day.toString().padLeft(2, '0')}';
  }

  static const _monthsFull = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  String _fmtDate(String dateStr) {
    if (dateStr.isEmpty || dateStr == '—') return '—';
    final d = DateTime.tryParse(dateStr);
    if (d == null) return dateStr;
    return '${_monthsFull[d.month - 1]} ${d.day}, ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      floatingActionButton: _tab == 0
          ? FloatingActionButton(
              onPressed: () => _showAddVehicleModal(),
              backgroundColor: _red,
              child: const Icon(Icons.add, color: Colors.white, size: 28),
            )
          : _tab == 1
          ? FloatingActionButton(
              onPressed: () => _maintBodyKey.currentState?.triggerAdd(),
              backgroundColor: _red,
              child: const Icon(Icons.add, color: Colors.white, size: 28),
            )
          : null,
      appBar: AppBar(
        backgroundColor: const Color(0xFF004B5F),
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF004B5F), Color(0xFFEE152A)],
              stops: [0.0, 1.0],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        title: _searching
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                onChanged: (v) =>
                    setState(() => _searchQuery = v.toLowerCase()),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: _tab == 0
                      ? 'Search vehicles...'
                      : _tab == 1
                      ? 'Search services...'
                      : 'Search bookings...',
                  hintStyle: const TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                ),
              )
            : Text(
                _tab == 0
                    ? 'Vehicle List'
                    : _tab == 1
                    ? 'Vehicle Maintenance'
                    : 'Service Bookings',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
        actions: [
          const SyncIndicator(),
          IconButton(
            icon: Icon(
              _searching ? Icons.close : Icons.search,
              color: Colors.white,
            ),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) {
                _searchCtrl.clear();
                _searchQuery = '';
              }
            }),
          ),
          if (_tab == 0 && !_searching)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onSelected: (val) => setState(() => _vehicleSortBy = val),
              itemBuilder: (_) => [
                const PopupMenuItem(
                  enabled: false,
                  child: Text(
                    'Sort By',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF718096),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _sortItem(
                  'plate-asc',
                  'Plate A→Z',
                  Icons.sort_by_alpha,
                  _vehicleSortBy,
                ),
                _sortItem(
                  'plate-desc',
                  'Plate Z→A',
                  Icons.sort_by_alpha,
                  _vehicleSortBy,
                ),
                _sortItem(
                  'owner-asc',
                  'Owner A→Z',
                  Icons.person_outline,
                  _vehicleSortBy,
                ),
                _sortItem(
                  'owner-desc',
                  'Owner Z→A',
                  Icons.person_outline,
                  _vehicleSortBy,
                ),
                _sortItem(
                  'pms-asc',
                  'Next PMS ↑ Soonest',
                  Icons.event_outlined,
                  _vehicleSortBy,
                ),
                _sortItem(
                  'pms-desc',
                  'Next PMS ↓ Latest',
                  Icons.event_outlined,
                  _vehicleSortBy,
                ),
                _sortItem(
                  'odo-desc',
                  'Odometer ↑ Highest',
                  Icons.trending_up,
                  _vehicleSortBy,
                ),
                _sortItem(
                  'odo-asc',
                  'Odometer ↓ Lowest',
                  Icons.trending_down,
                  _vehicleSortBy,
                ),
              ],
            ),
          if (_tab == 1 && !_searching)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onSelected: (val) => setState(() => _maintSortBy = val),
              itemBuilder: (_) => [
                const PopupMenuItem(
                  enabled: false,
                  child: Text(
                    'Sort By',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF718096),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _sortItem(
                  'date-desc',
                  'Date ↓ Newest',
                  Icons.arrow_downward,
                  _maintSortBy,
                ),
                _sortItem(
                  'date-asc',
                  'Date ↑ Oldest',
                  Icons.arrow_upward,
                  _maintSortBy,
                ),
                _sortItem(
                  'plate-asc',
                  'Plate A→Z',
                  Icons.sort_by_alpha,
                  _maintSortBy,
                ),
                _sortItem(
                  'plate-desc',
                  'Plate Z→A',
                  Icons.sort_by_alpha,
                  _maintSortBy,
                ),
                _sortItem(
                  'mechanic-asc',
                  'Mechanic A→Z',
                  Icons.person_outline,
                  _maintSortBy,
                ),
                _sortItem(
                  'cost-desc',
                  'Cost ↑ Highest',
                  Icons.trending_up,
                  _maintSortBy,
                ),
                _sortItem(
                  'cost-asc',
                  'Cost ↓ Lowest',
                  Icons.trending_down,
                  _maintSortBy,
                ),
              ],
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Container(
            color: Colors.white,
            child: Row(
              children: [
                _tabBtn(0, 'Vehicles'),
                _tabBtn(1, 'Maintenance'),
                _tabBtn(2, 'Bookings'),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: StaffBottomNavBar(
        currentIndex: 2,
        onIndexChanged: (i) {
          if (i == 2) return;
          if (i == 0) {
            Navigator.pop(context);
          } else if (i == 1) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const StaffInventory()),
            );
          } else if (i == 3) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => const UserProfile(role: UserRole.staff),
              ),
            );
          }
        },
        onScanPressed: () async {
          await Navigator.push<String>(
            context,
            MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
          );
        },
      ),
      body: OfflineSaveListener(
        child: IndexedStack(
          index: _tab,
          children: [
            _buildVehiclesBody(),
            StaffMaintenanceBody(
              key: _maintBodyKey,
              searchQuery: _tab == 1 && _searching ? _searchQuery : '',
              sortBy: _maintSortBy,
            ),
            StaffServiceBookingsBody(
              searchQuery: _tab == 2 && _searching ? _searchQuery : '',
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabBtn(int i, String label) {
    final active = _tab == i;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _tab = i;
          _searching = false;
          _searchCtrl.clear();
          _searchQuery = '';
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active ? _red : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: active ? FontWeight.w700 : FontWeight.normal,
              color: active ? _red : const Color(0xFF718096),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVehiclesBody() {
    return StreamBuilder<QuerySnapshot>(
      stream: _db.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 40),
                const SizedBox(height: 8),
                Text(
                  'Error: ${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ],
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        final vehicles = docs.map((d) {
          final data = d.data() as Map<String, dynamic>;
          return {
            'id': d.id,
            'plate': data['plate']?.toString() ?? '',
            'desc': data['desc']?.toString() ?? '',
            'owner': data['owner']?.toString() ?? '',
            'odo': data['odo']?.toString() ?? '',
            'type': data['type']?.toString() ?? '',
            'status': data['status']?.toString() ?? 'Active',
            'lastSvcOdo': data['lastSvcOdo']?.toString() ?? '',
            'lastSvcDate': data['lastSvcDate']?.toString() ?? '',
            'svcFreq': data['svcFreq']?.toString() ?? '',
          };
        }).toList();

        // Apply sort
        vehicles.sort((a, b) {
          switch (_vehicleSortBy) {
            case 'plate-desc':
              return (b['plate'] as String).compareTo(a['plate'] as String);
            case 'owner-asc':
              return (a['owner'] as String).compareTo(b['owner'] as String);
            case 'owner-desc':
              return (b['owner'] as String).compareTo(a['owner'] as String);
            case 'pms-asc':
            case 'pms-desc':
              {
                String pms(Map<String, String> v) {
                  final d = v['lastSvcDate'] ?? '';
                  final f = v['svcFreq'] ?? '';
                  if (d.isEmpty || f.isEmpty) return '9999-99-99';
                  final dt = DateTime.tryParse(d);
                  final m = int.tryParse(f);
                  if (dt == null || m == null) return '9999-99-99';
                  final next = DateTime(dt.year, dt.month + m, dt.day);
                  return '${next.year}-${next.month.toString().padLeft(2, '0')}-${next.day.toString().padLeft(2, '0')}';
                }

                final cmp = pms(a).compareTo(pms(b));
                return _vehicleSortBy == 'pms-asc' ? cmp : -cmp;
              }
            case 'odo-asc':
              final oa =
                  int.tryParse(
                    (a['odo'] as String).replaceAll(RegExp(r'[^0-9]'), ''),
                  ) ??
                  0;
              final ob =
                  int.tryParse(
                    (b['odo'] as String).replaceAll(RegExp(r'[^0-9]'), ''),
                  ) ??
                  0;
              return oa.compareTo(ob);
            case 'odo-desc':
              final oa2 =
                  int.tryParse(
                    (a['odo'] as String).replaceAll(RegExp(r'[^0-9]'), ''),
                  ) ??
                  0;
              final ob2 =
                  int.tryParse(
                    (b['odo'] as String).replaceAll(RegExp(r'[^0-9]'), ''),
                  ) ??
                  0;
              return ob2.compareTo(oa2);
            default:
              return (a['plate'] as String).compareTo(
                b['plate'] as String,
              ); // plate-asc
          }
        });

        final filtered = _searchQuery.isEmpty
            ? vehicles
            : vehicles
                  .where(
                    (v) =>
                        v['plate']!.toLowerCase().contains(_searchQuery) ||
                        v['desc']!.toLowerCase().contains(_searchQuery) ||
                        v['owner']!.toLowerCase().contains(_searchQuery),
                  )
                  .toList();

        final afterTypeFilter = _typeFilter == 'all'
            ? filtered
            : filtered
                  .where((v) => (v['type'] ?? '').toLowerCase() == _typeFilter)
                  .toList();

        final good = vehicles.where((v) => v['status'] == 'Active').length;
        final maint = vehicles
            .where((v) => v['status'] == 'Under Maintenance')
            .length;
        final overdue = vehicles.where((v) => v['status'] == 'Overdue').length;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  _statChip(
                    'Total',
                    '${vehicles.length}',
                    const Color(0xFF2563EB),
                    Icons.directions_car_outlined,
                    'all',
                  ),
                  const SizedBox(width: 8),
                  _statChip(
                    'Cars',
                    '${vehicles.where((v) => (v['type'] ?? '').toLowerCase() == 'car').length}',
                    const Color(0xFF003087),
                    Icons.directions_car_outlined,
                    'car',
                  ),
                  const SizedBox(width: 8),
                  _statChip(
                    'Trucks',
                    '${vehicles.where((v) => (v['type'] ?? '').toLowerCase() == 'truck').length}',
                    _red,
                    Icons.local_shipping_outlined,
                    'truck',
                  ),
                ],
              ),
            ),
            Expanded(
              child: afterTypeFilter.isEmpty
                  ? const Center(
                      child: Text(
                        'No vehicles found.',
                        style: TextStyle(color: Color(0xFF718096)),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: afterTypeFilter.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _vehicleCard(afterTypeFilter[i]),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _statChip(
    String label,
    String value,
    Color color,
    IconData icon,
    String filter,
  ) {
    final isActive = _typeFilter == filter;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(
          () => _typeFilter = _typeFilter == filter ? 'all' : filter,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: isActive ? color.withOpacity(0.08) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isActive ? color : Colors.transparent,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6),
            ],
          ),
          child: Column(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                label,
                style: const TextStyle(fontSize: 9, color: Color(0xFF718096)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _vehicleCard(Map<String, String> v) {
    final isTruck = v['type']?.toLowerCase() == 'truck';
    return GestureDetector(
      onTap: () => _showVehicleDetails(v),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    v['plate']!,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    v['desc']!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF4a5568),
                    ),
                  ),
                  Text(
                    '${v['owner']} • ${v['odo']}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF718096),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: Color(0xFFa0aec0)),
          ],
        ),
      ),
    );
  }

  void _showVehicleDetails(Map<String, String> v) {
    final lastSvcOdo =
        int.tryParse(
          (v['lastSvcOdo'] ?? '').replaceAll(RegExp(r'[^0-9]'), ''),
        ) ??
        0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (_, ctrl) => Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              decoration: const BoxDecoration(
                color: _red,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          v['plate']!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          v['desc']!,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
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
              child: SingleChildScrollView(
                controller: ctrl,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _detailRow('Plate Number', v['plate']!),
                      _detailRow('Description', v['desc']!),
                      _detailRow('Vehicle Type', v['type']!),
                      _detailRow('Owner Name / Company Name', v['owner']!),
                      _detailRow(
                        'Current Odometer',
                        v['odo']!.isNotEmpty ? v['odo']! : '—',
                      ),
                      _detailRow(
                        'Last Service Date',
                        _fmtDate(v['lastSvcDate']!),
                      ),
                      _detailRow(
                        'Last Service Odometer',
                        lastSvcOdo > 0 ? '$lastSvcOdo km' : '—',
                      ),
                      _detailRow(
                        'Next PMS Due',
                        _fmtDate(
                          _calcNextPms(v['lastSvcDate']!, v['svcFreq']!),
                        ),
                      ),
                      _detailRow(
                        'Service Frequency',
                        v['svcFreq']!.isNotEmpty
                            ? '${v['svcFreq']} month(s)'
                            : '—',
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _showAddVehicleModal(vehicle: v);
                          },
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          label: const Text('Edit Vehicle'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
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
              value.isNotEmpty ? value : '—',
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
  }

  void _showAddVehicleModal({Map<String, String>? vehicle}) async {
    try {
      final isEdit = vehicle != null;
      final types = await _fetchVehicleTypes();
      if (!mounted) return;

      final plateCtrl = TextEditingController(text: vehicle?['plate'] ?? '');
      final descCtrl = TextEditingController(text: vehicle?['desc'] ?? '');
      final ownerCtrl = TextEditingController(text: vehicle?['owner'] ?? '');
      final odoCtrl = TextEditingController(
        text: vehicle?['odo']?.replaceAll(' km', '').replaceAll(',', '') ?? '',
      );
      final lastSvcOdoCtrl = TextEditingController(
        text: vehicle?['lastSvcOdo'] ?? '',
      );
      final lastSvcDateCtrl = TextEditingController(
        text: vehicle?['lastSvcDate'] ?? '',
      );
      final svcFreqCtrl = TextEditingController(
        text: vehicle?['svcFreq'] ?? '',
      );
      String? selectedType =
          (vehicle?['type']?.isNotEmpty == true &&
              types.contains(vehicle!['type']))
          ? vehicle['type']
          : null;
      bool saving = false;

      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (sheetCtx) => StatefulBuilder(
          builder: (sheetCtx, setModal) => AnimatedPadding(
            duration: const Duration(milliseconds: 150),
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            isEdit ? 'Edit Vehicle' : 'Add Vehicle',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(sheetCtx),
                          child: const Icon(Icons.close, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: plateCtrl,
                          textCapitalization: TextCapitalization.characters,
                          inputFormatters: [_PlateNumberFormatter()],
                          decoration: const InputDecoration(
                            labelText: 'Plate Number *',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: descCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Description *',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        // Vehicle Type — bottom sheet picker (same style as admin)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () async {
                            final picked = await showModalBottomSheet<String>(
                              context: sheetCtx,
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(20),
                                ),
                              ),
                              builder: (pickerCtx) => Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                                    child: Text(
                                      'Select Vehicle Type',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const Divider(height: 1),
                                  Flexible(
                                    child: ListView(
                                      shrinkWrap: true,
                                      children: types
                                          .map(
                                            (t) => ListTile(
                                              title: Text(t),
                                              trailing: selectedType == t
                                                  ? const Icon(
                                                      Icons.check,
                                                      color: Color(0xFFE8001C),
                                                    )
                                                  : null,
                                              onTap: () =>
                                                  Navigator.pop(pickerCtx, t),
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                ],
                              ),
                            );
                            if (picked != null)
                              setModal(() => selectedType = picked);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 15,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: const Color(0xFFbdbdbd),
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Vehicle Type *',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: const Color(0xFF666666),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        selectedType ?? 'Select type',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: selectedType != null
                                              ? const Color(0xFF1a202c)
                                              : const Color(0xFF9e9e9e),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.arrow_drop_down,
                                  color: Color(0xFF718096),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _OwnerAutocomplete(controller: ownerCtrl),
                        const SizedBox(height: 10),
                        TextField(
                          controller: odoCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Current Odometer (km)',
                            border: OutlineInputBorder(),
                            suffixText: 'km',
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: svcFreqCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Service Frequency (months)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        // ── Just Serviced Toggle ──
                        _JustServicedSection(
                          lastSvcDateCtrl: lastSvcDateCtrl,
                          lastSvcOdoCtrl: lastSvcOdoCtrl,
                          initialChecked:
                              isEdit &&
                              (lastSvcDateCtrl.text.isNotEmpty ||
                                  lastSvcOdoCtrl.text.isNotEmpty),
                          readOnly: isEdit,
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(sheetCtx),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: saving
                                    ? null
                                    : () async {
                                        if (plateCtrl.text.trim().isEmpty)
                                          return;
                                        setModal(() => saving = true);

                                        // ── Resolve ownerId from owner name ──────────────
                                        String? resolvedOwnerId;
                                        final ownerName = ownerCtrl.text.trim();
                                        if (ownerName.isNotEmpty) {
                                          try {
                                            var ownerSnap =
                                                await FirebaseFirestore.instance
                                                    .collection('users')
                                                    .where(
                                                      'name',
                                                      isEqualTo: ownerName,
                                                    )
                                                    .where(
                                                      'role',
                                                      isEqualTo: 'customer',
                                                    )
                                                    .limit(1)
                                                    .get();
                                            if (ownerSnap.docs.isEmpty) {
                                              ownerSnap =
                                                  await FirebaseFirestore
                                                      .instance
                                                      .collection('users')
                                                      .where(
                                                        'companyName',
                                                        isEqualTo: ownerName,
                                                      )
                                                      .where(
                                                        'role',
                                                        isEqualTo: 'customer',
                                                      )
                                                      .limit(1)
                                                      .get();
                                            }
                                            if (ownerSnap.docs.isNotEmpty) {
                                              resolvedOwnerId =
                                                  ownerSnap.docs.first.id;
                                            }
                                          } catch (_) {
                                            // Non-fatal — migration script covers it.
                                          }
                                        }

                                        final plateUpper = plateCtrl.text
                                            .trim()
                                            .toUpperCase();
                                        final lastSvcDate = lastSvcDateCtrl.text
                                            .trim();
                                        final svcFreqRaw = svcFreqCtrl.text
                                            .trim();
                                        final svcFreqInt = int.tryParse(
                                          svcFreqRaw,
                                        );
                                        final odoRaw = odoCtrl.text.trim();
                                        final odoInt = int.tryParse(odoRaw);
                                        final lastSvcOdoInt = int.tryParse(
                                          lastSvcOdoCtrl.text.trim().replaceAll(
                                            RegExp(r'[^0-9]'),
                                            '',
                                          ),
                                        );

                                        // Write BOTH canonical and legacy short names so
                                        // all existing app code paths continue to work.
                                        final data = <String, dynamic>{
                                          // ── Canonical ─────────────────────────────────
                                          'plateNumber': plateUpper,
                                          'description': descCtrl.text.trim(),
                                          'owner': ownerName,
                                          'odometer': odoInt ?? 0,
                                          'lastServiceDate': lastSvcDate,
                                          'lastServiceOdometer':
                                              lastSvcOdoInt ?? 0,
                                          'serviceFrequency': svcFreqInt ?? 0,
                                          'type': selectedType ?? '',
                                          // ── Legacy aliases ─────────────────────────────
                                          'plate': plateUpper,
                                          'desc': descCtrl.text.trim(),
                                          'odo': odoRaw.isNotEmpty
                                              ? '$odoRaw km'
                                              : '',
                                          'lastSvcDate': lastSvcDate,
                                          'lastSvcOdo': lastSvcOdoCtrl.text
                                              .trim(),
                                          'svcFreq': svcFreqRaw,
                                          // ── Status ──────────────────────────────────────
                                          if (!isEdit)
                                            'status': _computeStatus(
                                              lastSvcDate,
                                              svcFreqRaw,
                                            ),
                                          // ── ownerId (authoritative customer link) ──────
                                          if (resolvedOwnerId != null)
                                            'ownerId': resolvedOwnerId,
                                        };
                                        try {
                                          if (isEdit) {
                                            await SyncStatusNotifier.instance
                                                .trackWrite(
                                                  () => _db
                                                      .doc(vehicle!['id'])
                                                      .update(data),
                                                );
                                            if (sheetCtx.mounted) {
                                              Navigator.pop(sheetCtx);
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Row(
                                                    children: const [
                                                      Icon(
                                                        Icons
                                                            .check_circle_outline,
                                                        color: Colors.white,
                                                        size: 18,
                                                      ),
                                                      SizedBox(width: 8),
                                                      Text(
                                                        'Updated successfully!',
                                                      ),
                                                    ],
                                                  ),
                                                  backgroundColor: Colors.green,
                                                  behavior:
                                                      SnackBarBehavior.floating,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                  ),
                                                ),
                                              );
                                            }
                                          } else {
                                            // Check for duplicate plate (check both field names)
                                            final existingByPlate = await _db
                                                .where(
                                                  'plateNumber',
                                                  isEqualTo: plateUpper,
                                                )
                                                .limit(1)
                                                .get();
                                            final existingByLegacy =
                                                existingByPlate.docs.isEmpty
                                                ? await _db
                                                      .where(
                                                        'plate',
                                                        isEqualTo: plateUpper,
                                                      )
                                                      .limit(1)
                                                      .get()
                                                : existingByPlate;
                                            if (existingByLegacy
                                                .docs
                                                .isNotEmpty) {
                                              setModal(() => saving = false);
                                              if (sheetCtx.mounted)
                                                ScaffoldMessenger.of(
                                                  sheetCtx,
                                                ).showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                      'A vehicle with this plate number already exists.',
                                                    ),
                                                    backgroundColor:
                                                        Colors.orange,
                                                  ),
                                                );
                                              return;
                                            }
                                            data['createdAt'] =
                                                FieldValue.serverTimestamp();
                                            await SyncStatusNotifier.instance
                                                .trackWrite(
                                                  () => _db.add(data),
                                                );
                                            if (sheetCtx.mounted) {
                                              Navigator.pop(sheetCtx);
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Row(
                                                    children: const [
                                                      Icon(
                                                        Icons
                                                            .check_circle_outline,
                                                        color: Colors.white,
                                                        size: 18,
                                                      ),
                                                      SizedBox(width: 8),
                                                      Text(
                                                        'Added successfully!',
                                                      ),
                                                    ],
                                                  ),
                                                  backgroundColor: Colors.green,
                                                  behavior:
                                                      SnackBarBehavior.floating,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                  ),
                                                ),
                                              );
                                            }
                                          }
                                        } catch (e) {
                                          setModal(() => saving = false);
                                          if (sheetCtx.mounted)
                                            ScaffoldMessenger.of(
                                              sheetCtx,
                                            ).showSnackBar(
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
                                    : Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.save_outlined,
                                            size: 16,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(isEdit ? 'Update' : 'Save'),
                                        ],
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
    } catch (e) {
      print('Error opening modal: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}

class _OwnerAutocomplete extends StatefulWidget {
  final TextEditingController controller;
  const _OwnerAutocomplete({required this.controller});

  @override
  State<_OwnerAutocomplete> createState() => _OwnerAutocompleteState();
}

class _OwnerAutocompleteState extends State<_OwnerAutocomplete> {
  List<String> _allNames = [];
  List<String> _suggestions = [];
  OverlayEntry? _overlay;
  final _layerLink = LayerLink();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadAllNames();
    widget.controller.addListener(_onChanged);
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) _removeOverlay();
    });
  }

  Future<void> _loadAllNames() async {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'customer')
        .get();
    if (!mounted) return;
    final names = <String>{};
    for (final d in snap.docs) {
      final data = d.data() as Map<String, dynamic>;
      final name = data['name'] as String? ?? '';
      final company = data['companyName'] as String? ?? '';
      if (name.isNotEmpty) names.add(name);
      if (company.isNotEmpty) names.add(company);
    }
    _allNames = names.toList()..sort();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _focusNode.dispose();
    _removeOverlay();
    super.dispose();
  }

  void _onChanged() {
    final q = widget.controller.text.trim().toLowerCase();
    if (q.isEmpty) {
      _removeOverlay();
      return;
    }
    final matches = _allNames
        .where((n) => n.toLowerCase().contains(q))
        .take(6)
        .toList();
    setState(() => _suggestions = matches);
    if (matches.isEmpty) {
      _removeOverlay();
      return;
    }
    _showOverlay();
  }

  void _showOverlay() {
    _removeOverlay();
    _overlay = OverlayEntry(
      builder: (_) => Positioned(
        width: 300,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 58),
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: ListView.separated(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: _suggestions.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) => ListTile(
                  dense: true,
                  leading: const CircleAvatar(
                    radius: 14,
                    backgroundColor: Color(0xFFF0F4FF),
                    child: Icon(
                      Icons.person_outline,
                      size: 16,
                      color: Color(0xFF003087),
                    ),
                  ),
                  title: Text(
                    _suggestions[i],
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onTap: () {
                    widget.controller.text = _suggestions[i];
                    widget.controller.selection = TextSelection.collapsed(
                      offset: _suggestions[i].length,
                    );
                    _removeOverlay();
                    _focusNode.unfocus();
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlay!);
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        decoration: const InputDecoration(
          labelText: 'Owner Name or Company Name',
          border: OutlineInputBorder(),
          suffixIcon: Icon(
            Icons.person_search_outlined,
            size: 20,
            color: Color(0xFF718096),
          ),
        ),
      ),
    );
  }
}

/// "Vehicle was just serviced" section
class _JustServicedSection extends StatefulWidget {
  final TextEditingController lastSvcDateCtrl;
  final TextEditingController lastSvcOdoCtrl;
  final bool initialChecked;
  final bool readOnly;
  const _JustServicedSection({
    required this.lastSvcDateCtrl,
    required this.lastSvcOdoCtrl,
    this.initialChecked = false,
    this.readOnly = false,
  });

  @override
  State<_JustServicedSection> createState() => _JustServicedSectionState();
}

class _JustServicedSectionState extends State<_JustServicedSection> {
  late bool _checked;

  @override
  void initState() {
    super.initState();
    _checked = widget.initialChecked;
    if (_checked && widget.lastSvcDateCtrl.text.isEmpty) {
      final now = DateTime.now();
      widget.lastSvcDateCtrl.text =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: widget.readOnly
              ? null
              : () {
                  setState(() => _checked = !_checked);
                  if (_checked && widget.lastSvcDateCtrl.text.isEmpty) {
                    final now = DateTime.now();
                    widget.lastSvcDateCtrl.text =
                        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
                  }
                  if (!_checked) {
                    widget.lastSvcDateCtrl.clear();
                    widget.lastSvcOdoCtrl.clear();
                  }
                },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _checked ? const Color(0xFFF0FFF4) : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _checked
                    ? const Color(0xFF9ae6b4)
                    : const Color(0xFFe2e8f0),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _checked ? Icons.check_box : Icons.check_box_outline_blank,
                  color: _checked
                      ? const Color(0xFF16a34a)
                      : const Color(0xFFcbd5e0),
                  size: 20,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    '🔧 Vehicle was just serviced',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF16a34a),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_checked) ...[
          const SizedBox(height: 10),
          TextField(
            controller: widget.lastSvcDateCtrl,
            readOnly: true,
            enabled: !widget.readOnly,
            decoration: InputDecoration(
              labelText: 'Last Service Date',
              border: const OutlineInputBorder(),
              suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
              filled: widget.readOnly,
              fillColor: widget.readOnly ? const Color(0xFFF7F8FA) : null,
            ),
            onTap: widget.readOnly
                ? null
                : () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate:
                          DateTime.tryParse(widget.lastSvcDateCtrl.text) ??
                          DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                      builder: (c, child) => Theme(
                        data: Theme.of(c).copyWith(
                          colorScheme: const ColorScheme.light(
                            primary: Color(0xFFE8001C),
                          ),
                        ),
                        child: child!,
                      ),
                    );
                    if (picked != null) {
                      widget.lastSvcDateCtrl.text =
                          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                    }
                  },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: widget.lastSvcOdoCtrl,
            keyboardType: TextInputType.number,
            readOnly: widget.readOnly,
            enabled: !widget.readOnly,
            decoration: InputDecoration(
              labelText: 'Last Service Odometer (km)',
              border: const OutlineInputBorder(),
              suffixText: 'km',
              filled: widget.readOnly,
              fillColor: widget.readOnly ? const Color(0xFFF7F8FA) : null,
            ),
          ),
        ],
      ],
    );
  }
}

/// Philippine plate number formatter: AAA-1234 (3 letters, dash, 4 digits)
class _PlateNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final isDeleting = newValue.text.length < oldValue.text.length;
    final raw = newValue.text.toUpperCase().replaceAll(
      RegExp(r'[^A-Z0-9]'),
      '',
    );
    final letters = raw.replaceAll(RegExp(r'[^A-Z]'), '');
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    final l = letters.substring(0, letters.length.clamp(0, 3));
    final d = digits.substring(0, digits.length.clamp(0, 4));

    String result;
    if (d.isNotEmpty) {
      result = '$l $d';
    } else if (l.length == 3 && !isDeleting) {
      result = '$l ';
    } else {
      result = l;
    }

    return TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: result.length),
    );
  }
}
