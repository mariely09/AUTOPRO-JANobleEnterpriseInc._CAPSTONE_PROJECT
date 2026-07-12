import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'barcode_scanner_screen.dart';

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
      body: AdminInventoryItemMasterBody(key: _bodyKey, sortOrder: _sortOrder),
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

  CollectionReference get _db => FirebaseFirestore.instance.collection(_col);

  @override
  void initState() {
    super.initState();
    _loadGroups();
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

  // Cache domains so they're only fetched once
  List<String>? _cachedGroups;
  List<String>? _cachedUoms;

  Future<void> _ensureDomainsLoaded() async {
    if (_cachedGroups != null && _cachedUoms != null) return;
    final results = await Future.wait([
      _fetchDomain('commodity_groups'),
      _fetchDomain('uom'),
    ]);
    _cachedGroups = results[0];
    _cachedUoms = results[1];
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
    final snap = await _db.orderBy('createdAt', descending: true).limit(1).get();
    if (snap.docs.isEmpty) return 'ITM-001';
    final last = snap.docs.first['num'] as String? ?? 'ITM-000';
    final n = int.tryParse(last.replaceAll('ITM-', '')) ?? 0;
    return 'ITM-${(n + 1).toString().padLeft(3, '0')}';
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
            return {
              'id': d.id,
              'num': (data['num'] ?? '—').toString(),
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
          }).toList();

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
              const SizedBox(width: 6),
              Text(item['num']!, style: const TextStyle(fontSize: 10, color: Color(0xFF718096))),
            ]),
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
                if (!isSvc && (item['sku']?.isNotEmpty == true))
                  _detailRow('SKU', item['sku']!),
                _detailRow('Item Name', item['name'] ?? '—'),
                _detailRow('Description', item['desc']?.isNotEmpty == true ? item['desc']! : '—'),
                _detailRow('Commodity Group', item['group']?.isNotEmpty == true ? item['group']! : '—'),
                _detailRow('UOM', item['uom']?.isNotEmpty == true ? item['uom']! : '—'),
                _detailRow('Cost', _fmtCost(item['cost'] ?? '')),
                _detailRow('Type', item['type'] ?? '—'),
                const SizedBox(height: 16),
                // Barcode + QR buttons (Material only)
                if (!isSvc) ...[
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
                    icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                    label: const Text('Delete', style: TextStyle(color: Colors.red)),
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
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
    _showScanCodeModal(item['name'] ?? '', item['uom'] ?? '', barcodeVal, isBarcode: true);
  }

  // ── Show existing or generate + save QR code ──
  void _showOrGenerateQR(Map<String, String> item) async {
    String qrVal = item['qr'] ?? '';

    if (qrVal.isEmpty) {
      qrVal = 'QR-${item['num']?.toUpperCase() ?? ''}';
      try {
        await _db.doc(item['id']).update({'qr': qrVal});
        item['qr'] = qrVal;
      } catch (e) {
        debugPrint('QR save error: $e');
      }
    }

    if (!mounted) return;
    _showScanCodeModal(item['name'] ?? '', item['uom'] ?? '', qrVal, isBarcode: false);
  }

  void _showScanCodeModal(String name, String uom, String value, {required bool isBarcode}) {
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
              if (uom.isNotEmpty)
                Text(uom, style: const TextStyle(color: Colors.white70, fontSize: 12)),
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
                      value,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        letterSpacing: 2,
                        color: Color(0xFF1a202c),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ])
                : Center(
                    child: QrImageView(
                      data: value,
                      version: QrVersions.auto,
                      size: 180,
                    )),
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

  void _showAddItemModal({Map<String, String>? item}) async {
    final isEdit = item != null;

    // Load domains once (cached after first load)
    await _ensureDomainsLoaded();
    if (!mounted) return;

    final groups = _cachedGroups!;
    final uoms = _cachedUoms!;
    final itemNum = isEdit ? item!['num']! : await _nextItemNum();
    if (!mounted) return;

    final skuCtrl = TextEditingController(text: item?['sku'] ?? '');
    final nameCtrl = TextEditingController(text: item?['name'] ?? '');
    final descCtrl = TextEditingController(text: item?['desc'] ?? '');
    final costCtrl = TextEditingController(text: item?['cost']?.replaceAll('₱', '').replaceAll(',', '') ?? '');
    final barcodeCtrl = TextEditingController(text: item?['barcode'] ?? '');
    final qrCtrl = TextEditingController(text: item?['qr'] ?? '');
    String selectedType = item?['type'] ?? 'Material';
    String? selectedGroup = (item?['group']?.isNotEmpty == true && groups.contains(item!['group'])) ? item['group'] : null;
    String? selectedUom = (item?['uom']?.isNotEmpty == true && uoms.contains(item!['uom'])) ? item['uom'] : null;
    bool saving = false;

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
                  TextField(controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Item Name *', border: OutlineInputBorder())),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: selectedGroup,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Commodity Group', border: OutlineInputBorder()),
                    hint: const Text('Select group'),
                    items: groups.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                    onChanged: (v) => setModalState(() => selectedGroup = v),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: selectedUom,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'UOM', border: OutlineInputBorder()),
                    hint: const Text('Select UOM'),
                    items: uoms.map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                    onChanged: (v) => setModalState(() => selectedUom = v),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  const SizedBox(height: 10),
                  TextField(controller: descCtrl, maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder())),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: TextField(controller: costCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Cost (₱)', border: OutlineInputBorder(), prefixText: '₱'))),
                    const SizedBox(width: 10),
                    Expanded(child: DropdownButtonFormField<String>(
                      value: selectedType,
                      decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'Material', child: Text('Material')),
                        DropdownMenuItem(value: 'Service', child: Text('Service')),
                      ],
                      onChanged: (v) => setModalState(() => selectedType = v!),
                    )),
                  ]),
                  if (selectedType == 'Material') ...[
                    const SizedBox(height: 10),
                    TextField(controller: skuCtrl, keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'SKU', border: OutlineInputBorder(), hintText: 'e.g. 10001')),
                    const SizedBox(height: 10),
                    // Barcode field with scan-only button
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: TextField(controller: barcodeCtrl,
                        decoration: InputDecoration(
                          labelText: 'Barcode',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.qr_code_scanner, size: 18, color: Color(0xFF003087)),
                            tooltip: 'Scan barcode',
                            onPressed: () async {
                              final result = await Navigator.push<String>(ctx,
                                MaterialPageRoute(builder: (_) => const BarcodeScannerScreen(
                                  title: 'Scan Barcode',
                                  hint: 'Point camera at the barcode',
                                )));
                              if (result != null && result.isNotEmpty) {
                                barcodeCtrl.text = result;
                                setModalState(() {});
                              }
                            },
                          ),
                        ))),
                    ]),
                    const SizedBox(height: 10),
                    // QR Code field with scan-only button
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: TextField(controller: qrCtrl,
                        decoration: InputDecoration(
                          labelText: 'QR Code',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.qr_code_scanner, size: 18, color: Color(0xFF003087)),
                            tooltip: 'Scan QR code',
                            onPressed: () async {
                              final result = await Navigator.push<String>(ctx,
                                MaterialPageRoute(builder: (_) => const BarcodeScannerScreen(
                                  title: 'Scan QR Code',
                                  hint: 'Point camera at the QR code',
                                )));
                              if (result != null && result.isNotEmpty) {
                                qrCtrl.text = result;
                                setModalState(() {});
                              }
                            },
                          ),
                        ))),
                    ]),
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
                        setModalState(() => saving = true);
                        final data = <String, dynamic>{
                          'num': itemNum,
                          'sku': skuCtrl.text.trim(),
                          'name': nameCtrl.text.trim(),
                          'desc': descCtrl.text.trim(),
                          'group': selectedGroup ?? '',
                          'uom': selectedUom ?? '',
                          'cost': '₱${costCtrl.text.trim()}',
                          'type': selectedType,
                          'barcode': selectedType == 'Material' ? barcodeCtrl.text.trim() : '',
                          'qr': selectedType == 'Material' ? qrCtrl.text.trim() : '',
                        };
                        try {
                          if (isEdit) {
                            await _db.doc(item!['id']).update(data);
                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Row(children: const [Icon(Icons.check_circle_outline, color: Colors.white, size: 18), SizedBox(width: 8), Text('Item updated successfully!')]),
                                backgroundColor: Colors.green, behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
                            }
                          } else {
                            data['createdAt'] = FieldValue.serverTimestamp();
                            await _db.add(data);
                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Row(children: const [Icon(Icons.check_circle_outline, color: Colors.white, size: 18), SizedBox(width: 8), Text('Item added successfully!')]),
                                backgroundColor: Colors.green, behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
                              if (selectedType == 'Material' && context.mounted) {
                                final shouldSetStock = await showDialog<bool>(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    title: const Text('Set Stock Levels?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                    content: const Text(
                                      'Would you like to set the stock levels (min, max, current quantity) for this item now?',
                                      style: TextStyle(fontSize: 13, color: Color(0xFF4a5568)),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context, false),
                                        child: const Text('Later', style: TextStyle(color: Color(0xFF718096))),
                                      ),
                                      TextButton(
                                        onPressed: () => Navigator.pop(context, true),
                                        style: TextButton.styleFrom(foregroundColor: _red),
                                        child: const Text('Set Now', style: TextStyle(fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  ),
                                );
                                if (shouldSetStock == true && context.mounted) {
                                  _showSetStockModal(itemNum, nameCtrl.text.trim(), selectedGroup ?? '', selectedUom ?? '');
                                }
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
                                Text('Stock item added successfully!'),
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
        title: const Text('Delete Item'),
        content: Text('Delete "${item['name']}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await _db.doc(item['id']).delete();
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Row(children: const [Icon(Icons.check_circle_outline, color: Colors.white, size: 18), SizedBox(width: 8), Text('Item deleted successfully!')]),
                  backgroundColor: Colors.red, behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
