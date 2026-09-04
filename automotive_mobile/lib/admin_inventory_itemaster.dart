import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'barcode_scanner_screen.dart';
import 'admin_inventory_stock.dart';
import 'sync_indicator.dart';

/// Standalone full-screen wrapper (for direct navigation if needed elsewhere).
class AdminInventoryItemMaster extends StatefulWidget {
  const AdminInventoryItemMaster({super.key});

  @override
  State<AdminInventoryItemMaster> createState() => _AdminInventoryItemMasterState();
}

class _AdminInventoryItemMasterState extends State<AdminInventoryItemMaster> {
  static const _red = Color(0xFFE8001C);
  String _sortOrder = 'num_asc';
  final _bodyKey = GlobalKey<AdminInventoryItemMasterBodyState>();

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: _red,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Item Master',
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
              final groupList = _bodyKey.currentState?.groups.isNotEmpty == true
                  ? _bodyKey.currentState!.groups
                  : ['Lubricants', 'Spare Parts', 'Filter', 'AutoService'];
              final currentGroup = _bodyKey.currentState?.groupFilter ?? '';
              return [
                const PopupMenuItem(enabled: false, child: Text('Sort By', style: TextStyle(fontSize: 11, color: Color(0xFF718096), fontWeight: FontWeight.w700))),
                _popItem('sort:num_asc',   'Item No. (Ascending)',  Icons.arrow_upward,    _sortOrder == 'num_asc',   _red),
                _popItem('sort:num_desc',  'Item No. (Descending)', Icons.arrow_downward,  _sortOrder == 'num_desc',  _red),
                _popItem('sort:name_asc',  'Name A → Z',            Icons.sort_by_alpha,   _sortOrder == 'name_asc',  _red),
                _popItem('sort:name_desc', 'Name Z → A',            Icons.sort_by_alpha,   _sortOrder == 'name_desc', _red),
                _popItem('sort:cost_desc', 'Cost ↑ Highest',        Icons.trending_up,     _sortOrder == 'cost_desc', _red),
                _popItem('sort:cost_asc',  'Cost ↓ Lowest',         Icons.trending_down,   _sortOrder == 'cost_asc',  _red),
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
        child: AdminInventoryItemMasterBody(key: _bodyKey, sortOrder: _sortOrder)),
    );
  }
}

/// Embeddable body — used inside AdminInventoryHub's IndexedStack.
class AdminInventoryItemMasterBody extends StatefulWidget {
  final String searchQuery;
  final String sortOrder;
  final String groupFilter;
  final VoidCallback? onStockSaved;
  const AdminInventoryItemMasterBody({super.key, this.searchQuery = '', this.sortOrder = 'num_asc', this.groupFilter = '', this.onStockSaved});

  @override
  AdminInventoryItemMasterBodyState createState() => AdminInventoryItemMasterBodyState();
}

class AdminInventoryItemMasterBodyState extends State<AdminInventoryItemMasterBody>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  static const _red = Color(0xFFE8001C);
  static const _col = 'item_master';

  String _searchQuery = '';
  String _typeFilter = 'all';
  String groupFilter = '';
  List<String> groups = [];
  List<String> uomList = [];

  // ── Issuance stats: itemNum → { avgMonthly, lastMonth } ──
  Map<String, _IssuanceStats> _issuanceStats = {};
  bool _statsLoaded = false;

  CollectionReference get _db => FirebaseFirestore.instance.collection(_col);

  @override
  void initState() {
    super.initState();
    _loadGroups();
    _loadUoms();
    _loadIssuanceStats();
  }

  Future<void> _loadGroups() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('domains').doc('commodity_groups').collection('items')
          .orderBy('name').get();
      final list = snap.docs.map((d) => d['name'] as String).toList();
      if (mounted) setState(() => groups = list.isNotEmpty ? list : ['Lubricants', 'Spare Parts', 'Filter', 'AutoService']);
    } catch (_) {
      if (mounted) setState(() => groups = ['Lubricants', 'Spare Parts', 'Filter', 'AutoService']);
    }
  }

  Future<void> _loadUoms() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('domains').doc('uom').collection('items')
          .orderBy('name').get();
      final list = snap.docs.map((d) => d['name'] as String).toList();
      if (mounted) setState(() => uomList = list.isNotEmpty ? list : ['pcs', 'L', 'set', 'job', 'kg', 'box', 'pair', 'm']);
    } catch (_) {
      if (mounted) setState(() => uomList = ['pcs', 'L', 'set', 'job', 'kg', 'box', 'pair', 'm']);
    }
  }

  // ── Compute avg monthly issuance + last month issuance per itemNum ─────────
  // avgMonthly = total qty ÷ months from first issuance to current month (inclusive)
  // lastMonth  = total qty issued in the previous calendar month
  Future<void> _loadIssuanceStats() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('issuances').get();

      final now = DateTime.now();
      final nowYear  = now.year;
      final nowMonth = now.month; // 1-indexed

      // Previous calendar month (for lastMonth)
      final prevDate = DateTime(nowYear, nowMonth - 1, 1);
      final prevKey  = '${prevDate.year}-${prevDate.month.toString().padLeft(2, '0')}';

      // monthKey → qty per itemNum
      final buckets   = <String, Map<String, double>>{};
      final firstKeys = <String, String>{};

      for (final doc in snap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final num  = (data['itemNum'] as String? ?? '').trim();
        if (num.isEmpty) continue;
        final qty  = double.tryParse(data['qty']?.toString() ?? '0') ?? 0;
        if (qty <= 0) continue;
        final dateStr = data['date'] as String? ?? '';
        final ym = _parseYearMonth(dateStr);
        if (ym == null) continue;
        final key = '${ym.$1}-${ym.$2.toString().padLeft(2, '0')}';
        buckets.putIfAbsent(num, () => {});
        buckets[num]![key] = (buckets[num]![key] ?? 0) + qty;
        if (!firstKeys.containsKey(num) || key.compareTo(firstKeys[num]!) < 0) {
          firstKeys[num] = key;
        }
      }

      final stats = <String, _IssuanceStats>{};
      buckets.forEach((num, monthMap) {
        final totalQty = monthMap.values.fold(0.0, (s, v) => s + v);

        // Span: first issuance month → current month (inclusive)
        final fk = firstKeys[num]!.split('-');
        final firstYear  = int.parse(fk[0]);
        final firstMonth = int.parse(fk[1]); // 1-indexed
        var span = (nowYear - firstYear) * 12 + (nowMonth - firstMonth) + 1;
        if (span < 1) span = 1;

        final avgMonthly = (totalQty / span * 10).roundToDouble() / 10;
        final lastMonth  = monthMap[prevKey] ?? 0.0;

        stats[num] = _IssuanceStats(avgMonthly: avgMonthly, lastMonth: lastMonth);
      });

      if (mounted) setState(() { _issuanceStats = stats; _statsLoaded = true; });
    } catch (_) {
      if (mounted) setState(() => _statsLoaded = true);
    }
  }

  // Returns (year, month 1-indexed) from common date string formats
  (int, int)? _parseYearMonth(String s) {
    if (s.isEmpty) return null;
    // "May 7, 2026" / "May 7 2026"
    final m1 = RegExp(r'^([A-Za-z]{3,})\s+\d+,?\s+(\d{4})').firstMatch(s);
    if (m1 != null) {
      const mo = ['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'];
      final idx = mo.indexOf(m1.group(1)!.substring(0,3).toLowerCase());
      if (idx >= 0) return (int.parse(m1.group(2)!), idx + 1);
    }
    // "1/7/2026"
    final m2 = RegExp(r'^(\d{1,2})/\d{1,2}/(\d{4})').firstMatch(s);
    if (m2 != null) return (int.parse(m2.group(2)!), int.parse(m2.group(1)!));
    // "2026-05-07"
    final m3 = RegExp(r'^(\d{4})-(\d{2})-\d{2}').firstMatch(s);
    if (m3 != null) return (int.parse(m3.group(1)!), int.parse(m3.group(2)!));
    final dt = DateTime.tryParse(s);
    if (dt != null) return (dt.year, dt.month);
    return null;
  }

  // Cache domains so they're only fetched once
  List<String>? _cachedGroups;
  List<String>? _cachedUoms;

  Future<void> _ensureDomainsLoaded() async {
    if (_cachedGroups != null && _cachedUoms != null) return;
    final results = await Future.wait([
      _fetchDomain('commodity_groups'),
      _fetchDomain('uom'),
    ]);
    _cachedGroups = results[0].isNotEmpty ? results[0] : ['Lubricants', 'Spare Parts', 'Filter', 'AutoService'];
    _cachedUoms   = results[1].isNotEmpty ? results[1] : ['pcs', 'L', 'set', 'job', 'kg', 'box', 'pair', 'm'];
    // Also sync to state lists so pickers always have data
    if (mounted) setState(() {
      if (groups.isEmpty) groups = _cachedGroups!;
      if (uomList.isEmpty) uomList = _cachedUoms!;
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<List<String>> _fetchDomain(String key) async {
    final snap = await FirebaseFirestore.instance
        .collection('domains').doc(key).collection('items')
        .orderBy('name').get();
    return snap.docs.map((d) => d['name'] as String).toList();
  }

  Future<String> _nextItemNum() async {
    final snap = await _db.get();
    int maxNum = 0;
    for (final doc in snap.docs) {
      final n = int.tryParse(
        (doc['num'] as String? ?? '').replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      if (n > maxNum) maxNum = n;
    }
    return (maxNum + 1).toString().padLeft(3, '0');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final activeQuery = widget.searchQuery.isNotEmpty ? widget.searchQuery : _searchQuery;
    return Stack(children: [
      StreamBuilder<QuerySnapshot>(
        stream: _db.orderBy('createdAt', descending: true).snapshots(),
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
            // Skip archived items
            if (data['archived'] == true) return null;
            return {
              'id': d.id,
              'num': (data['num'] ?? '—').toString(),
              'supplierCode': (data['supplierCode'] ?? '').toString(),
              'oem': (data['oem'] ?? '').toString(),
              'sku': (data['sku'] ?? '').toString(),
              'name': (data['name'] ?? '—').toString(),
              'desc': (data['desc'] ?? '').toString(),
              'group': (data['group'] ?? '').toString(),
              'uom': (data['uom'] ?? '').toString(),
              'cost': (data['cost'] ?? '₱0').toString(),
              'type': (data['type'] ?? 'Material').toString(),
              'barcode': (data['barcode'] ?? '').toString(),
              'qr': (data['qr'] ?? '').toString(),
            };
          }).whereType<Map<String, String>>().toList();

          // Apply sort
          int numPart(String s) => int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
          double costVal(Map<String, String> i) =>
              double.tryParse((i['cost'] ?? '').replaceAll(RegExp(r'[₱,]'), '').trim()) ?? 0;

          switch (widget.sortOrder) {
            case 'num_desc':
              items.sort((a, b) => numPart(b['num']!).compareTo(numPart(a['num']!)));
              break;
            case 'name_asc':
              items.sort((a, b) => (a['name']!).compareTo(b['name']!));
              break;
            case 'name_desc':
              items.sort((a, b) => (b['name']!).compareTo(a['name']!));
              break;
            case 'group_asc':
              items.sort((a, b) => (a['group']!).compareTo(b['group']!));
              break;
            case 'cost_desc':
              items.sort((a, b) => costVal(b).compareTo(costVal(a)));
              break;
            case 'cost_asc':
              items.sort((a, b) => costVal(a).compareTo(costVal(b)));
              break;
            default: // 'num_asc'
              items.sort((a, b) => numPart(a['num']!).compareTo(numPart(b['num']!)));
              break;
          }

          final filtered = activeQuery.isEmpty
              ? items
              : items.where((i) =>
                  i['name']!.toLowerCase().contains(activeQuery) ||
                  i['num']!.toLowerCase().contains(activeQuery) ||
                  i['group']!.toLowerCase().contains(activeQuery)).toList();

          // Apply type filter
          final afterTypeFilter = _typeFilter == 'all'
              ? filtered
              : filtered.where((i) => i['type'] == _typeFilter).toList();

          // Apply group filter — use widget prop (from hub) if set, else internal
          final activeGroupFilter = widget.groupFilter.isNotEmpty ? widget.groupFilter : groupFilter;
          final afterGroupFilter = activeGroupFilter.isEmpty
              ? afterTypeFilter
              : afterTypeFilter.where((i) => (i['group'] as String) == activeGroupFilter).toList();

          final total = items.length;
          final materials = items.where((i) => i['type'] == 'Material').length;
          final services = items.where((i) => i['type'] == 'Service').length;

          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(children: [
                _statChip('Total Items', '$total', Colors.blue, Icons.list_alt_outlined, 'all'),
                const SizedBox(width: 8),
                _statChip('Materials', '$materials', _red, Icons.inventory_2_outlined, 'Material'),
                const SizedBox(width: 8),
                _statChip('Services', '$services', const Color(0xFF003087), Icons.build_outlined, 'Service'),
              ]),
            ),
            Expanded(
              child: afterGroupFilter.isEmpty
                ? const Center(child: Text('No items found.', style: TextStyle(color: Color(0xFF718096))))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: afterGroupFilter.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _itemCard(afterGroupFilter[i]),
                  ),
            ),
          ]);
        },
      ),
      // FAB
      Positioned(
        bottom: 16, right: 16,
        child: FloatingActionButton(
          heroTag: 'itemmaster_fab',
          onPressed: () => _showAddItemModal(),
          backgroundColor: _red,
          child: const Icon(Icons.add, color: Colors.white, size: 28),
        ),
      ),
    ]);
  }

  Widget _statChip(String label, String value, Color color, IconData icon, String filter) {
    final isActive = _typeFilter == filter;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _typeFilter = _typeFilter == filter ? 'all' : filter),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: isActive ? color.withValues(alpha: 0.08) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isActive ? color : Colors.transparent, width: 1.5),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)]),
          child: Column(children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
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

  Widget _itemCard(Map<String, String> item) {
    final isSvc = item['type'] == 'Service';
    final typeColor = isSvc ? const Color(0xFF003087) : _red;
    final typeBg    = isSvc ? const Color(0xFFebf8ff) : const Color(0xFFFFF5F5);
    final stats     = _issuanceStats[item['num'] ?? ''];
    final avgM      = stats?.avgMonthly ?? 0.0;
    final lastM     = stats?.lastMonth  ?? 0.0;

    return GestureDetector(
      onTap: () => _showItemDetails(item),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
        ),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item['name']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1a202c))),
            const SizedBox(height: 2),
            Text(
              [if (item['group']!.isNotEmpty) item['group']!, if (item['uom']!.isNotEmpty) item['uom']!].join(' • '),
              style: const TextStyle(fontSize: 11, color: Color(0xFF4a5568)),
            ),
            const SizedBox(height: 4),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: typeBg, borderRadius: BorderRadius.circular(20)),
                child: Text(isSvc ? 'Service' : 'Material',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: typeColor)),
              ),
              if ((item['supplierCode'] as String? ?? '').isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(item['supplierCode']!, style: const TextStyle(fontSize: 10, color: Color(0xFF718096))),
              ],
            ]),
            // ── Issuance stats row ──
            if (_statsLoaded && (avgM > 0 || lastM > 0)) ...[
              const SizedBox(height: 6),
              Row(children: [
                _issStatBadge('Avg/mo', avgM > 0 ? _fmtQty(avgM) : '—', const Color(0xFF003087)),
                const SizedBox(width: 6),
                _issStatBadge('Last mo', lastM > 0 ? _fmtQty(lastM) : '—', const Color(0xFF718096)),
              ]),
            ],
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_fmtCost(item['cost']!),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1a202c))),
          ]),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right, size: 18, color: Color(0xFFa0aec0)),
        ]),
      ),
    );
  }

  Widget _issStatBadge(String label, String value, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: TextStyle(fontSize: 9, color: color.withValues(alpha: 0.8), fontWeight: FontWeight.w600)),
      const SizedBox(width: 4),
      Text(value, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    ]),
  );

  String _fmtQty(double v) {
    if (v == v.truncateToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(1);
  }

  void _showItemDetails(Map<String, String> item) {
    final isSvc = item['type'] == 'Service';
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => DraggableScrollableSheet(
        expand: false, initialChildSize: 0.6, maxChildSize: 0.9,
        builder: (_, ctrl) => SingleChildScrollView(
          controller: ctrl,
          child: Column(children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              decoration: BoxDecoration(
                color: isSvc ? const Color(0xFF003087) : _red,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item['name']!, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(item['uom'] ?? '—', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ])),
                GestureDetector(onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close, color: Colors.white)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _detailRow('Item Number', item['num'] ?? '—'),
                if ((item['supplierCode'] as String? ?? '').isNotEmpty)
                  _detailRow('Supplier Item Code', item['supplierCode']!),
                if ((item['oem'] as String? ?? '').isNotEmpty)
                  _detailRow('OEM', item['oem']!),
                _detailRow('Item Name', item['name'] ?? '—'),
                _detailRow('Commodity Group', item['group']?.isNotEmpty == true ? item['group']! : '—'),
                _detailRow('UOM', item['uom']?.isNotEmpty == true ? item['uom']! : '—'),
                _detailRow('Cost', _fmtCost(item['cost'] ?? '')),
                _detailRow('Type', item['type'] ?? '—'),
                // ── Issuance stats ──
                Builder(builder: (_) {
                  final stats  = _issuanceStats[item['num'] ?? ''];
                  final avgM   = stats?.avgMonthly ?? 0.0;
                  final lastM  = stats?.lastMonth  ?? 0.0;
                  if (!_statsLoaded) return const SizedBox.shrink();
                  return Column(children: [
                    const Divider(height: 20),
                    Row(children: [
                      Expanded(child: _issStatCard(
                        'Avg Monthly Issuance',
                        avgM > 0 ? _fmtQty(avgM) : '—',
                        Icons.trending_up_outlined,
                        const Color(0xFF003087),
                      )),
                      const SizedBox(width: 10),
                      Expanded(child: _issStatCard(
                        'Last Month Issuance',
                        lastM > 0 ? _fmtQty(lastM) : '—',
                        Icons.calendar_month_outlined,
                        const Color(0xFF718096),
                      )),
                    ]),
                  ]);
                }),
                const SizedBox(height: 16),
                // Barcode + QR buttons (Material only, and only when supplierCode exists)
                if (!isSvc && (item['supplierCode'] ?? '').trim().isNotEmpty) ...[
                  Row(children: [
                    Expanded(child: OutlinedButton.icon(
                      onPressed: () => _showOrGenerateBarcode(item),
                      icon: const Icon(Icons.qr_code_2, size: 16),
                      label: const Text('Barcode'),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: OutlinedButton.icon(
                      onPressed: () => _showOrGenerateQR(item),
                      icon: const Icon(Icons.qr_code, size: 16),
                      label: const Text('QR Code'),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                    )),
                  ]),
                  const SizedBox(height: 10),
                ],
                Row(children: [
                  Expanded(child: OutlinedButton.icon(
                    onPressed: () { Navigator.pop(context); _showAddItemModal(item: item); },
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Edit'),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: OutlinedButton.icon(
                    onPressed: () { Navigator.pop(context); _confirmDelete(item); },
                    icon: const Icon(Icons.archive_outlined, size: 16, color: Colors.orange),
                    label: const Text('Archive', style: TextStyle(color: Colors.orange)),
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.orange)),
                  )),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Show existing or generate + save barcode ──
  void _showOrGenerateBarcode(Map<String, String> item) async {
    String barcodeVal = item['barcode'] ?? '';

    if (barcodeVal.isEmpty) {
      // Generate random valid EAN-13
      final rnd = DateTime.now().microsecondsSinceEpoch;
      final digits = List.generate(12, (i) => ((rnd * (i + 7) + i * 13) % 10).abs());
      int sum = 0;
      for (int j = 0; j < 12; j++) sum += digits[j] * (j.isEven ? 1 : 3);
      digits.add((10 - (sum % 10)) % 10);
      barcodeVal = digits.join('');
      // Save to Firestore
      try {
        await _db.doc(item['id']).update({'barcode': barcodeVal});
        item['barcode'] = barcodeVal;
      } catch (e) {
        debugPrint('Barcode save error: $e');
      }
    }

    if (!mounted) return;
    _showScanCodeModal(item['name'] ?? '', item['uom'] ?? '', barcodeVal, isBarcode: true, codeLabel: item['supplierCode']?.isNotEmpty == true ? item['supplierCode']! : (item['num'] ?? ''));
  }

  // ── Show existing or generate + save QR code ──
  void _showOrGenerateQR(Map<String, String> item) async {
    String qrVal = item['qr'] ?? '';
    final supplierCode = item['supplierCode'] ?? item['num'] ?? '';

    if (qrVal.isEmpty) {
      qrVal = 'QR-${supplierCode.toUpperCase()}';
      try {
        await _db.doc(item['id']).update({'qr': qrVal});
        item['qr'] = qrVal;
      } catch (e) {
        debugPrint('QR save error: $e');
      }
    }

    if (!mounted) return;
    _showScanCodeModal(item['name'] ?? '', item['uom'] ?? '', qrVal, isBarcode: false, codeLabel: supplierCode.isNotEmpty ? supplierCode : (item['num'] ?? ''));
  }

  void _showScanCodeModal(String name, String subtitle, String value, {required bool isBarcode, String? codeLabel}) {
    final labelBelow = codeLabel ?? subtitle;
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
        // Header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          decoration: const BoxDecoration(
            color: _red,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              if (subtitle.isNotEmpty)
                Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ])),
            GestureDetector(onTap: () => Navigator.pop(context),
              child: const Icon(Icons.close, color: Colors.white)),
          ]),
        ),
        // Image
        Padding(
          padding: const EdgeInsets.all(20),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFe2e8f0)),
              borderRadius: BorderRadius.circular(14)),
            child: isBarcode
                ? Column(children: [
                    BarcodeWidget(
                      barcode: Barcode.code128(),
                      data: value,
                      width: double.infinity,
                      height: 80,
                      drawText: false,
                      errorBuilder: (ctx, err) => Text(value,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFF718096))),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      labelBelow,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        letterSpacing: 2,
                        color: Color(0xFF1a202c),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ])
                : Column(children: [
                    Center(
                      child: QrImageView(
                        data: value,
                        version: QrVersions.auto,
                        size: 180,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      labelBelow, // supplier code shown below QR
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        letterSpacing: 1.5,
                        color: Color(0xFF1a202c),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ]),
          ),
        ),
      ]),
    );
  }

  String _fmtCost(String raw) {
    final clean = raw.replaceAll('₱', '').replaceAll(',', '').trim();
    final val = double.tryParse(clean);
    if (val == null || clean.isEmpty) return '₱0.00';
    // Format integer part with comma separators
    final intPart = val.truncate();
    final decPart = ((val - intPart) * 100).round().toString().padLeft(2, '0');
    final intStr = intPart.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < intStr.length; i++) {
      if (i > 0 && (intStr.length - i) % 3 == 0) buffer.write(',');
      buffer.write(intStr[i]);
    }
    return '₱$buffer.$decPart';
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 130, child: Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF718096), fontWeight: FontWeight.w500))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1a202c)))),
      ]),
    );
  }

  Widget _issStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Expanded(child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
      ]),
    );
  }

  void _showAddItemModal({Map<String, String>? item}) async {
    final isEdit = item != null;

    // Load domains once (cached after first load)
    await _ensureDomainsLoaded();
    if (!mounted) return;

    // Use state-level lists (always fresh from Firestore, never empty)
    final groupOptions = this.groups.isNotEmpty ? this.groups : (_cachedGroups ?? ['Lubricants', 'Spare Parts', 'Filter', 'AutoService']);
    final uomOptions   = this.uomList.isNotEmpty ? this.uomList : (_cachedUoms ?? ['pcs', 'L', 'set', 'job', 'kg', 'box', 'pair', 'm']);

    // Auto-generate item number for new items
    String newItemNum = '';
    if (!isEdit) {
      newItemNum = await _nextItemNum();
      if (!mounted) return;
    }

    final nameCtrl = TextEditingController(text: item?['name'] ?? '');
    final descCtrl = TextEditingController(text: item?['desc'] ?? '');
    final supplierCodeCtrl = TextEditingController(text: item?['supplierCode'] ?? '');
    final oemCtrl = TextEditingController(text: item?['oem'] ?? '');
    final costCtrl = TextEditingController(text: item?['cost']?.replaceAll('₱', '').replaceAll(',', '') ?? '');
    String selectedType = item?['type'] ?? 'Material';
    String? selectedGroup = (item?['group']?.isNotEmpty == true && groupOptions.contains(item!['group'])) ? item['group'] : null;
    String? selectedUom   = (item?['uom']?.isNotEmpty   == true && uomOptions.contains(item!['uom']))     ? item['uom']   : null;
    // Auto-apply AutoService → Service rule on modal open
    if (selectedGroup == 'AutoService') selectedType = 'Service';
    bool saving = false;
    bool nameDuplicate = false;

    // All existing name+uom combinations (lowercased) for live duplicate check
    // Same name with different UOM is allowed
    final existingNames = (await _db.get()).docs
        .where((d) => isEdit ? d.id != item!['id'] : true)
        .map((d) {
          final name = (d['name'] as String? ?? '').toLowerCase().trim();
          final uom  = (d['uom']  as String? ?? '').toLowerCase().trim();
          return '$name||$uom';
        })
        .toSet();

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                decoration: const BoxDecoration(color: _red,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                child: Row(children: [
                  Expanded(child: Text(isEdit ? 'Edit Item' : 'Add Item',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
                  GestureDetector(onTap: () => Navigator.pop(ctx),
                    child: const Icon(Icons.close, color: Colors.white)),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  TextField(controller: supplierCodeCtrl,
                    decoration: InputDecoration(
                      labelText: 'Supplier Item Code',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.qr_code_scanner, size: 18, color: Color(0xFF003087)),
                        tooltip: 'Scan barcode / QR code',
                        onPressed: () async {
                          final result = await Navigator.push<String>(ctx,
                            MaterialPageRoute(builder: (_) => const BarcodeScannerScreen(
                              title: 'Scan Supplier Code',
                              hint: 'Point camera at barcode or QR code',
                            )));
                          if (result != null && result.isNotEmpty) {
                            supplierCodeCtrl.text = result;
                            setModalState(() {});
                          }
                        },
                      ),
                    )),
                  const SizedBox(height: 10),
                  TextField(controller: oemCtrl,
                    decoration: const InputDecoration(
                      labelText: 'OEM',
                      border: OutlineInputBorder(),
                    )),
                  const SizedBox(height: 10),
                  // Item Number is auto-generated — not shown in modal
                  TextField(controller: nameCtrl,
                    onChanged: (v) {
                      final key = '${v.trim().toLowerCase()}||${(selectedUom ?? '').toLowerCase().trim()}';
                      final isDup = existingNames.contains(key);
                      if (isDup != nameDuplicate) setModalState(() => nameDuplicate = isDup);
                    },
                    decoration: const InputDecoration(
                      labelText: 'Item Name *',
                      border: OutlineInputBorder(),
                    )),
                  const SizedBox(height: 10),
                  TextField(controller: descCtrl,
                    decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder())),
                  const SizedBox(height: 10),
                  // Commodity Group — GestureDetector-based picker avoids scroll conflict
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () async {
                      final groupList = groupOptions.isNotEmpty
                          ? groupOptions
                          : ['Lubricants', 'Filters', 'Spare Parts', 'AutoService'];
                      final picked = await showModalBottomSheet<String>(
                        context: ctx,
                        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                        builder: (sheetCtx) => Column(mainAxisSize: MainAxisSize.min, children: [
                          const Padding(
                            padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                            child: Text('Select Commodity Group', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                          ),
                          const Divider(height: 1),
                          Flexible(
                            child: ListView(
                              shrinkWrap: true,
                              children: groupList.map((g) => ListTile(
                                title: Text(g),
                                trailing: selectedGroup == g ? const Icon(Icons.check, color: Color(0xFFE8001C)) : null,
                                onTap: () => Navigator.pop(sheetCtx, g),
                              )).toList(),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ]),
                      );
                      if (picked != null) setModalState(() {
                        selectedGroup = picked;
                        // Auto-set type: AutoService group → Service, others → Material
                        if (picked == 'AutoService') {
                          selectedType = 'Service';
                        } else if (selectedType == 'Service' && picked != 'AutoService') {
                          selectedType = 'Material';
                        }
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFbdbdbd)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(children: [
                        Expanded(child: Text(
                          selectedGroup ?? 'Select group',
                          style: TextStyle(
                            fontSize: 16,
                            color: selectedGroup != null ? const Color(0xFF1a202c) : const Color(0xFF9e9e9e),
                          ),
                        )),
                        const Icon(Icons.arrow_drop_down, color: Color(0xFF718096)),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // UOM — GestureDetector-based picker avoids scroll conflict
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () async {
                      // Ensure list is never empty — fallback to seeds
                      final uomList = uomOptions.isNotEmpty
                          ? uomOptions
                          : ['pcs', 'L', 'set', 'job', 'kg', 'box', 'pair', 'm'];
                      final picked = await showModalBottomSheet<String>(
                        context: ctx,
                        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                        builder: (sheetCtx) => Column(mainAxisSize: MainAxisSize.min, children: [
                          const Padding(
                            padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                            child: Text('Select UOM', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                          ),
                          const Divider(height: 1),
                          Flexible(
                            child: ListView(
                              shrinkWrap: true,
                              children: uomList.map((u) => ListTile(
                                title: Text(u),
                                trailing: selectedUom == u ? const Icon(Icons.check, color: Color(0xFFE8001C)) : null,
                                onTap: () => Navigator.pop(sheetCtx, u),
                              )).toList(),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ]),
                      );
                      if (picked != null) setModalState(() {
                        selectedUom = picked;
                        // Re-check duplicate with new UOM
                        final key = '${nameCtrl.text.trim().toLowerCase()}||${picked.toLowerCase().trim()}';
                        nameDuplicate = existingNames.contains(key);
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFbdbdbd)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(children: [
                        Expanded(child: Text(
                          selectedUom ?? 'Select UOM',
                          style: TextStyle(
                            fontSize: 16,
                            color: selectedUom != null ? const Color(0xFF1a202c) : const Color(0xFF9e9e9e),
                          ),
                        )),
                        const Icon(Icons.arrow_drop_down, color: Color(0xFF718096)),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: TextField(controller: costCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Cost (₱)', border: OutlineInputBorder(), prefixText: '₱'))),
                    const SizedBox(width: 10),
                    Expanded(child: DropdownButtonFormField<String>(
                      value: selectedType,
                      decoration: InputDecoration(
                        labelText: 'Type',
                        border: const OutlineInputBorder(),
                        filled: selectedGroup == 'AutoService',
                        fillColor: selectedGroup == 'AutoService' ? const Color(0xFFF7F8FA) : null,
                        suffixIcon: selectedGroup == 'AutoService'
                          ? const Tooltip(
                              message: 'Auto-set to Service for AutoService group',
                              child: Icon(Icons.lock_outline, size: 16, color: Color(0xFF718096)))
                          : null,
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Material', child: Text('Material')),
                        DropdownMenuItem(value: 'Service', child: Text('Service')),
                      ],
                      onChanged: selectedGroup == 'AutoService' ? null : (v) => setModalState(() => selectedType = v!),
                    )),
                  ]),
                  if (selectedType == 'Material') ...[
                    const SizedBox(height: 10),
                    // (barcode and QR are derived from supplier item code)
                  ],
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel'))),
                    const SizedBox(width: 12),
                    Expanded(child: ElevatedButton(
                      onPressed: saving ? null : () async {
                        if (nameCtrl.text.trim().isEmpty) return;
                        if (nameDuplicate) {
                          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                            content: Text('An item with this name and UOM already exists.'),
                            backgroundColor: Colors.orange,
                            behavior: SnackBarBehavior.floating,
                          ));
                          return;
                        }
                        setModalState(() => saving = true);

                        final data = <String, dynamic>{
                          'num': isEdit ? (item!['num'] ?? '') : newItemNum,
                          'supplierCode': supplierCodeCtrl.text.trim(),
                          'oem': oemCtrl.text.trim(),
                          'name': nameCtrl.text.trim(),
                          'desc': descCtrl.text.trim(),
                          'group': selectedGroup ?? '',
                          'uom': selectedUom ?? '',
                          'cost': '₱${costCtrl.text.trim()}',
                          'type': selectedType,
                          'barcode': selectedType == 'Material' ? supplierCodeCtrl.text.trim() : '',
                          'qr': selectedType == 'Material' ? supplierCodeCtrl.text.trim() : '',
                        };
                        try {
                          if (isEdit) {
                            await SyncStatusNotifier.instance.trackWrite(() async {
                              await _db.doc(item!['id']).update(data);
                            });
                            // ── Sync matching stock_inventory record ──
                            try {
                              final oldNum = item['num'] as String? ?? '';
                              final newNum = data['num'] as String? ?? oldNum;
                              if (oldNum.isNotEmpty) {
                                final stockSnap = await FirebaseFirestore.instance
                                    .collection('stock_inventory')
                                    .where('num', isEqualTo: oldNum)
                                    .limit(1).get();
                                if (stockSnap.docs.isNotEmpty) {
                                  final stockSync = <String, dynamic>{
                                    'num':          newNum.isNotEmpty ? newNum : oldNum,
                                    'supplierCode': data['supplierCode'] ?? '',
                                    'name':         data['name'] ?? '',
                                    'group':        data['group'] ?? '',
                                    'uom':          data['uom'] ?? '',
                                    'updatedAt':    FieldValue.serverTimestamp(),
                                  };
                                  await stockSnap.docs.first.reference.update(stockSync);
                                }
                              }
                            } catch (syncErr) {
                              debugPrint('Stock sync error: $syncErr');
                            }
                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Row(children: const [Icon(Icons.check_circle_outline, color: Colors.white, size: 18), SizedBox(width: 8), Text('Updated successfully!')]),
                                backgroundColor: Colors.green, behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
                            }
                          } else {
                            data['createdAt'] = FieldValue.serverTimestamp();
                            await SyncStatusNotifier.instance.trackWrite(() => _db.add(data));
                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Row(children: const [Icon(Icons.check_circle_outline, color: Colors.white, size: 18), SizedBox(width: 8), Text('Added successfully!')]),
                                backgroundColor: Colors.green, behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
                              // For Material items (excluding AutoService group) — navigate to Stock to set levels
                              if (selectedType == 'Material' && (selectedGroup ?? '') != 'AutoService' && context.mounted) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => AdminInventoryStock(
                                      prefilledItemNum:      newItemNum,
                                      prefilledItemName:     nameCtrl.text.trim(),
                                      prefilledGroup:        selectedGroup        ?? '',
                                      prefilledUom:          selectedUom          ?? '',
                                      prefilledSupplierCode: supplierCodeCtrl.text.trim(),
                                    ),
                                  ),
                                );
                              }
                            }
                          }
                        } catch (e) {
                          setModalState(() => saving = false);
                          if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                        }
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white),
                      child: saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.save_outlined, size: 16),
                            const SizedBox(width: 6),
                            Text(isEdit ? 'Update' : 'Save'),
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

  void _showSetStockModal(String itemNum, String itemName, String group, String uom) {
    final stockCtrl = TextEditingController();
    final minCtrl = TextEditingController();
    final maxCtrl = TextEditingController();
    final reorderCtrl = TextEditingController();
    bool savingStock = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSave) => AnimatedPadding(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                decoration: const BoxDecoration(color: Color(0xFF003087),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                child: Row(children: [
                  const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Set Stock Levels', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    Text('Configure inventory levels for this item', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ])),
                  GestureDetector(onTap: () => Navigator.pop(sheetCtx),
                    child: const Icon(Icons.close, color: Colors.white)),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Item info
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF68d391)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(itemName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        Text('$itemNum • $group • $uom', style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
                      ])),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  const Text('Stock Level Settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 10),
                  TextField(controller: stockCtrl, keyboardType: TextInputType.number, autofocus: true,
                    decoration: const InputDecoration(labelText: 'Current Quantity *', border: OutlineInputBorder())),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: TextField(controller: minCtrl, keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Min Level *', border: OutlineInputBorder()))),
                    const SizedBox(width: 10),
                    Expanded(child: TextField(controller: maxCtrl, keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Max Level *', border: OutlineInputBorder()))),
                  ]),
                  const SizedBox(height: 10),
                  TextField(controller: reorderCtrl, keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Reorder Quantity *', border: OutlineInputBorder())),
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(child: OutlinedButton(
                      onPressed: () => Navigator.pop(sheetCtx),
                      child: const Text('Skip'))),
                    const SizedBox(width: 12),
                    Expanded(child: ElevatedButton(
                      onPressed: savingStock ? null : () async {
                        final stock = int.tryParse(stockCtrl.text) ?? 0;
                        final min = int.tryParse(minCtrl.text) ?? 0;
                        final max = int.tryParse(maxCtrl.text) ?? 0;
                        final reorder = int.tryParse(reorderCtrl.text) ?? 0;
                        setSave(() => savingStock = true);
                        try {
                          final existing = await FirebaseFirestore.instance
                              .collection('stock_inventory')
                              .where('num', isEqualTo: itemNum)
                              .limit(1).get();
                          if (existing.docs.isNotEmpty) {
                            await existing.docs.first.reference.update({
                              'stock': stock, 'min': min, 'max': max, 'reorder': reorder,
                              'status': stock > min ? 'OK' : 'Low',
                              'updatedAt': FieldValue.serverTimestamp(),
                            });
                          } else {
                            await FirebaseFirestore.instance.collection('stock_inventory').add({
                              'num': itemNum,
                              'name': itemName,
                              'group': group,
                              'uom': uom,
                              'stock': stock, 'min': min, 'max': max, 'reorder': reorder,
                              'status': stock > min ? 'OK' : 'Low',
                              'createdAt': FieldValue.serverTimestamp(),
                              'updatedAt': FieldValue.serverTimestamp(),
                            });
                          }
                          if (sheetCtx.mounted) {
                            Navigator.pop(sheetCtx);
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Row(children: const [
                                Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
                                SizedBox(width: 8),
                                Text('Added successfully!'),
                              ]),
                              backgroundColor: Colors.green, behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
                            // Switch to Stock tab
                            widget.onStockSaved?.call();
                          }
                        } catch (e) {
                          setSave(() => savingStock = false);
                          if (sheetCtx.mounted) ScaffoldMessenger.of(sheetCtx).showSnackBar(
                            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                        }
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF003087), foregroundColor: Colors.white),
                      child: savingStock
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.save_outlined, size: 16),
                            SizedBox(width: 6),
                            Text('Save Stock'),
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

  void _confirmDelete(Map<String, String> item) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.archive_outlined, color: Colors.orange, size: 22),
          SizedBox(width: 8),
          Text('Archive Item', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
        content: Text(
          'Are you sure you want to archive "${item['name']}"?',
          style: const TextStyle(fontSize: 14, color: Color(0xFF4a5568)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF718096))),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                final docId = item['id']!;
                // Fetch full doc then move to archive sub-collection
                final snap = await _db.doc(docId).get();
                if (!snap.exists) throw Exception('Item not found');
                final data = Map<String, dynamic>.from(snap.data() as Map<String, dynamic>);
                data['archivedAt'] = FieldValue.serverTimestamp();
                await SyncStatusNotifier.instance.trackWrite(() =>
                    FirebaseFirestore.instance
                        .collection('archive')
                        .doc('item_master')
                        .collection('items')
                        .doc(docId)
                        .set(data));
                await SyncStatusNotifier.instance.trackWrite(() => _db.doc(docId).delete());
                // Delete matching stock_inventory doc
                final num = item['num'] as String? ?? '';
                if (num.isNotEmpty) {
                  final stockSnap = await FirebaseFirestore.instance
                      .collection('stock_inventory').where('num', isEqualTo: num).limit(1).get();
                  if (stockSnap.docs.isNotEmpty) {
                    await stockSnap.docs.first.reference.delete().catchError((_) {});
                  }
                }
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Row(children: const [Icon(Icons.inventory_2_outlined, color: Colors.white, size: 18), SizedBox(width: 8), Text('Item archived successfully!')]),
                  backgroundColor: Colors.orange, behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Yes, Archive'),
          ),
        ],
      ),
    );
  }
}

// ── Issuance stats model ─────────────────────────────────────────────────────
class _IssuanceStats {
  final double avgMonthly; // total qty ÷ months from first issuance to now
  final double lastMonth;  // qty issued in the previous calendar month
  const _IssuanceStats({required this.avgMonthly, required this.lastMonth});
}
