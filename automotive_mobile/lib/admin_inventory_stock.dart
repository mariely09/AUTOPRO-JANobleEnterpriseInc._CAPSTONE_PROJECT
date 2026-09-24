import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'barcode_scanner_screen.dart';
import 'sync_indicator.dart';

/// Standalone full-screen wrapper for Stock Inventory.
/// Can be navigated to directly (e.g. from dashboard stat card).
class AdminInventoryStock extends StatefulWidget {
  final String? prefilledItemNum;
  final String? prefilledItemName;
  final String? prefilledGroup;
  final String? prefilledUom;
  final String? prefilledSupplierCode;

  const AdminInventoryStock({
    super.key,
    this.prefilledItemNum,
    this.prefilledItemName,
    this.prefilledGroup,
    this.prefilledUom,
    this.prefilledSupplierCode,
  });

  @override
  State<AdminInventoryStock> createState() => _AdminInventoryStockState();
}

class _AdminInventoryStockState extends State<AdminInventoryStock> {
  static const _red = Color(0xFFE8001C);
  String _sortOrder = 'num-asc';
  final _bodyKey = GlobalKey<AdminInventoryStockBodyState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: _red,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Inventory',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          const SyncIndicator(),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (val) {
              if (val.startsWith('sort:')) {
                setState(() => _sortOrder = val.substring(5));
              } else if (val.startsWith('group:')) {
                _bodyKey.currentState?.setState(() {
                  _bodyKey.currentState!.groupFilter = val.substring(6);
                });
              }
            },
            itemBuilder: (_) {
              final groupList = _bodyKey.currentState?.groups ?? ['Lubricants', 'Spare Parts', 'Filter', 'AutoService'];
              final currentGroup = _bodyKey.currentState?.groupFilter ?? '';
              return [
                const PopupMenuItem(enabled: false, child: Text('Sort By', style: TextStyle(fontSize: 11, color: Color(0xFF718096), fontWeight: FontWeight.w700))),
                _popItem('sort:num-asc',    'Item No. (Ascending)',  Icons.arrow_upward,    _sortOrder == 'num-asc',    _red),
                _popItem('sort:num-desc',   'Item No. (Descending)', Icons.arrow_downward,  _sortOrder == 'num-desc',   _red),
                _popItem('sort:name-asc',   'Name A → Z',            Icons.sort_by_alpha,   _sortOrder == 'name-asc',   _red),
                _popItem('sort:name-desc',  'Name Z → A',            Icons.sort_by_alpha,   _sortOrder == 'name-desc',  _red),
                _popItem('sort:stock-desc', 'Stock ↑ Highest',       Icons.trending_up,     _sortOrder == 'stock-desc', _red),
                _popItem('sort:stock-asc',  'Stock ↓ Lowest',        Icons.trending_down,   _sortOrder == 'stock-asc',  _red),
                const PopupMenuDivider(),
                const PopupMenuItem(enabled: false, child: Text('Filter by Group', style: TextStyle(fontSize: 11, color: Color(0xFF718096), fontWeight: FontWeight.w700))),
                _popItem('group:',  'All Groups', Icons.select_all,     currentGroup.isEmpty, const Color(0xFF003087)),
                ...groupList.map((g) => _popItem('group:$g', g, Icons.circle_outlined, currentGroup == g, const Color(0xFF003087))),
              ];
            },
          ),
        ],
      ),
      body: OfflineSaveListener(
        child: AdminInventoryStockBody(
        key: _bodyKey,
        sortOrder: _sortOrder,
        prefilledItemNum:      widget.prefilledItemNum,
        prefilledItemName:     widget.prefilledItemName,
        prefilledGroup:        widget.prefilledGroup,
        prefilledUom:          widget.prefilledUom,
        prefilledSupplierCode: widget.prefilledSupplierCode,
      )),
    );
  }

  PopupMenuItem<String> _popItem(String value, String label, IconData icon, bool active, Color color) {
    return PopupMenuItem(
      value: value,
      child: Row(children: [
        Icon(icon, size: 16, color: active ? color : const Color(0xFF718096)),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(fontSize: 13, color: active ? color : const Color(0xFF1a202c), fontWeight: active ? FontWeight.w700 : FontWeight.normal)),
        if (active) ...[const Spacer(), Icon(Icons.check, size: 14, color: color)],
      ]),
    );
  }
}

/// Embeddable body — can be placed inside any parent (e.g. a tab in the hub).
/// Accepts [searchQuery] from the parent's search bar.
class AdminInventoryStockBody extends StatefulWidget {
  final String searchQuery;
  final String sortOrder;
  final String groupFilter;
  final String? prefilledItemNum;
  final String? prefilledItemName;
  final String? prefilledGroup;
  final String? prefilledUom;
  final String? prefilledSupplierCode;

  const AdminInventoryStockBody({
    super.key,
    this.searchQuery = '',
    this.sortOrder = 'num-asc',
    this.groupFilter = '',
    this.prefilledItemNum,
    this.prefilledItemName,
    this.prefilledGroup,
    this.prefilledUom,
    this.prefilledSupplierCode,
  });

  @override
  AdminInventoryStockBodyState createState() =>
      AdminInventoryStockBodyState();
}

class AdminInventoryStockBodyState extends State<AdminInventoryStockBody>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  static const _red = Color(0xFFE8001C);
  static const _stockCol = 'stock_inventory';
  static const _masterCol = 'item_master';

  String _statusFilter = 'all';
  String _sortOrder = 'num-asc';
  String groupFilter = ''; // commodity group filter
  List<String> groups = [];

  @override
  void initState() {
    super.initState();
    _loadGroups();
    // Auto-open Add Stock modal if navigated from Item Master with prefilled item
    if (widget.prefilledItemNum != null && widget.prefilledItemNum!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showNewStockModalWithItem(
          itemNum:      widget.prefilledItemNum!,
          itemName:     widget.prefilledItemName    ?? '',
          group:        widget.prefilledGroup       ?? '',
          uom:          widget.prefilledUom         ?? '',
          supplierCode: widget.prefilledSupplierCode ?? '',
        );
      });
    }
  }

  Future<void> _loadGroups() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('domains').doc('commodity_groups').collection('items')
          .orderBy('name').get();
      final list = snap.docs.map((d) => d['name'] as String).toList();
      if (mounted) setState(() => groups = list);
    } catch (_) {
      if (mounted) setState(() => groups = ['Lubricants', 'Spare Parts', 'Filter', 'AutoService']);
    }
  }

  CollectionReference get _db =>
      FirebaseFirestore.instance.collection(_stockCol);
  CollectionReference get _masterDb =>
      FirebaseFirestore.instance.collection(_masterCol);

  Future<Map<String, dynamic>?> _findItemMaster(String query) async {
    if (query.isEmpty) return null;
    final raw = query.trim();

    String _norm(String s) {
      final t = s.trim();
      if (RegExp(r'^\d+$').hasMatch(t)) {
        final stripped = t.replaceFirst(RegExp(r'^0+'), '');
        return stripped.isEmpty ? '0' : stripped;
      }
      return t.toLowerCase();
    }

    bool _match(String stored, String scanned) {
      if (stored.isEmpty || scanned.isEmpty) return false;
      if (stored == scanned) return true;
      if (stored.toLowerCase() == scanned.toLowerCase()) return true;
      final sNum = RegExp(r'^\d+$').hasMatch(stored.trim());
      final qNum = RegExp(r'^\d+$').hasMatch(scanned.trim());
      if (sNum && qNum) {
        final ns = _norm(stored), nq = _norm(scanned);
        if (ns == nq) return true;
        if (ns.length >= 10 && nq.length > ns.length && nq.contains(ns)) return true;
        if (nq.length == ns.length + 1 && nq.startsWith(ns)) return true;
        for (int i = 1; i <= 3 && i < nq.length; i++) {
          if (nq.substring(i) == ns) return true;
        }
      }
      return false;
    }

    final all = await _masterDb.get();

    // P1: exact barcode
    var doc = all.docs.cast<DocumentSnapshot?>().firstWhere(
      (d) => (d!.data() as Map<String, dynamic>)['barcode']?.toString().trim() == raw,
      orElse: () => null);
    // P2: exact QR
    doc ??= all.docs.cast<DocumentSnapshot?>().firstWhere(
      (d) => (d!.data() as Map<String, dynamic>)['qr']?.toString().trim() == raw,
      orElse: () => null);
    // P3: normalized barcode/QR
    doc ??= all.docs.cast<DocumentSnapshot?>().firstWhere((d) {
      final data = d!.data() as Map<String, dynamic>;
      return _match(data['barcode']?.toString() ?? '', raw) ||
             _match(data['qr']?.toString()      ?? '', raw);
    }, orElse: () => null);
    // P4: item number
    doc ??= all.docs.cast<DocumentSnapshot?>().firstWhere(
      (d) => (d!.data() as Map<String, dynamic>)['num']?.toString().trim().toLowerCase() == raw.toLowerCase(),
      orElse: () => null);
    // P5: name contains (non-numeric only)
    if (doc == null && raw.length >= 3 && !RegExp(r'^\d+$').hasMatch(raw)) {
      doc = all.docs.cast<DocumentSnapshot?>().firstWhere(
        (d) => ((d!.data() as Map<String, dynamic>)['name']?.toString() ?? '').toLowerCase().contains(raw.toLowerCase()),
        orElse: () => null);
    }

    return doc != null ? _docToMaster(doc) : null;
  }

  /// Returns all item_master docs matching [query] (name, num, group, barcode, QR).
  Future<List<Map<String, dynamic>>> _searchItemMaster(String query) async {
    if (query.trim().isEmpty) return [];
    final raw = query.trim();
    final q = raw.toLowerCase();

    String _norm(String s) {
      final t = s.trim();
      if (RegExp(r'^\d+$').hasMatch(t)) {
        final stripped = t.replaceFirst(RegExp(r'^0+'), '');
        return stripped.isEmpty ? '0' : stripped;
      }
      return t.toLowerCase();
    }

    bool _match(String stored, String scanned) {
      if (stored.isEmpty || scanned.isEmpty) return false;
      if (stored == scanned) return true;
      if (stored.toLowerCase() == scanned.toLowerCase()) return true;
      final sNum = RegExp(r'^\d+$').hasMatch(stored.trim());
      final qNum = RegExp(r'^\d+$').hasMatch(scanned.trim());
      if (sNum && qNum) {
        final ns = _norm(stored), nq = _norm(scanned);
        if (ns == nq) return true;
        if (ns.length >= 10 && nq.length > ns.length && nq.contains(ns)) return true;
        if (nq.length == ns.length + 1 && nq.startsWith(ns)) return true;
        for (int i = 1; i <= 3 && i < nq.length; i++) {
          if (nq.substring(i) == ns) return true;
        }
      }
      return false;
    }

    final snap = await _masterDb.orderBy('name').get();
    return snap.docs
        .map((d) => _docToMaster(d))
        .where((item) {
          // Exclude Service type and AutoService group — no stock tracking needed
          final type  = (item['type']  as String? ?? '').toLowerCase();
          final group = (item['group'] as String? ?? '').toLowerCase();
          if (type == 'service' || group == 'autoservice') return false;
          return (item['name'] as String).toLowerCase().contains(q) ||
              (item['num'] as String).toLowerCase().contains(q) ||
              (item['group'] as String).toLowerCase().contains(q) ||
              (item['supplierCode'] as String).toLowerCase().contains(q) ||
              _match(item['barcode'] as String, raw) ||
              _match(item['qr']      as String, raw);
        })
        .toList();
  }

  Map<String, dynamic> _docToMaster(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return {
      'id': doc.id,
      'num': d['num'] ?? '',
      'supplierCode': d['supplierCode'] ?? '',
      'name': d['name'] ?? '',
      'group': d['group'] ?? '',
      'uom': d['uom'] ?? '',
      'barcode': d['barcode'] ?? '',
      'qr': d['qr'] ?? '',
    };
  }

  /// Resolves supplier code — uses stored value if available,
  /// otherwise fetches from item_master by num.
  Future<String> _resolveSupplierCode(Map<String, dynamic> item) async {
    final sc = item['supplierCode'] as String? ?? '';
    if (sc.isNotEmpty) return sc;
    final num = item['num'] as String? ?? '';
    if (num.isEmpty) return '—';
    try {
      final snap = await _masterDb.where('num', isEqualTo: num).limit(1).get();
      if (snap.docs.isNotEmpty) {
        final resolved = (snap.docs.first.data() as Map<String, dynamic>)['supplierCode']?.toString() ?? '';
        if (resolved.isNotEmpty) {
          // Backfill the stock doc so next time it's immediate
          _db.doc(item['id'] as String).update({'supplierCode': resolved}).catchError((_) {});
          return resolved;
        }
      }
    } catch (_) {}
    return '—';
  }

  List<Map<String, dynamic>> _applySortOrder(List<Map<String, dynamic>> items) {
    // Use widget.sortOrder (from hub) if local sort hasn't been changed, else use local
    final order = widget.sortOrder != 'num-asc' ? widget.sortOrder : _sortOrder;
    int numPart(String s) => int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    final sorted = List<Map<String, dynamic>>.from(items);
    switch (order) {
      case 'num-asc':    sorted.sort((a, b) => numPart(a['num'] as String).compareTo(numPart(b['num'] as String))); break;
      case 'num-desc':   sorted.sort((a, b) => numPart(b['num'] as String).compareTo(numPart(a['num'] as String))); break;
      case 'name-asc':   sorted.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String)); break;
      case 'name-desc':  sorted.sort((a, b) => (b['name'] as String).compareTo(a['name'] as String)); break;
      case 'stock-desc': sorted.sort((a, b) => (b['stock'] as int).compareTo(a['stock'] as int)); break;
      case 'stock-asc':  sorted.sort((a, b) => (a['stock'] as int).compareTo(b['stock'] as int)); break;
      case 'group-asc':  sorted.sort((a, b) => (a['group'] as String).compareTo(b['group'] as String)); break;
    }
    return sorted;
  }


  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Stack(
      children: [
        StreamBuilder<QuerySnapshot>(
          stream: _db.orderBy('name').snapshots(),
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
                'supplierCode': data['supplierCode'] as String? ?? '',
                'sku': data['sku'] as String? ?? '',
                'name': data['name'] as String? ?? '',
                'group': data['group'] as String? ?? '',
                'uom': data['uom'] as String? ?? '',
                'stock': stock,
                'min': min,
                'max': max,
                'reorder': (data['reorder'] as num?)?.toInt() ?? 0,
                // Preserve 'Over' if stock exceeds max, else compute from stock levels
                'status': stock > min
                    ? (stock > max ? 'Over' : 'OK')
                    : 'Low',
              };
            }).toList();

            final q = widget.searchQuery;
            final filtered = q.isEmpty
                ? items
                : items
                    .where((i) =>
                        (i['name'] as String)
                            .toLowerCase()
                            .contains(q) ||
                        (i['num'] as String)
                            .toLowerCase()
                            .contains(q) ||
                        (i['group'] as String)
                            .toLowerCase()
                            .contains(q))
                    .toList();

            // Apply status filter
            final afterStatusFilter = _statusFilter == 'all'
                ? filtered
                : _statusFilter == 'out'
                    ? filtered.where((i) => (i['stock'] as int) == 0).toList()
                    : _statusFilter == 'Low'
                        ? filtered.where((i) => (i['stock'] as int) > 0 && i['status'] == 'Low').toList()
                        : filtered.where((i) => i['status'] == _statusFilter).toList();

            // Apply commodity group filter — use widget prop (from hub) if set, else internal
            final activeGroupFilter = widget.groupFilter.isNotEmpty ? widget.groupFilter : groupFilter;
            final afterGroupFilter = activeGroupFilter.isEmpty
                ? afterStatusFilter
                : afterStatusFilter.where((i) => (i['group'] as String) == activeGroupFilter).toList();

            // Apply sort — prefer local state if set, else use widget prop
            final sortedFiltered = _applySortOrder(afterGroupFilter);

            final total = items.length;
            final lowCount =
                items.where((i) => (i['stock'] as int) > 0 && i['status'] == 'Low').length;
            final outCount =
                items.where((i) => (i['stock'] as int) == 0).length;

            return Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(children: [
                  _statChip('Total Items', '$total', Colors.blue,
                      Icons.inventory_2_outlined, 'all'),
                  const SizedBox(width: 8),
                  _statChip('Out of Stock', '$outCount', Colors.red,
                      Icons.remove_circle_outline, 'out'),
                  const SizedBox(width: 8),
                  _statChip('Low Stock', '$lowCount', Colors.orange,
                      Icons.warning_amber_outlined, 'Low'),
                  const SizedBox(width: 8),
                  _statChip(
                      'In Stock',
                      '${items.where((i) => i['status'] == 'OK').length}',
                      Colors.green,
                      Icons.check_circle_outline, 'OK'),
                ]),
              ),
              Expanded(
                child: sortedFiltered.isEmpty
                    ? const Center(
                        child: Text('No items found.',
                            style: TextStyle(color: Color(0xFF718096))))
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: sortedFiltered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _stockCard(sortedFiltered[i]),
                      ),
              ),
            ]);
          },
        ),
        // FAB
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton(
            heroTag: 'stock_fab',
            onPressed: _showNewStockModal,
            backgroundColor: _red,
            child: const Icon(Icons.add, color: Colors.white, size: 28),
          ),
        ),
      ],
    );
  }


  Widget _statChip(String label, String value, Color color, IconData icon, String filter) {
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
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)
              ]),
          child: Column(children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(height: 6),
            Text(value,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color)),
            Text(label,
                style: const TextStyle(
                    fontSize: 10, color: Color(0xFF718096))),
          ]),
        ),
      ),
    );
  }

  Widget _stockCard(Map<String, dynamic> item) {
    final status = item['status'] as String;
    final stock = item['stock'] as int;
    final min = item['min'] as int;
    final max = item['max'] as int;
    final isOut  = stock == 0;
    final isLow  = !isOut && status == 'Low';
    final isOver = !isOut && !isLow && status == 'Over';
    final progress = max > 0 ? (stock / max).clamp(0.0, 1.0) : 0.0;
    final barColor = isOut
        ? Colors.red
        : isLow
            ? Colors.orange
            : isOver
                ? Colors.purple
                : Colors.green;
    final statusLabel = isOut
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
          border: isOut
              ? Border.all(color: Colors.red.shade200)
              : isLow
                  ? Border.all(color: Colors.orange.shade200)
                  : isOver
                      ? Border.all(color: Colors.purple.shade200)
                      : null,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.04), blurRadius: 6)
          ],
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(children: [
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(item['name'] as String,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  Text(item['uom'] as String,
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF718096))),
                ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('$stock',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: barColor)),
              Text(statusLabel,
                  style: TextStyle(
                      fontSize: 10,
                      color: barColor,
                      fontWeight: FontWeight.w500)),
            ]),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFFa0aec0)),
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
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
            Text('Min: $min',
                style: const TextStyle(
                    fontSize: 10, color: Color(0xFF718096))),
            Text('$stock / $max',
                style: TextStyle(
                    fontSize: 10,
                    color: barColor,
                    fontWeight: FontWeight.w500)),
            Text('Max: $max',
                style: const TextStyle(
                    fontSize: 10, color: Color(0xFF718096))),
          ]),
        ]),
      ),
    );
  }




  void _showStockDetails(Map<String, dynamic> item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.85,
        builder: (_, ctrl) => SingleChildScrollView(
          controller: ctrl,
          child: Column(children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              decoration: const BoxDecoration(
                  color: _red,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(24))),
              child: Row(children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                  Text(item['name'] as String,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  Text(item['uom'] as String,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12)),
                ])),
                GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.close, color: Colors.white)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                FutureBuilder<String>(
                  future: _resolveSupplierCode(item),
                  builder: (_, snap) => _detailRow('Supplier Item Code',
                    snap.connectionState == ConnectionState.done ? (snap.data ?? '—') : '…'),
                ),
                _detailRow('Item Name', item['name'] as String),
                _detailRow('Commodity Group', item['group'] as String),
                _detailRow('UOM', item['uom'] as String),
                _detailRow(
                    'Current Stock', '${item['stock']}'),
                _detailRow('Min Level', '${item['min']}'),
                _detailRow('Max Level', '${item['max']}'),
                _detailRow(
                    'Reorder Qty', '${item['reorder']}'),
                _detailRow('Status', item['stock'] == 0 ? 'Out of Stock' : item['status'] == 'OK' ? 'In Stock' : item['status'] == 'Over' ? 'Over Max' : 'Low Stock'),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                      child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _showAddStockModal(item: item);
                    },
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Edit'),
                  )),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }


  void _showAddStockModal({Map<String, dynamic>? item}) {
    if (item != null) {
      _showEditStockModal(item);
      return;
    }
    _showNewStockModal();
  }

  void _showEditStockModal(Map<String, dynamic> item) {
    final stockCtrl = TextEditingController(text: '${item['stock']}');
    final minCtrl   = TextEditingController(text: '${item['min']}');
    final maxCtrl   = TextEditingController(text: '${item['max']}');
    final reorderCtrl = TextEditingController(text: '${item['reorder']}');

    // Auto-calculate reorder = max - current stock
    void calcReorder() {
      final stock = int.tryParse(stockCtrl.text) ?? 0;
      final max = int.tryParse(maxCtrl.text) ?? 0;
      final r = max > stock ? max - stock : 0;
      reorderCtrl.text = r > 0 ? '$r' : '';
    }
    minCtrl.addListener(calcReorder);
    maxCtrl.addListener(calcReorder);
    stockCtrl.addListener(calcReorder);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      isDismissible: true,
      enableDrag: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, _) => AnimatedPadding(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                decoration: const BoxDecoration(
                    color: _red,
                    borderRadius: BorderRadius.vertical(
                        top: Radius.circular(24))),
                child: Row(children: [
                  const Expanded(
                      child: Text('Edit Stock Item',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold))),
                  GestureDetector(
                      onTap: () => Navigator.pop(sheetCtx),
                      child:
                          const Icon(Icons.close, color: Colors.white)),
                ]),
              ),
              // Form
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(20, 20, 20, 32),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        color: const Color(0xFFF7F8FA),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: const Color(0xFFe2e8f0))),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      FutureBuilder<String>(
                        future: _resolveSupplierCode(item),
                        builder: (_, snap) => _infoRow('Supplier Item Code',
                          snap.connectionState == ConnectionState.done ? (snap.data ?? '—') : '…'),
                      ),
                      _infoRow('Item Name', item['name'] as String),
                      _infoRow('Group', item['group'] as String),
                      _infoRow('UOM', item['uom'] as String),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  const Text('Stock Level Settings',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 10),
                  TextField(
                      controller: stockCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Current Quantity *',
                          border: OutlineInputBorder())),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                        child: TextField(
                            controller: minCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: 'Min Level *',
                                border: OutlineInputBorder()))),
                    const SizedBox(width: 10),
                    Expanded(
                        child: TextField(
                            controller: maxCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: 'Max Level *',
                                border: OutlineInputBorder()))),
                  ]),
                  const SizedBox(height: 10),
                  TextField(
                      controller: reorderCtrl,
                      keyboardType: TextInputType.number,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'Reorder Quantity (auto)',
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: const Color(0xFFF7F8FA),
                        suffixIcon: Tooltip(
                          message: 'Auto-calculated: Max − Current Stock',
                          child: Icon(Icons.info_outline, size: 16, color: Colors.grey.shade400),
                        ),
                      )),
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(
                        child: OutlinedButton(
                            onPressed: () =>
                                Navigator.pop(sheetCtx),
                            child: const Text('Cancel'))),
                    const SizedBox(width: 12),
                    Expanded(
                        child: ElevatedButton(
                      onPressed: () async {
                        final stock =
                            int.tryParse(stockCtrl.text) ?? 0;
                        final min =
                            int.tryParse(minCtrl.text) ?? 0;
                        final max =
                            int.tryParse(maxCtrl.text) ?? 0;
                        final reorder =
                            int.tryParse(reorderCtrl.text) ?? 0;
                        try {
                          await SyncStatusNotifier.instance.trackWrite(() => _db
                              .doc(item['id'] as String)
                              .update({
                            'stock': stock,
                            'min': min,
                            'max': max,
                            'reorder': reorder,
                            'status':
                                stock > min ? 'OK' : 'Low',
                            'updatedAt':
                                FieldValue.serverTimestamp(),
                          }));
                          if (sheetCtx.mounted) {
                            Navigator.pop(sheetCtx);
                            ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(
                              content: Row(children: const [
                                Icon(
                                    Icons.check_circle_outline,
                                    color: Colors.white,
                                    size: 18),
                                SizedBox(width: 8),
                                Text(
                                    'Stock updated successfully!')
                              ]),
                              backgroundColor: Colors.green,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(10)),
                            ));
                          }
                        } catch (e) {
                          if (sheetCtx.mounted) {
                            ScaffoldMessenger.of(sheetCtx)
                                .showSnackBar(SnackBar(
                                    content: Text('Error: $e'),
                                    backgroundColor: Colors.red));
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _red,
                          foregroundColor: Colors.white),
                      child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                        Icon(Icons.save_outlined, size: 16),
                        SizedBox(width: 6),
                        Text('Update'),
                      ]),
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


  void _showNewStockModal() {
    _showNewStockModalWithItem();
  }

  void _showNewStockModalWithItem({
    String? itemNum,
    String? itemName,
    String? group,
    String? uom,
    String? supplierCode,
  }) {
    final scanCtrl = TextEditingController();
    final stockCtrl = TextEditingController();
    final minCtrl = TextEditingController();
    final maxCtrl = TextEditingController();
    final reorderCtrl = TextEditingController();

    // Auto-calculate reorder qty = max - current stock whenever either changes
    void _calcReorder() {
      final stock = int.tryParse(stockCtrl.text) ?? 0;
      final max = int.tryParse(maxCtrl.text) ?? 0;
      final reorder = max > stock ? max - stock : 0;
      reorderCtrl.text = reorder > 0 ? '$reorder' : '';
    }
    minCtrl.addListener(_calcReorder);
    maxCtrl.addListener(_calcReorder);
    stockCtrl.addListener(_calcReorder);
    Map<String, dynamic>? selectedMaster;
    List<Map<String, dynamic>> searchResults = [];
    bool searching = false;
    bool searched = false;
    bool _isServiceSearchResult = false;
    Timer? _debounce;
    Future<QuerySnapshot>? _dupCheckFuture;
    bool saving = false;

    // Pre-select item if navigated from Item Master — use passed supplierCode directly
    if (itemNum != null && itemNum.isNotEmpty) {
      selectedMaster = {
        'id':           '',
        'num':          itemNum,
        'supplierCode': supplierCode ?? '',
        'name':         itemName ?? '',
        'group':        group    ?? '',
        'uom':          uom      ?? '',
        'barcode':      '',
        'qr':           '',
      };
      _dupCheckFuture = _db.where('num', isEqualTo: itemNum).limit(1).get();
    }

    Future<void> doSearch(String query, StateSetter setModal) async {
      if (query.trim().isEmpty) {
        setModal(() { searching = false; searched = false; searchResults = []; });
        return;
      }
      setModal(() { searching = true; searched = false; selectedMaster = null; searchResults = []; });
      final results = await _searchItemMaster(query);
      // Check if the empty result is because of a service/AutoService match
      bool isServiceMatch = false;
      if (results.isEmpty) {
        final q2 = query.trim().toLowerCase();
        final allDocs = await _masterDb.get();
        isServiceMatch = allDocs.docs.any((d) {
          final data = d.data() as Map<String, dynamic>;
          final type  = (data['type']  as String? ?? '').toLowerCase();
          final group = (data['group'] as String? ?? '').toLowerCase();
          if (type != 'service' && group != 'autoservice') return false;
          return (data['name']         as String? ?? '').toLowerCase().contains(q2) ||
                 (data['num']          as String? ?? '').toLowerCase().contains(q2) ||
                 (data['supplierCode'] as String? ?? '').toLowerCase().contains(q2);
        });
      }
      setModal(() { searching = false; searched = true; searchResults = results; _isServiceSearchResult = isServiceMatch; });
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) {
          final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
          return Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.92,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                    decoration: const BoxDecoration(
                        color: _red,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                    child: Row(children: [
                      const Expanded(
                          child: Text('Add Stock Item',
                              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
                      GestureDetector(
                          onTap: () => Navigator.pop(ctx),
                          child: const Icon(Icons.close, color: Colors.white)),
                    ]),
                  ),
                  // Scrollable body
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                  Row(children: [
                    Expanded(
                        child: TextField(
                      controller: scanCtrl,
                      decoration: InputDecoration(
                        hintText: 'Search by name, number, supplier code...',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: scanCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  scanCtrl.clear();
                                  setModal(() { selectedMaster = null; searchResults = []; searched = false; searching = false; _isServiceSearchResult = false; });
                                },
                              )
                            : null,
                      ),
                      onChanged: (val) {
                        // Reset selection
                        if (selectedMaster != null) {
                          setModal(() { selectedMaster = null; searchResults = []; searched = false; _isServiceSearchResult = false; });
                        }
                        // Debounce: cancel previous timer, fire after 400ms idle
                        _debounce?.cancel();
                        _debounce = Timer(const Duration(milliseconds: 400), () {
                          doSearch(val, setModal);
                        });
                      },
                      onSubmitted: (val) => doSearch(val, setModal),
                    )),
                    const SizedBox(width: 8),
                    IconButton(
                      style: IconButton.styleFrom(
                          backgroundColor: _red,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.all(10)),
                      icon: const Icon(Icons.qr_code_scanner, color: Colors.white, size: 22),
                      onPressed: () async {
                        final result = await Navigator.push<String>(context,
                          MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()));
                        if (result != null) {
                          scanCtrl.text = result;
                          setModal(() { searching = true; searched = false; selectedMaster = null; searchResults = []; });
                          // For scans, try exact match first then fall back to list
                          final exact = await _findItemMaster(result);
                          if (exact != null) {
                            setModal(() { searching = false; searched = true; searchResults = [exact]; });
                          } else {
                            final results = await _searchItemMaster(result);
                            setModal(() { searching = false; searched = true; searchResults = results; });
                          }
                        }
                      },
                    ),
                  ]),
                  const SizedBox(height: 12),

                  // ── Loading ──
                  if (searching)
                    const Center(child: CircularProgressIndicator()),

                  // ── Search results list (before item is selected) ──
                  if (!searching && searched && selectedMaster == null) ...[
                    if (searchResults.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: _isServiceSearchResult ? const Color(0xFFFFFBEB) : Colors.red.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _isServiceSearchResult ? const Color(0xFFFCD34D) : Colors.red.shade200)),
                        child: Row(children: [
                          Icon(_isServiceSearchResult ? Icons.info_outline : Icons.error_outline,
                              color: _isServiceSearchResult ? const Color(0xFF92400E) : Colors.red, size: 16),
                          const SizedBox(width: 8),
                          Expanded(child: Text(
                            _isServiceSearchResult
                                ? 'Service items and AutoService group items do not require stock tracking.'
                                : 'No item found in Item Master.',
                            style: TextStyle(
                                color: _isServiceSearchResult ? const Color(0xFF92400E) : Colors.red,
                                fontSize: 12),
                          )),
                        ]),
                      )
                    else ...[
                      Text('${searchResults.length} result${searchResults.length == 1 ? '' : 's'} found — tap to select',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF718096))),
                      const SizedBox(height: 8),
                      ...searchResults.map((master) {
                        return FutureBuilder<QuerySnapshot>(
                          future: _db.where('num', isEqualTo: master['num']).limit(1).get(),
                          builder: (ctx, snap) {
                            final inStock = snap.hasData && snap.data!.docs.isNotEmpty;
                            return GestureDetector(
                              onTap: () => setModal(() {
                                selectedMaster = master;
                                _dupCheckFuture = _db.where('num', isEqualTo: master['num']).limit(1).get();
                              }),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                    color: inStock ? const Color(0xFFFFFBEB) : Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: inStock ? const Color(0xFFFCD34D) : const Color(0xFFe2e8f0)),
                                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 4)]),
                                child: Row(children: [
                                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Wrap(
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      spacing: 6,
                                      children: [
                                        Text(master['name'] as String,
                                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF1a202c))),
                                        Text(master['uom'] as String,
                                            style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
                                        if (inStock)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                                color: const Color(0xFFFEF3C7),
                                                borderRadius: BorderRadius.circular(20)),
                                            child: const Text('⚠ Already in Stock',
                                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF92400E))),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${(master['supplierCode'] as String).isNotEmpty ? master['supplierCode'] : master['num']}  •  ${master['group']}',
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF718096)),
                                    ),
                                  ])),
                                  const Icon(Icons.chevron_right, size: 18, color: Color(0xFFa0aec0)),
                                ]),
                              ),
                            );
                          },
                        );
                      }),
                    ],
                  ],

                  // ── Selected item + stock fields ──
                  if (!searching && selectedMaster != null)
                    FutureBuilder<QuerySnapshot>(
                      future: _dupCheckFuture,
                      builder: (ctx, dupSnap) {
                        if (dupSnap.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final alreadyExists = (dupSnap.data?.docs.isNotEmpty) == true;
                        if (alreadyExists) {
                          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                  color: Colors.orange.shade50,
                                  border: Border.all(color: Colors.orange.shade300),
                                  borderRadius: BorderRadius.circular(12)),
                              child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Icon(Icons.warning_amber_outlined, color: Colors.orange, size: 16),
                                  SizedBox(width: 6),
                                  Text('Already in Stock', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.orange, fontSize: 12)),
                                ]),
                                SizedBox(height: 6),
                                Text('This item already exists in stock inventory. Use Edit to update it.',
                                    style: TextStyle(fontSize: 11, color: Colors.orange)),
                              ]),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton(
                              onPressed: () => setModal(() { selectedMaster = null; _dupCheckFuture = null; }),
                              child: const Text('← Back to results'),
                            ),
                          ]);
                        }
                        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          // Item preview card
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                                color: const Color(0xFFf0fff4),
                                border: Border.all(color: const Color(0xFF68d391)),
                                borderRadius: BorderRadius.circular(12)),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                const Icon(Icons.check_circle_outline, color: Colors.green, size: 16),
                                const SizedBox(width: 6),
                                const Expanded(child: Text('Item Selected', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.green, fontSize: 12))),
                                GestureDetector(
                                  onTap: () => setModal(() { selectedMaster = null; _dupCheckFuture = null; }),
                                  child: const Icon(Icons.close, size: 16, color: Color(0xFF718096)),
                                ),
                              ]),
                              const SizedBox(height: 8),
                              _infoRow('Supplier Item Code', (selectedMaster!['supplierCode'] as String? ?? '').isNotEmpty ? selectedMaster!['supplierCode'] as String : selectedMaster!['num'] as String),
                              _infoRow('Item Name', selectedMaster!['name'] as String),
                              _infoRow('Group', selectedMaster!['group'] as String),
                              _infoRow('UOM', selectedMaster!['uom'] as String),
                            ]),
                          ),
                          const SizedBox(height: 14),
                          const Text('Stock Level Settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(height: 10),
                          TextField(
                              controller: stockCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Current Quantity *', border: OutlineInputBorder())),
                          const SizedBox(height: 10),
                          Row(children: [
                            Expanded(child: TextField(
                                controller: minCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'Min Level *', border: OutlineInputBorder()))),
                            const SizedBox(width: 10),
                            Expanded(child: TextField(
                                controller: maxCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'Max Level *', border: OutlineInputBorder()))),
                          ]),
                          const SizedBox(height: 10),
                          TextField(
                              controller: reorderCtrl,
                              keyboardType: TextInputType.number,
                              readOnly: true,
                              decoration: InputDecoration(
                                labelText: 'Reorder Quantity (auto)',
                                border: const OutlineInputBorder(),
                                filled: true,
                                fillColor: const Color(0xFFF7F8FA),
                                suffixIcon: Tooltip(
                                  message: 'Auto-calculated: Max − Current Stock',
                                  child: Icon(Icons.info_outline, size: 16, color: Colors.grey.shade400),
                                ),
                              )),
                          const SizedBox(height: 20),
                          Row(children: [
                            Expanded(child: OutlinedButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Cancel'))),
                            const SizedBox(width: 12),
                            Expanded(child: ElevatedButton(
                              onPressed: saving ? null : () async {
                                final stock = int.tryParse(stockCtrl.text) ?? 0;
                                final min = int.tryParse(minCtrl.text) ?? 0;
                                final max = int.tryParse(maxCtrl.text) ?? 0;
                                final reorder = int.tryParse(reorderCtrl.text) ?? 0;
                                final data = <String, dynamic>{
                                  'num': selectedMaster!['num'],
                                  'name': selectedMaster!['name'],
                                  'group': selectedMaster!['group'],
                                  'uom': selectedMaster!['uom'],
                                  'stock': stock, 'min': min, 'max': max, 'reorder': reorder,
                                  'status': stock > min ? 'OK' : 'Low',
                                  'createdAt': FieldValue.serverTimestamp(),
                                  'updatedAt': FieldValue.serverTimestamp(),
                                };
                                setModal(() => saving = true);
                                try {
                                  final existing = await _db
                                      .where('num', isEqualTo: selectedMaster!['num'])
                                      .limit(1).get();
                                  if (existing.docs.isNotEmpty) {
                                    setModal(() => saving = false);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                        content: Text('Already in stock inventory.'),
                                        backgroundColor: Colors.orange,
                                      ));
                                    }
                                    return;
                                  }
                                  await SyncStatusNotifier.instance.trackWrite(() => _db.add(data));
                                  if (context.mounted) {
                                    // Pop modal + pop stock screen → back to item master
                                    Navigator.pop(context); // close modal
                                    // If this screen was pushed from item master (has prefilled item),
                                    // also pop the stock screen itself to return to item master
                                    if (widget.prefilledItemNum != null && widget.prefilledItemNum!.isNotEmpty) {
                                      Navigator.pop(context);
                                    }
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                      content: Row(children: const [
                                        Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
                                        SizedBox(width: 8),
                                        Text('Added successfully!'),
                                      ]),
                                      backgroundColor: Colors.green,
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ));
                                  }
                                } catch (e) {
                                  setModal(() => saving = false);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                        content: Text('Error: $e'), backgroundColor: Colors.red));
                                  }
                                }
                              },
                              style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white),
                              child: saving
                                  ? const SizedBox(
                                      width: 18, height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Row(mainAxisSize: MainAxisSize.min, children: [
                                      Icon(Icons.save_outlined, size: 16),
                                      SizedBox(width: 6),
                                      Text('Save'),
                                    ]),
                            )),
                          ]),
                        ]);
                      },
                    ),
                  ]),         // closes Column.children (scrollable body)
                ),            // closes SingleChildScrollView
              ),              // closes Flexible
                ],            // closes outer Column.children
              ),              // closes Column
            ),                // closes ConstrainedBox
          );                  // closes Padding / return
        },
      ),
    );
  }


  void _confirmDelete(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Item'),
        content: Text('Delete "${item['name']}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await _db.doc(item['id'] as String).delete();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Row(children: const [
                      Icon(Icons.check_circle_outline,
                          color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text('Deleted successfully!')
                    ]),
                    backgroundColor: Colors.red,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ));
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: Colors.red));
                }
              }
            },
            child:
                const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        SizedBox(
            width: 120,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 11, color: Color(0xFF718096)))),
        Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600))),
      ]),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 140,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF718096),
                    fontWeight: FontWeight.w500))),
        Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1a202c)))),
      ]),
    );
  }
}
