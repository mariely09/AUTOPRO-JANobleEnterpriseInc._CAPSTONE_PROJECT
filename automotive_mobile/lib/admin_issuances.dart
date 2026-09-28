import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_bottomnavbar.dart';
import 'admin_dashboard.dart';
import 'admin_inventory_hub.dart';
import 'admin_vehicles_list.dart';
import 'profile.dart';

class AdminIssuances extends StatelessWidget {
  const AdminIssuances({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: const AdminIssuancesBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddIssuanceScreen()),
          );
        },
        backgroundColor: const Color(0xFFE31E24),
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
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
              MaterialPageRoute(builder: (_) => const AdminInventoryHub()),
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

/// Embeddable body — can be placed inside any parent (e.g. a tab in the dashboard).
class AdminIssuancesBody extends StatefulWidget {
  final String searchQuery;
  const AdminIssuancesBody({super.key, this.searchQuery = ''});

  @override
  State<AdminIssuancesBody> createState() => _AdminIssuancesBodyState();
}

class _AdminIssuancesBodyState extends State<AdminIssuancesBody> {
  static const _red = Color(0xFFE8001C);

  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String _typeFilter = 'all'; // 'all', 'Material', 'Service'

  // Live vehicle lookup (plate -> desc)
  Map<String, String> _vehicleDescMap = {};

  static const _monthsShort = [
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
  static const _monthsLong = [
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

  @override
  void initState() {
    super.initState();
    _loadVehicles();
  }

  Future<void> _loadVehicles() async {
    final snap = await FirebaseFirestore.instance.collection('vehicles').get();
    if (!mounted) return;
    setState(() {
      _vehicleDescMap = {};
      for (final d in snap.docs) {
        final data = d.data();
        final plate = data['plate'] as String? ?? '';
        final desc =
            data['desc'] as String? ??
            data['assetDescription'] as String? ??
            '';
        if (plate.isNotEmpty) _vehicleDescMap[plate] = desc;
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _fmtDate(String dateStr) {
    if (dateStr.isEmpty || dateStr == '—') return dateStr;
    for (int i = 0; i < _monthsShort.length; i++) {
      if (dateStr.startsWith(_monthsShort[i])) {
        return dateStr.replaceFirst(_monthsShort[i], _monthsLong[i]);
      }
    }
    final slash = dateStr.split('/');
    if (slash.length == 3) {
      final m = int.tryParse(slash[0]);
      final d = int.tryParse(slash[1]);
      final y = int.tryParse(slash[2]);
      if (m != null && d != null && y != null && m >= 1 && m <= 12) {
        return '${_monthsLong[m - 1]} $d, $y';
      }
    }
    final dt = DateTime.tryParse(dateStr);
    if (dt != null) return '${_monthsLong[dt.month - 1]} ${dt.day}, ${dt.year}';
    return dateStr;
  }

  @override
  Widget build(BuildContext context) {
    return _buildBody();
  }

  Widget _buildBody() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('issuances')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final docs = snapshot.data?.docs ?? [];
        final all = docs.map((d) {
          final data = d.data() as Map<String, dynamic>;
          return {...data, 'docId': d.id};
        }).toList();

        final afterType = _typeFilter == 'all'
            ? all
            : all
                  .where((d) => (d['itemType'] as String? ?? '') == _typeFilter)
                  .toList();

        final activeQuery = widget.searchQuery.isNotEmpty
            ? widget.searchQuery
            : _searchQuery;
        final filtered = activeQuery.isEmpty
            ? afterType
            : afterType.where((d) {
                final name = (d['itemName'] ?? d['item'] ?? '')
                    .toString()
                    .toLowerCase();
                final plate = (d['plate'] as String? ?? '').toLowerCase();
                final by = (d['createdBy'] as String? ?? '').toLowerCase();
                return name.contains(activeQuery) ||
                    plate.contains(activeQuery) ||
                    by.contains(activeQuery);
              }).toList();

        final totalMat = all
            .where((d) => (d['itemType'] as String? ?? '') == 'Material')
            .length;
        final totalSvc = all
            .where((d) => (d['itemType'] as String? ?? '') == 'Service')
            .length;

        return Column(
          children: [
            // ── Stat chips ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  _chip(
                    'All',
                    '${all.length}',
                    const Color(0xFF003087),
                    Icons.list_alt_outlined,
                    'all',
                  ),
                  const SizedBox(width: 8),
                  _chip(
                    'Material',
                    '$totalMat',
                    _red,
                    Icons.inventory_2_outlined,
                    'Material',
                  ),
                  const SizedBox(width: 8),
                  _chip(
                    'Service',
                    '$totalSvc',
                    const Color(0xFF003087),
                    Icons.build_outlined,
                    'Service',
                  ),
                ],
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(
                      child: Text(
                        'No issuances found.',
                        style: TextStyle(color: Color(0xFF718096)),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _issCard(filtered[i]),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _chip(
    String label,
    String value,
    Color color,
    IconData icon,
    String filter,
  ) {
    final isActive = _typeFilter == filter;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _typeFilter = filter),
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
                  fontSize: 15,
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

  Widget _issCard(Map<String, dynamic> iss) {
    final name = (iss['itemName'] ?? iss['item'] ?? '—') as String;
    final plate = iss['plate'] as String? ?? '—';
    final date = iss['date'] as String? ?? '—';
    final qty = iss['qty']?.toString() ?? '—';
    final uom = iss['uom'] as String? ?? '';
    final subtotal = double.tryParse(iss['subtotal']?.toString() ?? '0') ?? 0;
    final group = iss['commodityGroup'] as String? ?? '';
    final isMat = (iss['itemType'] as String? ?? '') == 'Material';
    final typeColor = isMat ? _red : const Color(0xFF003087);
    final typeBg = isMat ? const Color(0xFFFFF5F5) : const Color(0xFFebf8ff);
    // Look up vehicle description from live vehicles data
    final liveDesc = _vehicleDescMap[plate] ?? '';

    return GestureDetector(
      onTap: () => _showDetail(iss),
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
                    plate ?? '—',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  if (liveDesc.isNotEmpty)
                    Text(
                      liveDesc,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF718096),
                      ),
                    ),
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF4a5568),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: typeBg,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          isMat ? 'Material' : 'Service',
                          style: TextStyle(
                            fontSize: 9,
                            color: typeColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _fmtDate(date),
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF718096),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₱${subtotal.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Color(0xFF1a202c),
                  ),
                ),
                Text(
                  '$qty $uom',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF718096),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFFa0aec0)),
          ],
        ),
      ),
    );
  }

  void _showDetail(Map<String, dynamic> iss) {
    final name = (iss['itemName'] ?? iss['item'] ?? '—') as String;
    final itemNum = iss['itemNum'] as String? ?? '—';
    final plate = iss['plate'] as String? ?? '—';
    // Look up vehicle description from live vehicles data (stays in sync with edits)
    final assetDesc =
        _vehicleDescMap[plate] ?? (iss['assetDesc'] as String? ?? '');
    final date = iss['date'] as String? ?? '—';
    final qty = iss['qty']?.toString() ?? '0';
    final uom = iss['uom'] as String? ?? '';
    final unitCost = double.tryParse(iss['unitCost']?.toString() ?? '0') ?? 0;
    final subtotal = double.tryParse(iss['subtotal']?.toString() ?? '0') ?? 0;
    final by = iss['createdBy'] as String? ?? '—';
    final group = iss['commodityGroup'] as String? ?? '—';
    final isMat = (iss['itemType'] as String? ?? '') == 'Material';
    final color = isMat ? _red : const Color(0xFF003087);

    Widget detailRow(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
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
              value.isNotEmpty && value != '—' ? value : '—',
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

    Widget costBox(
      String label,
      String value,
      String sub,
      Color bg,
      Color valueColor,
    ) => Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              color: Color(0xFF718096),
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
            textAlign: TextAlign.center,
          ),
          if (sub.isNotEmpty)
            Text(
              sub,
              style: const TextStyle(fontSize: 9, color: Color(0xFF718096)),
            ),
        ],
      ),
    );

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
        maxChildSize: 0.92,
        builder: (_, ctrl) => SingleChildScrollView(
          controller: ctrl,
          child: Column(
            children: [
              // ── Colored header ──
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            plate,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (assetDesc.isNotEmpty)
                            Text(
                              assetDesc,
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
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // ── Subtotal + date summary banner ──
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFe2e8f0)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Issued By',
                                style: TextStyle(
                                  color: Color(0xFF718096),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                by,
                                style: const TextStyle(
                                  color: Color(0xFF1a202c),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text(
                                'Date',
                                style: TextStyle(
                                  color: Color(0xFF718096),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                _fmtDate(date),
                                style: const TextStyle(
                                  color: Color(0xFF1a202c),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // ── Item details ──
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFe2e8f0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '📋  ITEM DETAILS',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF718096),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          detailRow('Item Name', name),
                          detailRow(
                            'Item Type',
                            isMat ? 'Material' : 'Service',
                          ),
                          detailRow('Commodity Group', group),
                          detailRow('UOM', uom),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // ── Cost breakdown ──
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFe2e8f0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '💰  COST BREAKDOWN',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF718096),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: costBox(
                                  'Quantity',
                                  qty,
                                  uom,
                                  const Color(0xFFF7F8FA),
                                  const Color(0xFF1a202c),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: costBox(
                                  'Unit Cost',
                                  '₱${unitCost.toStringAsFixed(2)}',
                                  '',
                                  const Color(0xFFebf8ff),
                                  const Color(0xFF2b6cb0),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: costBox(
                                  'Subtotal',
                                  '₱${subtotal.toStringAsFixed(2)}',
                                  '',
                                  const Color(0xFFFFF5F5),
                                  _red,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// Add Issuance Screen
// ══════════════════════════════════════════════════════════════════════════
// Add Issuance Screen with Commodity Group Filter & Searchable Items
// ══════════════════════════════════════════════════════════════════════════

class AddIssuanceScreen extends StatefulWidget {
  const AddIssuanceScreen({super.key});

  @override
  State<AddIssuanceScreen> createState() => _AddIssuanceScreenState();
}

class _AddIssuanceScreenState extends State<AddIssuanceScreen> {
  static const _red = Color(0xFFE31E24);

  final _formKey = GlobalKey<FormState>();
  final _dateCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController();
  final _itemSearchCtrl = TextEditingController();

  String? _selectedVehicle;
  String? _selectedCommodityGroup;
  String? _selectedItem;
  String? _selectedItemType;

  Map<String, dynamic> _vehicleData = {};
  Map<String, dynamic> _itemData = {};

  List<Map<String, dynamic>> _vehicles = [];
  List<Map<String, dynamic>> _allItems = [];
  List<Map<String, dynamic>> _filteredItems = [];
  List<String> _commodityGroups = [];
  Map<String, String> _commodityGroupItemTypes = {}; // Auto-detect item type

  bool _loading = false;
  double _subtotal = 0.0;

  @override
  void initState() {
    super.initState();
    _dateCtrl.text = _formatDateForInput(DateTime.now());
    _loadVehicles();
    _loadCommodityGroups();
    _loadItems();
    _qtyCtrl.addListener(_calculateSubtotal);
    _itemSearchCtrl.addListener(_filterItems);
  }

  @override
  void dispose() {
    _dateCtrl.dispose();
    _qtyCtrl.dispose();
    _itemSearchCtrl.dispose();
    super.dispose();
  }

  String _formatDateForInput(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _formatDateForDisplay(String dateStr) {
    final parts = dateStr.split('-');
    if (parts.length != 3) return dateStr;
    final months = [
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
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    final year = int.tryParse(parts[0]);
    if (month == null || day == null || year == null) return dateStr;
    return '${months[month - 1]} $day, $year';
  }

  Future<void> _loadVehicles() async {
    final snap = await FirebaseFirestore.instance
        .collection('vehicles')
        .orderBy('plate')
        .get();
    if (!mounted) return;
    setState(() {
      _vehicles = snap.docs
          .map((d) {
            final data = d.data();
            return {
              'plate': data['plate'] as String? ?? '',
              'desc':
                  data['desc'] as String? ??
                  data['assetDescription'] as String? ??
                  '',
            };
          })
          .where((v) => v['plate']!.isNotEmpty)
          .toList();
    });
  }

  Future<void> _loadCommodityGroups() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('domains')
          .doc('commodity_groups')
          .collection('items')
          .orderBy('name')
          .get();
      if (!mounted) return;
      final groups = snap.docs
          .map((d) => d.data()['name'] as String? ?? '')
          .where((n) => n.isNotEmpty)
          .toSet()
          .toList();
      setState(() {
        _commodityGroups = groups.isNotEmpty
            ? groups
            : ['Lubricants', 'Spare Parts', 'Filter', 'AutoService'];
      });
    } catch (e) {
      setState(() {
        _commodityGroups = [
          'Lubricants',
          'Spare Parts',
          'Filter',
          'AutoService',
        ];
      });
    }
  }

  Future<void> _loadItems() async {
    print('🔍 Loading items from item_master...');
    try {
      final snap = await FirebaseFirestore.instance
          .collection('item_master')
          .orderBy('name')
          .get();

      print('📦 Found ${snap.docs.length} documents');

      if (!mounted) return;

      setState(() {
        _allItems = snap.docs
            .map((d) {
              final data = d.data();

              // Use correct field names: 'group', 'num', 'cost'
              final group = data['group'] as String? ?? '';
              final itemNum = data['num'] as String? ?? '';
              final name = data['name'] as String? ?? '';
              final uom = data['uom'] as String? ?? '';
              final cost = (data['cost'] ?? 0).toString();

              // Auto-detect: "Service" if AutoService, otherwise "Material"
              final itemType = (group.toLowerCase() == 'autoservice')
                  ? 'Service'
                  : 'Material';

              // Debug first few items
              if (_allItems.length < 3) {
                print('Item: $itemNum - $name | Group: $group');
              }

              // Track item type for each commodity group
              if (group.isNotEmpty &&
                  !_commodityGroupItemTypes.containsKey(group)) {
                _commodityGroupItemTypes[group] = itemType;
              }

              return {
                'itemNum': itemNum,
                'name': name,
                'uom': uom,
                'unitCost': cost,
                'commodityGroup': group,
                'itemType': itemType,
              };
            })
            .where(
              (i) =>
                  i['itemNum']!.isNotEmpty &&
                  i['name']!.isNotEmpty &&
                  i['commodityGroup']!.isNotEmpty,
            )
            .toList();
      });

      print('✅ Loaded ${_allItems.length} items');
      print('📋 Groups: ${_commodityGroupItemTypes.keys.toList()}');
    } catch (e) {
      print('❌ Error: $e');
    }
  }

  void _onCommodityGroupChanged(String? group) {
    setState(() {
      _selectedCommodityGroup = group;
      _selectedItem = null;
      _itemData = {};
      _itemSearchCtrl.clear();

      // Auto-set item type based on commodity group
      if (group != null && _commodityGroupItemTypes.containsKey(group)) {
        _selectedItemType = _commodityGroupItemTypes[group];
        print('🔧 Item type for "$group": $_selectedItemType');
      } else {
        _selectedItemType = 'Material'; // Default
        print('🔧 Item type defaulted to: Material (group: $group)');
      }
    });

    // Call filter after setState completes
    Future.microtask(() => _filterItems());
  }

  void _filterItems() {
    if (_selectedCommodityGroup == null) {
      if (mounted) setState(() => _filteredItems = []);
      return;
    }

    final query = _itemSearchCtrl.text.toLowerCase();

    // Debug: print to see what's happening
    print('Filtering items for group: $_selectedCommodityGroup');
    print('Total items loaded: ${_allItems.length}');
    print('Search query: $query');

    final filtered = _allItems.where((item) {
      final itemGroup = item['commodityGroup'] as String? ?? '';
      print('Item: ${item['itemNum']} - Group: $itemGroup');

      if (itemGroup != _selectedCommodityGroup) return false;
      if (query.isEmpty) return true;

      final itemNum = (item['itemNum'] as String? ?? '').toLowerCase();
      final itemName = (item['name'] as String? ?? '').toLowerCase();

      return itemNum.contains(query) || itemName.contains(query);
    }).toList();

    print('Filtered items count: ${filtered.length}');

    if (mounted) {
      setState(() {
        _filteredItems = filtered;
      });
    }
  }

  void _showItemSelectionBottomSheet() {
    // Create a local search controller for the modal
    final modalSearchCtrl = TextEditingController(text: _itemSearchCtrl.text);
    List<Map<String, dynamic>> modalFilteredItems = List.from(_filteredItems);

    showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            void filterModalItems(String query) {
              final lowerQuery = query.toLowerCase();
              final filtered = _allItems.where((item) {
                final itemGroup = item['commodityGroup'] as String? ?? '';
                if (itemGroup != _selectedCommodityGroup) return false;
                if (lowerQuery.isEmpty) return true;

                final itemNum = (item['itemNum'] as String? ?? '')
                    .toLowerCase();
                final itemName = (item['name'] as String? ?? '').toLowerCase();

                return itemNum.contains(lowerQuery) ||
                    itemName.contains(lowerQuery);
              }).toList();

              setModalState(() {
                modalFilteredItems = filtered;
              });
            }

            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (context, scrollController) {
                return Column(
                  children: [
                    // Handle bar
                    Container(
                      margin: const EdgeInsets.only(top: 8, bottom: 4),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    // Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Select Item',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2d3748),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: () => Navigator.pop(context),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                    // Search field
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: modalSearchCtrl,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: 'Search by item number or name...',
                          hintStyle: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF718096),
                          ),
                          prefixIcon: const Icon(
                            Icons.search,
                            color: Color(0xFFa0aec0),
                            size: 20,
                          ),
                          suffixIcon: modalSearchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    modalSearchCtrl.clear();
                                    filterModalItems('');
                                  },
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: Color(0xFFe2e8f0),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: Color(0xFFe2e8f0),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: Color(0xFF3b82f6),
                              width: 2,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          isDense: true,
                        ),
                        onChanged: filterModalItems,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Item count
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          modalFilteredItems.isEmpty
                              ? modalSearchCtrl.text.isEmpty
                                    ? 'No items in "$_selectedCommodityGroup"'
                                    : 'No items match "${modalSearchCtrl.text}"'
                              : '${modalFilteredItems.length} item${modalFilteredItems.length == 1 ? '' : 's'} found',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF718096),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    // Items list
                    Expanded(
                      child: modalFilteredItems.isEmpty
                          ? Center(
                              child: Text(
                                modalSearchCtrl.text.isEmpty
                                    ? 'No items available in this group'
                                    : 'No matching items found',
                                style: const TextStyle(
                                  color: Color(0xFF718096),
                                  fontSize: 14,
                                ),
                              ),
                            )
                          : ListView.builder(
                              controller: scrollController,
                              itemCount: modalFilteredItems.length,
                              itemBuilder: (context, index) {
                                final item = modalFilteredItems[index];
                                final itemNum = item['itemNum'] as String;
                                final name = item['name'] as String;
                                final uom = item['uom'] as String? ?? '';
                                final isSelected = _selectedItem == itemNum;

                                return InkWell(
                                  onTap: () async {
                                    // Store data
                                    final selectedData = {
                                      'itemNum': itemNum,
                                      'itemData': Map<String, dynamic>.from(
                                        item,
                                      ),
                                      'searchText': modalSearchCtrl.text,
                                    };

                                    // Close modal
                                    Navigator.of(context).pop();

                                    // Wait a bit for modal to close
                                    await Future.delayed(
                                      const Duration(milliseconds: 300),
                                    );

                                    // Update parent state
                                    if (mounted) {
                                      setState(() {
                                        _selectedItem =
                                            selectedData['itemNum'] as String;
                                        _itemData =
                                            selectedData['itemData']
                                                as Map<String, dynamic>;
                                        _itemSearchCtrl.text =
                                            selectedData['searchText']
                                                as String;
                                        _calculateSubtotal();
                                      });
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? const Color(0xFFEBF5FF)
                                          : null,
                                      border: Border(
                                        bottom: BorderSide(
                                          color: Colors.grey[200]!,
                                          width: 0.5,
                                        ),
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
                                                itemNum,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color: isSelected
                                                      ? const Color(0xFF1e40af)
                                                      : const Color(0xFF2d3748),
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                name,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Color(0xFF4a5568),
                                                ),
                                              ),
                                              if (uom.isNotEmpty) ...[
                                                const SizedBox(height: 2),
                                                Text(
                                                  'UOM: $uom',
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Color(0xFF718096),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        if (isSelected)
                                          const Icon(
                                            Icons.check_circle,
                                            color: Color(0xFF1e40af),
                                            size: 20,
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    ).whenComplete(() {
      // Cleanup when modal closes
      modalSearchCtrl.dispose();
    });
  }

  void _calculateSubtotal() {
    final qty = double.tryParse(_qtyCtrl.text) ?? 0;
    final unitCost = double.tryParse(_itemData['unitCost'] ?? '0') ?? 0;
    setState(() {
      _subtotal = qty * unitCost;
    });
  }

  Future<void> _saveIssuance() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedVehicle == null ||
        _selectedCommodityGroup == null ||
        _selectedItem == null ||
        _selectedItemType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all required fields')),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final qty = double.tryParse(_qtyCtrl.text) ?? 0;
      final unitCost = double.tryParse(_itemData['unitCost'] ?? '0') ?? 0;
      final subtotal = qty * unitCost;

      await FirebaseFirestore.instance.collection('issuances').add({
        'date': _formatDateForDisplay(_dateCtrl.text),
        'plate': _selectedVehicle,
        'assetNum': _selectedVehicle,
        'assetDesc': _vehicleData['desc'] ?? '',
        'itemNum': _selectedItem,
        'itemName': _itemData['name'] ?? '',
        'itemType': _selectedItemType,
        'commodityGroup': _selectedCommodityGroup,
        'uom': _itemData['uom'] ?? '',
        'qty': qty,
        'quantity': qty,
        'unitCost': unitCost,
        'subtotal': subtotal,
        'createdBy': 'Admin',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Issuance added successfully'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: _red,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'New Issuance',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Date
            _buildLabel('Date *'),
            TextFormField(
              controller: _dateCtrl,
              decoration: _inputDecoration('Select date'),
              readOnly: true,
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (picked != null) {
                  setState(() => _dateCtrl.text = _formatDateForInput(picked));
                }
              },
              validator: (v) => v == null || v.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),

            // Vehicle
            _buildLabel('Vehicle *'),
            DropdownButtonFormField<String>(
              value: _selectedVehicle,
              decoration: _inputDecoration('Select vehicle'),
              items: _vehicles.map((v) {
                final plate = v['plate'] as String;
                final desc = v['desc'] as String;
                return DropdownMenuItem(
                  value: plate,
                  child: Text(
                    desc.isEmpty ? plate : '$plate - $desc',
                    style: const TextStyle(fontSize: 13),
                  ),
                );
              }).toList(),
              onChanged: (val) {
                setState(() {
                  _selectedVehicle = val;
                  _vehicleData = _vehicles.firstWhere((v) => v['plate'] == val);
                });
              },
              validator: (v) => v == null ? 'Required' : null,
            ),
            if (_vehicleData['desc']?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(
                _vehicleData['desc']!,
                style: const TextStyle(fontSize: 12, color: Color(0xFF718096)),
              ),
            ],
            const SizedBox(height: 16),

            // Commodity Group Filter
            _buildLabel('Commodity Group *'),
            DropdownButtonFormField<String>(
              value: _selectedCommodityGroup,
              decoration: _inputDecoration('Select commodity group'),
              items: _commodityGroups.map((g) {
                return DropdownMenuItem(
                  value: g,
                  child: Text(g, style: const TextStyle(fontSize: 13)),
                );
              }).toList(),
              onChanged: _onCommodityGroupChanged,
              validator: (v) => v == null ? 'Required' : null,
            ),
            const SizedBox(height: 16),

            // Item Search - Bottom Sheet Modal
            if (_selectedCommodityGroup != null) ...[
              _buildLabel('Search & Select Item *'),
              InkWell(
                onTap: _allItems.isEmpty ? null : _showItemSelectionBottomSheet,
                child: InputDecorator(
                  decoration: _inputDecoration(
                    'Tap to select item',
                  ).copyWith(suffixIcon: const Icon(Icons.arrow_drop_down)),
                  child: Text(
                    _selectedItem != null &&
                            _itemData['name']?.isNotEmpty == true
                        ? '$_selectedItem - ${_itemData['name']}'
                        : _allItems.isEmpty
                        ? 'Loading items...'
                        : _filteredItems.isEmpty
                        ? 'No items in "$_selectedCommodityGroup"'
                        : 'Select an item (${_filteredItems.length} items)',
                    style: TextStyle(
                      fontSize: 13,
                      color: _selectedItem != null
                          ? const Color(0xFF2d3748)
                          : const Color(0xFF718096),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Item Type (Auto-filled, read-only)
            _buildLabel('Item Type *'),
            TextFormField(
              key: ValueKey(_selectedItemType),
              initialValue: _selectedItemType ?? '',
              decoration: _inputDecoration('Auto-detected from group'),
              readOnly: true,
              style: const TextStyle(color: Color(0xFF4a5568)),
            ),
            const SizedBox(height: 16),

            if (_itemData['uom']?.isNotEmpty == true) ...[
              _buildReadOnlyField('UOM', _itemData['uom']!),
              const SizedBox(height: 16),
            ],

            // Quantity
            _buildLabel('Quantity *'),
            TextFormField(
              controller: _qtyCtrl,
              decoration: _inputDecoration('Enter quantity'),
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v == null || v.isEmpty) return 'Required';
                final n = double.tryParse(v);
                if (n == null || n <= 0) return 'Must be > 0';
                return null;
              },
            ),
            const SizedBox(height: 16),

            if (_itemData['unitCost']?.isNotEmpty == true) ...[
              _buildReadOnlyField(
                'Unit Cost',
                '₱${double.tryParse(_itemData['unitCost']!)?.toStringAsFixed(2) ?? '0.00'}',
              ),
              const SizedBox(height: 16),
            ],

            // Subtotal display
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFebf8ff),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF3182ce), width: 2),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Subtotal:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2c5282),
                    ),
                  ),
                  Text(
                    '₱${_subtotal.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF2c5282),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _loading ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: Color(0xFFe2e8f0)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF4a5568),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _loading ? null : _saveIssuance,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _red,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Save Issuance',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF4a5568),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFFa0aec0), fontSize: 13),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFe2e8f0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFe2e8f0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF3182ce), width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Widget _buildReadOnlyField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(label),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F8FA),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFe2e8f0)),
          ),
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, color: Color(0xFF4a5568)),
          ),
        ),
      ],
    );
  }
}
