import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'staff_receiving.dart';
import 'sync_indicator.dart';

class StaffInventory extends StatefulWidget {
  const StaffInventory({super.key});

  @override
  State<StaffInventory> createState() => _StaffInventoryState();
}

class _StaffInventoryState extends State<StaffInventory> {
  static const _red = Color(0xFFE8001C);
  static const _stockCol = 'stock_inventory';

  int _tab = 0; // 0 = Inventory, 1 = Receiving
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  bool _searching = false;
  String _statusFilter = 'all';
  String _sortOrder = 'num-asc';
  String _groupFilter = '';
  List<String> _groups = [];

  CollectionReference get _db =>
      FirebaseFirestore.instance.collection(_stockCol);

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('domains')
          .doc('commodity_groups')
          .collection('items')
          .orderBy('name')
          .get();
      final list = snap.docs.map((d) => d['name'] as String).toList();
      if (mounted) setState(() => _groups = list);
    } catch (_) {
      if (mounted)
        setState(
          () =>
              _groups = ['Lubricants', 'Spare Parts', 'Filter', 'AutoService'],
        );
    }
  }

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
        backgroundColor: const Color(0xFF004B5F),
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF004B5F), Color(0xFF006B7D), Color(0xFFEE152A)],
              stops: [0.0, 0.35, 1.0],
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
                      ? 'Search items...'
                      : 'Search deliveries...',
                  hintStyle: const TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                ),
              )
            : Text(
                _tab == 0 ? 'Stock Inventory' : 'Receiving Items',
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
          if (!_searching)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onSelected: (val) {
                if (val.startsWith('sort:')) {
                  setState(() => _sortOrder = val.substring(5));
                } else if (val.startsWith('group:')) {
                  setState(() => _groupFilter = val.substring(6));
                }
              },
              itemBuilder: (_) {
                final groupList = _groups.isEmpty
                    ? ['Lubricants', 'Spare Parts', 'Filter', 'AutoService']
                    : _groups;
                return [
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
                  _popItem(
                    'sort:num-asc',
                    'Item No. (Ascending)',
                    Icons.arrow_upward,
                    _sortOrder == 'num-asc',
                    _red,
                  ),
                  _popItem(
                    'sort:num-desc',
                    'Item No. (Descending)',
                    Icons.arrow_downward,
                    _sortOrder == 'num-desc',
                    _red,
                  ),
                  _popItem(
                    'sort:name-asc',
                    'Name A → Z',
                    Icons.sort_by_alpha,
                    _sortOrder == 'name-asc',
                    _red,
                  ),
                  _popItem(
                    'sort:name-desc',
                    'Name Z → A',
                    Icons.sort_by_alpha,
                    _sortOrder == 'name-desc',
                    _red,
                  ),
                  _popItem(
                    'sort:stock-desc',
                    'Stock ↑ Highest',
                    Icons.trending_up,
                    _sortOrder == 'stock-desc',
                    _red,
                  ),
                  _popItem(
                    'sort:stock-asc',
                    'Stock ↓ Lowest',
                    Icons.trending_down,
                    _sortOrder == 'stock-asc',
                    _red,
                  ),
                  _popItem(
                    'sort:group-asc',
                    'Group A → Z',
                    Icons.folder_outlined,
                    _sortOrder == 'group-asc',
                    _red,
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    enabled: false,
                    child: Text(
                      'Filter by Group',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF718096),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _popItem(
                    'group:',
                    'All Groups',
                    Icons.select_all,
                    _groupFilter.isEmpty,
                    const Color(0xFF003087),
                  ),
                  ...groupList.map(
                    (g) => _popItem(
                      'group:$g',
                      g,
                      Icons.circle_outlined,
                      _groupFilter == g,
                      const Color(0xFF003087),
                    ),
                  ),
                ];
              },
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Container(
            color: Colors.white,
            child: Row(
              children: [_tabBtn(0, 'Inventory'), _tabBtn(1, 'Receiving')],
            ),
          ),
        ),
      ),
      body: OfflineSaveListener(
        child: IndexedStack(
          index: _tab,
          children: [
            _buildInventoryBody(),
            StaffReceivingBody(
              searchQuery: _tab == 1 && _searching ? _searchQuery : '',
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

  PopupMenuItem<String> _popItem(
    String value,
    String label,
    IconData icon,
    bool active,
    Color color,
  ) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 16, color: active ? color : const Color(0xFF718096)),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: active ? color : const Color(0xFF1a202c),
              fontWeight: active ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
          if (active) ...[
            const Spacer(),
            Icon(Icons.check, size: 14, color: color),
          ],
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _applySortOrder(List<Map<String, dynamic>> items) {
    int numPart(String s) =>
        int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    final sorted = List<Map<String, dynamic>>.from(items);
    switch (_sortOrder) {
      case 'num-asc':
        sorted.sort(
          (a, b) => numPart(
            a['num'] as String,
          ).compareTo(numPart(b['num'] as String)),
        );
        break;
      case 'num-desc':
        sorted.sort(
          (a, b) => numPart(
            b['num'] as String,
          ).compareTo(numPart(a['num'] as String)),
        );
        break;
      case 'name-asc':
        sorted.sort(
          (a, b) => (a['name'] as String).compareTo(b['name'] as String),
        );
        break;
      case 'name-desc':
        sorted.sort(
          (a, b) => (b['name'] as String).compareTo(a['name'] as String),
        );
        break;
      case 'stock-desc':
        sorted.sort((a, b) => (b['stock'] as int).compareTo(a['stock'] as int));
        break;
      case 'stock-asc':
        sorted.sort((a, b) => (a['stock'] as int).compareTo(b['stock'] as int));
        break;
      case 'group-asc':
        sorted.sort(
          (a, b) => (a['group'] as String).compareTo(b['group'] as String),
        );
        break;
    }
    return sorted;
  }

  Widget _buildInventoryBody() {
    return StreamBuilder<QuerySnapshot>(
      stream: _db.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final docs = snapshot.data?.docs ?? [];
        final items =
            docs.map((d) {
              final data = d.data() as Map<String, dynamic>;
              final stock = (data['stock'] as num?)?.toInt() ?? 0;
              final min = (data['min'] as num?)?.toInt() ?? 0;
              final max = (data['max'] as num?)?.toInt() ?? 0;
              return {
                'id': d.id,
                'num': data['num'] as String? ?? '',
                'name': data['name'] as String? ?? '',
                'group': data['group'] as String? ?? '',
                'uom': data['uom'] as String? ?? '',
                'stock': stock,
                'min': min,
                'max': max,
                'reorder': (data['reorder'] as num?)?.toInt() ?? 0,
                'status': (data['status'] as String? ?? '') == 'Inactive'
                    ? 'Inactive'
                    : stock > min
                    ? (stock > max ? 'Over' : 'OK')
                    : 'Low',
              };
            }).toList()..sort(
              (a, b) => (a['name'] as String).compareTo(b['name'] as String),
            );

        final filtered = _searchQuery.isEmpty
            ? items
            : items
                  .where(
                    (i) =>
                        (i['name'] as String).toLowerCase().contains(
                          _searchQuery,
                        ) ||
                        (i['num'] as String).toLowerCase().contains(
                          _searchQuery,
                        ) ||
                        (i['group'] as String).toLowerCase().contains(
                          _searchQuery,
                        ),
                  )
                  .toList();

        // Apply status filter
        final afterStatusFilter = _statusFilter == 'all'
            ? filtered
            : _statusFilter == 'out'
            ? filtered.where((i) => (i['stock'] as int) == 0).toList()
            : _statusFilter == 'Low'
            ? filtered
                  .where((i) => (i['stock'] as int) > 0 && i['status'] == 'Low')
                  .toList()
            : filtered.where((i) => i['status'] == _statusFilter).toList();

        // Apply commodity group filter
        final afterGroupFilter = _groupFilter.isEmpty
            ? afterStatusFilter
            : afterStatusFilter
                  .where((i) => (i['group'] as String) == _groupFilter)
                  .toList();

        final sortedFiltered = _applySortOrder(afterGroupFilter);

        final total = items.length;
        final lowCount = items
            .where((i) => (i['stock'] as int) > 0 && i['status'] == 'Low')
            .length;
        final outCount = items.where((i) => (i['stock'] as int) == 0).length;
        final inStock = items.where((i) => i['status'] == 'OK').length;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  _statChip('Total Items', '$total', Colors.blue, 'all'),
                  const SizedBox(width: 8),
                  _statChip('Out of Stock', '$outCount', Colors.red, 'out'),
                  const SizedBox(width: 8),
                  _statChip('Low Stock', '$lowCount', Colors.orange, 'Low'),
                  const SizedBox(width: 8),
                  _statChip('In Stock', '$inStock', Colors.green, 'OK'),
                ],
              ),
            ),
            Expanded(
              child: sortedFiltered.isEmpty
                  ? const Center(
                      child: Text(
                        'No items found.',
                        style: TextStyle(color: Color(0xFF718096)),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: sortedFiltered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _stockCard(sortedFiltered[i]),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _statChip(String label, String value, Color color, String filter) {
    IconData icon;
    switch (label) {
      case 'Total Items':
        icon = Icons.inventory_2_outlined;
        break;
      case 'Out of Stock':
        icon = Icons.remove_circle_outline;
        break;
      case 'Low Stock':
        icon = Icons.warning_amber_outlined;
        break;
      case 'In Stock':
        icon = Icons.check_circle_outline;
        break;
      default:
        icon = Icons.info_outline;
    }
    final isActive = _statusFilter == filter;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(
          () => _statusFilter = _statusFilter == filter ? 'all' : filter,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: isActive ? color.withValues(alpha: 0.08) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isActive ? color : Colors.transparent,
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
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                label,
                style: const TextStyle(fontSize: 10, color: Color(0xFF718096)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stockCard(Map<String, dynamic> item) {
    final status = item['status'] as String;
    final stock = item['stock'] as int;
    final min = item['min'] as int;
    final max = item['max'] as int;
    final isInactive = status == 'Inactive';
    final isOut = !isInactive && stock == 0;
    final isLow = !isInactive && !isOut && status == 'Low';
    final isOver = !isInactive && !isOut && !isLow && status == 'Over';
    final progress = max > 0 ? (stock / max).clamp(0.0, 1.0) : 0.0;
    final barColor = isInactive
        ? const Color(0xFF718096)
        : isOut
        ? Colors.red
        : isLow
        ? Colors.orange
        : isOver
        ? Colors.purple
        : Colors.green;
    final statusLabel = isInactive
        ? 'Inactive'
        : isOut
        ? 'Out of Stock'
        : isLow
        ? 'Low Stock'
        : isOver
        ? 'Over Max'
        : 'In Stock';

    return GestureDetector(
      onTap: () => _showStockDetails(item),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: isInactive
              ? Border.all(color: Colors.grey.shade300)
              : isOut
              ? Border.all(color: Colors.red.shade200)
              : isLow
              ? Border.all(color: Colors.orange.shade200)
              : isOver
              ? Border.all(color: Colors.purple.shade200)
              : null,
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['name'] as String,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '${item['group']}  •  ${item['uom']}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF718096),
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$stock',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: barColor,
                      ),
                    ),
                    Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 10,
                        color: barColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: Color(0xFFa0aec0),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: const Color(0xFFe2e8f0),
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Min: $min',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF718096),
                  ),
                ),
                Text(
                  '$stock / $max',
                  style: TextStyle(
                    fontSize: 10,
                    color: barColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  'Max: $max',
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
    );
  }

  void _showStockDetails(Map<String, dynamic> item) async {
    // Fetch supplierCode from item_master since stock_inventory doesn't store it
    String supplierCode = '';
    try {
      final num = item['num'] as String? ?? '';
      if (num.isNotEmpty) {
        final snap = await FirebaseFirestore.instance
            .collection('item_master')
            .where('num', isEqualTo: num)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) {
          supplierCode =
              (snap.docs.first.data() as Map<String, dynamic>)['supplierCode']
                  ?.toString() ??
              '';
        }
      }
    } catch (_) {}
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
        initialChildSize: 0.55,
        maxChildSize: 0.85,
        builder: (_, ctrl) => SingleChildScrollView(
          controller: ctrl,
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
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
                            item['name'] as String,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            item['uom'] as String,
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
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (supplierCode.isNotEmpty)
                      _detailRow('Supplier Item Code', supplierCode),
                    _detailRow('Item Number', item['num'] as String),
                    _detailRow('Item Name', item['name'] as String),
                    _detailRow('Commodity Group', item['group'] as String),
                    _detailRow('UOM', item['uom'] as String),
                    _detailRow('Current Stock', '${item['stock']}'),
                    _detailRow('Min Level', '${item['min']}'),
                    _detailRow('Max Level', '${item['max']}'),
                    _detailRow('Reorder Qty', '${item['reorder']}'),
                    _detailRow(
                      'Status',
                      item['stock'] == 0
                          ? 'Out of Stock'
                          : item['status'] == 'OK'
                          ? 'In Stock'
                          : item['status'] == 'Over'
                          ? 'Over Max'
                          : 'Low Stock',
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

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
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
  }
}
