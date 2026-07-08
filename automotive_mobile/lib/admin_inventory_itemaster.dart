import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'barcode_scanner_screen.dart';

/// Standalone full-screen wrapper (for direct navigation if needed elsewhere).
class AdminInventoryItemMaster extends StatelessWidget {
  const AdminInventoryItemMaster({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFF7F8FA),
      body: AdminInventoryItemMasterBody(),
    );
  }
}

/// Embeddable body — used inside AdminInventoryHub's IndexedStack.
class AdminInventoryItemMasterBody extends StatefulWidget {
  final String searchQuery;
  const AdminInventoryItemMasterBody({super.key, this.searchQuery = ''});

  @override
  State<AdminInventoryItemMasterBody> createState() => _AdminInventoryItemMasterBodyState();
}

class _AdminInventoryItemMasterBodyState extends State<AdminInventoryItemMasterBody> {
  static const _red = Color(0xFFE8001C);
  static const _col = 'item_master';

  String _searchQuery = '';
  String _typeFilter = 'all'; // 'all', 'Material', 'Service'

  CollectionReference get _db => FirebaseFirestore.instance.collection(_col);

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
              child: afterTypeFilter.isEmpty
                ? const Center(child: Text('No items found.', style: TextStyle(color: Color(0xFF718096))))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: afterTypeFilter.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _itemCard(afterTypeFilter[i]),
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
            Text(
              item['group']!.isNotEmpty ? '${item['num']!} • ${item['group']!}' : item['num']!,
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
              Text(item['uom']!, style: const TextStyle(fontSize: 10, color: Color(0xFF718096))),
            ]),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_fmtCost(item['cost']!),
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: typeColor)),
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
                  Text(item['group'] ?? '—', style: const TextStyle(color: Colors.white70, fontSize: 12)),
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
                _detailRow('Cost', item['cost'] ?? '—'),
                _detailRow('Type', item['type'] ?? '—'),
                if (!isSvc) ...[
                  const Divider(height: 24),
                  const Text('Scan Codes', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF718096))),
                  const SizedBox(height: 12),
                  if ((item['barcode'] ?? '').isNotEmpty) ...[
                    const Text('Barcode', style: TextStyle(fontSize: 11, color: Color(0xFF718096))),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFe2e8f0)), borderRadius: BorderRadius.circular(10)),
                      child: BarcodeWidget(
                        barcode: Barcode.code128(),
                        data: item['barcode']!,
                        width: double.infinity,
                        height: 70,
                        drawText: true,
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if ((item['qr'] ?? '').isNotEmpty) ...[
                    const Text('QR Code', style: TextStyle(fontSize: 11, color: Color(0xFF718096))),
                    const SizedBox(height: 8),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFe2e8f0)), borderRadius: BorderRadius.circular(10)),
                        child: QrImageView(
                          data: item['qr']!,
                          version: QrVersions.auto,
                          size: 160,
                        ),
                      ),
                    ),
                  ],
                  if ((item['barcode'] ?? '').isEmpty && (item['qr'] ?? '').isEmpty)
                    const Text('No scan codes assigned.', style: TextStyle(fontSize: 12, color: Color(0xFF718096))),
                ],
                const SizedBox(height: 16),
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

  String _fmtCost(String raw) {
    final clean = raw.replaceAll('₱', '').replaceAll(',', '').trim();
    final val = double.tryParse(clean);
    if (val == null || clean.isEmpty) return '₱0.00';
    return '₱${val.toStringAsFixed(2)}';
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
                  Container(width: 44, height: 44,
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(12)),
                    child: Icon(isEdit ? Icons.edit_outlined : Icons.add, color: Colors.white, size: 22)),
                  const SizedBox(width: 12),
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
                    // Barcode field with scan button
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: TextField(controller: barcodeCtrl,
                        decoration: InputDecoration(
                          labelText: 'Barcode',
                          border: const OutlineInputBorder(),
                          suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                            // Auto-generate
                            IconButton(
                              icon: const Icon(Icons.auto_fix_high, size: 18),
                              tooltip: 'Auto-generate',
                              onPressed: () {
                                barcodeCtrl.text = DateTime.now().millisecondsSinceEpoch.toString().substring(3);
                                setModalState(() {});
                              },
                            ),
                            // Scan
                            IconButton(
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
                          ]),
                        ))),
                    ]),
                    const SizedBox(height: 10),
                    // QR Code field with scan button
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: TextField(controller: qrCtrl,
                        decoration: InputDecoration(
                          labelText: 'QR Code',
                          border: const OutlineInputBorder(),
                          suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                            // Auto-generate
                            IconButton(
                              icon: const Icon(Icons.auto_fix_high, size: 18),
                              tooltip: 'Auto-generate',
                              onPressed: () {
                                qrCtrl.text = 'QR-$itemNum';
                                setModalState(() {});
                              },
                            ),
                            // Scan
                            IconButton(
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
                          ]),
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
                      onPressed: () async {
                        if (nameCtrl.text.trim().isEmpty) return;
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
                              // Auto-navigate to Stock Inventory to set stock levels for Material items
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
                                  // Show stock level fields directly in a modal
                                  _showSetStockModal(itemNum, nameCtrl.text.trim(), selectedGroup ?? '', selectedUom ?? '');
                                }
                              }
                            }
                          }
                        } catch (e) {
                          if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                        }
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
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

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, _) => AnimatedPadding(
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
                      onPressed: () async {
                        final stock = int.tryParse(stockCtrl.text) ?? 0;
                        final min = int.tryParse(minCtrl.text) ?? 0;
                        final max = int.tryParse(maxCtrl.text) ?? 0;
                        final reorder = int.tryParse(reorderCtrl.text) ?? 0;
                        try {
                          // Check if already exists in stock_inventory
                          final existing = await FirebaseFirestore.instance
                              .collection('stock_inventory')
                              .where('num', isEqualTo: itemNum)
                              .limit(1).get();
                          if (existing.docs.isNotEmpty) {
                            // Update existing
                            await existing.docs.first.reference.update({
                              'stock': stock, 'min': min, 'max': max, 'reorder': reorder,
                              'status': stock > min ? 'OK' : 'Low',
                              'updatedAt': FieldValue.serverTimestamp(),
                            });
                          } else {
                            // Create new stock entry
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
                                Text('Stock levels saved!'),
                              ]),
                              backgroundColor: Colors.green, behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
                          }
                        } catch (e) {
                          if (sheetCtx.mounted) ScaffoldMessenger.of(sheetCtx).showSnackBar(
                            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                        }
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF003087), foregroundColor: Colors.white),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
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
