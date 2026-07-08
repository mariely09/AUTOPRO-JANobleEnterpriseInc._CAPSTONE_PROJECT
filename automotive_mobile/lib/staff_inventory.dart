import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'staff_receiving.dart';

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
  String _statusFilter = 'all'; // 'all', 'Low', 'OK'

  CollectionReference get _db => FirebaseFirestore.instance.collection(_stockCol);

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
        backgroundColor: _red,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: _searching
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: _tab == 0 ? 'Search items...' : 'Search deliveries...',
                  hintStyle: const TextStyle(color: Colors.white54),
                  border: InputBorder.none,
                ),
              )
            : Text(_tab == 0 ? 'Stock Inventory' : 'Receiving Items',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close : Icons.search, color: Colors.white),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) { _searchCtrl.clear(); _searchQuery = ''; }
            }),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Container(
            color: Colors.white,
            child: Row(children: [
              _tabBtn(0, 'Inventory'),
              _tabBtn(1, 'Receiving'),
            ]),
          ),
        ),
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          _buildInventoryBody(),
          StaffReceivingBody(
            searchQuery: _tab == 1 && _searching ? _searchQuery : '',
          ),
        ],
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
            border: Border(bottom: BorderSide(
              color: active ? _red : Colors.transparent, width: 2))),
          child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: active ? FontWeight.w700 : FontWeight.normal,
              color: active ? _red : const Color(0xFF718096))),
        ),
      ),
    );
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
          final items = docs.map((d) {
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
              'stock': stock, 'min': min, 'max': max,
              'reorder': (data['reorder'] as num?)?.toInt() ?? 0,
              'status': stock > min ? (stock > max ? 'Over' : 'OK') : 'Low',
            };
          }).toList()
            ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

          final filtered = _searchQuery.isEmpty
              ? items
              : items.where((i) =>
                  (i['name'] as String).toLowerCase().contains(_searchQuery) ||
                  (i['num'] as String).toLowerCase().contains(_searchQuery) ||
                  (i['group'] as String).toLowerCase().contains(_searchQuery)).toList();

          // Apply status filter
          final afterStatusFilter = _statusFilter == 'all'
              ? filtered
              : filtered.where((i) => i['status'] == _statusFilter).toList();

          final total = items.length;
          final lowCount = items.where((i) => i['status'] == 'Low').length;
          final inStock = items.where((i) => i['status'] == 'OK').length;

          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(children: [
                _statChip('Total Items', '$total', Colors.blue, 'all'),
                const SizedBox(width: 8),
                _statChip('Low Stock', '$lowCount', _red, 'Low'),
                const SizedBox(width: 8),
                _statChip('In Stock', '$inStock', Colors.green, 'OK'),
              ]),
            ),
            Expanded(
              child: afterStatusFilter.isEmpty
                ? const Center(child: Text('No items found.', style: TextStyle(color: Color(0xFF718096))))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: afterStatusFilter.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _stockCard(afterStatusFilter[i]),
                  ),
            ),
          ]);
        },
      );
  }

  Widget _statChip(String label, String value, Color color, String filter) {
    IconData icon;
    switch (label) {
      case 'Total Items': icon = Icons.inventory_2_outlined; break;
      case 'Low Stock':   icon = Icons.warning_amber_outlined; break;
      case 'In Stock':    icon = Icons.check_circle_outline; break;
      default:            icon = Icons.info_outline;
    }
    final isActive = _statusFilter == filter;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _statusFilter = _statusFilter == filter ? 'all' : filter),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: isActive ? color.withValues(alpha: 0.08) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isActive ? color : Colors.transparent, width: 1.5),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
          ),
          child: Column(children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(height: 6),
            Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF718096))),
          ]),
        ),
      ),
    );
  }

  Widget _stockCard(Map<String, dynamic> item) {
    final status = item['status'] as String;
    final isLow = status == 'Low';
    final isOver = status == 'Over';
    final stock = item['stock'] as int;
    final min = item['min'] as int;
    final max = item['max'] as int;
    final progress = max > 0 ? (stock / max).clamp(0.0, 1.0) : 0.0;
    final barColor = isLow ? Colors.orange : isOver ? Colors.purple : Colors.green;
    final statusLabel = isLow ? 'Low Stock' : isOver ? 'Over Max' : 'In Stock';

    return GestureDetector(
      onTap: () => _showStockDetails(item),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: isLow ? Border.all(color: Colors.orange.shade200)
              : isOver ? Border.all(color: Colors.purple.shade200) : null,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              Text('${item['group']}', style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('$stock ${item['uom']}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: barColor)),
              Text(statusLabel, style: TextStyle(fontSize: 10, color: barColor, fontWeight: FontWeight.w500)),
            ]),
          ]),
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
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Min: $min', style: const TextStyle(fontSize: 10, color: Color(0xFF718096))),
            Text('$stock / $max', style: TextStyle(fontSize: 10, color: barColor, fontWeight: FontWeight.w500)),
            Text('Max: $max', style: const TextStyle(fontSize: 10, color: Color(0xFF718096))),
          ]),
        ]),
      ),
    );
  }

  void _showStockDetails(Map<String, dynamic> item) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => DraggableScrollableSheet(
        expand: false, initialChildSize: 0.55, maxChildSize: 0.85,
        builder: (_, ctrl) => SingleChildScrollView(
          controller: ctrl,
          child: Column(children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              decoration: const BoxDecoration(color: _red,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item['name'] as String, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(item['group'] as String, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ])),
                GestureDetector(onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close, color: Colors.white)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _detailRow('Item Number', item['num'] as String),
                _detailRow('Item Name', item['name'] as String),
                _detailRow('Commodity Group', item['group'] as String),
                _detailRow('Current Stock', '${item['stock']} ${item['uom']}'),
                _detailRow('Min Level', '${item['min']} ${item['uom']}'),
                _detailRow('Max Level', '${item['max']} ${item['uom']}'),
                _detailRow('Reorder Qty', '${item['reorder']} ${item['uom']}'),
                _detailRow('Status', item['status'] as String),
                const SizedBox(height: 16),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 140, child: Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF718096), fontWeight: FontWeight.w500))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1a202c)))),
      ]),
    );
  }
}
