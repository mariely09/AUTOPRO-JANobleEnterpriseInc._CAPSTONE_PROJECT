import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'barcode_scanner_screen.dart';

/// Standalone full-screen wrapper for Stock Inventory.
/// Can be navigated to directly (e.g. from dashboard stat card).
class AdminInventoryStock extends StatelessWidget {
  const AdminInventoryStock({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFE8001C),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Stock Inventory',
          style: TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      body: const AdminInventoryStockBody(),
    );
  }
}

/// Embeddable body — can be placed inside any parent (e.g. a tab in the hub).
/// Accepts [searchQuery] from the parent's search bar.
class AdminInventoryStockBody extends StatefulWidget {
  final String searchQuery;
  const AdminInventoryStockBody({super.key, this.searchQuery = ''});

  @override
  State<AdminInventoryStockBody> createState() =>
      _AdminInventoryStockBodyState();
}

class _AdminInventoryStockBodyState extends State<AdminInventoryStockBody> {
  static const _red = Color(0xFFE8001C);
  static const _stockCol = 'stock_inventory';
  static const _masterCol = 'item_master';

  String _statusFilter = 'all'; // 'all', 'Low', 'OK'

  CollectionReference get _db =>
      FirebaseFirestore.instance.collection(_stockCol);
  CollectionReference get _masterDb =>
      FirebaseFirestore.instance.collection(_masterCol);

  Future<Map<String, dynamic>?> _findItemMaster(String query) async {
    if (query.isEmpty) return null;
    final q = query.trim();
    var snap = await _masterDb.where('barcode', isEqualTo: q).limit(1).get();
    if (snap.docs.isNotEmpty) return _docToMaster(snap.docs.first);
    snap = await _masterDb.where('qr', isEqualTo: q).limit(1).get();
    if (snap.docs.isNotEmpty) return _docToMaster(snap.docs.first);
    snap = await _masterDb
        .where('num', isEqualTo: q.toUpperCase())
        .limit(1)
        .get();
    if (snap.docs.isNotEmpty) return _docToMaster(snap.docs.first);
    snap = await _masterDb
        .orderBy('name')
        .startAt([q])
        .endAt(['$q\uf8ff'])
        .limit(1)
        .get();
    if (snap.docs.isNotEmpty) return _docToMaster(snap.docs.first);
    return null;
  }

  Map<String, dynamic> _docToMaster(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return {
      'id': doc.id,
      'num': d['num'] ?? '',
      'name': d['name'] ?? '',
      'group': d['group'] ?? '',
      'uom': d['uom'] ?? '',
      'barcode': d['barcode'] ?? '',
      'qr': d['qr'] ?? '',
    };
  }


  @override
  Widget build(BuildContext context) {
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
                'name': data['name'] as String? ?? '',
                'group': data['group'] as String? ?? '',
                'uom': data['uom'] as String? ?? '',
                'stock': stock,
                'min': min,
                'max': max,
                'reorder': (data['reorder'] as num?)?.toInt() ?? 0,
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
                : filtered.where((i) => i['status'] == _statusFilter).toList();

            final total = items.length;
            final lowCount =
                items.where((i) => i['status'] == 'Low').length;

            return Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(children: [
                  _statChip('Total Items', '$total', Colors.blue,
                      Icons.inventory_2_outlined, 'all'),
                  const SizedBox(width: 8),
                  _statChip('Low Stock', '$lowCount', _red,
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
                child: afterStatusFilter.isEmpty
                    ? const Center(
                        child: Text('No items found.',
                            style:
                                TextStyle(color: Color(0xFF718096))))
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: afterStatusFilter.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 10),
                        itemBuilder: (_, i) =>
                            _stockCard(afterStatusFilter[i]),
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
            onPressed: _showActionChoice,
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
    final isLow = status == 'Low';
    final isOver = status == 'Over';
    final stock = item['stock'] as int;
    final min = item['min'] as int;
    final max = item['max'] as int;
    final progress = max > 0 ? (stock / max).clamp(0.0, 1.0) : 0.0;
    final barColor =
        isLow ? Colors.orange : isOver ? Colors.purple : Colors.green;
    final statusLabel =
        isLow ? 'Low Stock' : isOver ? 'Over Max' : 'In Stock';

    return GestureDetector(
      onTap: () => _showStockDetails(item),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: isLow
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
                  Text('${item['group']}',
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF718096))),
                ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('$stock ${item['uom']}',
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
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert,
                  size: 18, color: Color(0xFF718096)),
              onSelected: (val) {
                if (val == 'edit') _showAddStockModal(item: item);
                if (val == 'delete') _confirmDelete(item);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                    value: 'edit',
                    child: Row(children: [
                      Icon(Icons.edit_outlined, size: 16),
                      SizedBox(width: 8),
                      Text('Edit')
                    ])),
                PopupMenuItem(
                    value: 'delete',
                    child: Row(children: [
                      Icon(Icons.delete_outline,
                          size: 16, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Delete',
                          style: TextStyle(color: Colors.red))
                    ])),
              ],
            ),
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


  void _showActionChoice() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          const Text('What would you like to do?',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1a202c))),
          const SizedBox(height: 6),
          const Text('Choose an action below',
              style: TextStyle(fontSize: 12, color: Color(0xFF718096))),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () {
              Navigator.pop(context);
              _showReceiveModal();
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: const Color(0xFFebf8ff),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF90cdf4))),
              child: Row(children: [
                Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                        color: const Color(0xFF003087),
                        borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.download_outlined,
                        color: Colors.white, size: 24)),
                const SizedBox(width: 14),
                const Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                  Text('Receive Items',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  Text('Update stock from delivery',
                      style: TextStyle(
                          fontSize: 12, color: Color(0xFF718096))),
                ])),
                const Icon(Icons.chevron_right,
                    color: Color(0xFF718096)),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () {
              Navigator.pop(context);
              _showAddStockModal();
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: const Color(0xFFF0F4FF),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFbee3f8))),
              child: Row(children: [
                Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                        color: _red,
                        borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.add_box_outlined,
                        color: Colors.white, size: 24)),
                const SizedBox(width: 14),
                const Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                  Text('Add Stock Item',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  Text('Add a new item to inventory',
                      style: TextStyle(
                          fontSize: 12, color: Color(0xFF718096))),
                ])),
                const Icon(Icons.chevron_right,
                    color: Color(0xFF718096)),
              ]),
            ),
          ),
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
                  Text(item['group'] as String,
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
                _detailRow('Item Number', item['num'] as String),
                _detailRow('Item Name', item['name'] as String),
                _detailRow('Commodity Group', item['group'] as String),
                _detailRow(
                    'Current Stock', '${item['stock']}'),
                _detailRow('Min Level', '${item['min']}'),
                _detailRow('Max Level', '${item['max']}'),
                _detailRow(
                    'Reorder Qty', '${item['reorder']}'),
                _detailRow('Status', item['status'] as String),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                      child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _showAddStockModal(item: item);
                    },
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Edit'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: _red,
                        foregroundColor: Colors.white),
                  )),
                  const SizedBox(width: 12),
                  Expanded(
                      child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _confirmDelete(item);
                    },
                    icon: const Icon(Icons.delete_outline,
                        size: 16, color: Colors.red),
                    label: const Text('Delete',
                        style: TextStyle(color: Colors.red)),
                    style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red)),
                  )),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }


  void _showReceiveModal() {
    final scanCtrl = TextEditingController();
    final qtyCtrl = TextEditingController();
    Map<String, dynamic>? foundStock;
    bool searching = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.92,
          builder: (_, ctrl) => SingleChildScrollView(
            controller: ctrl,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                decoration: const BoxDecoration(
                    color: Color(0xFF003087),
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(24))),
                child: Row(children: [
                  Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.download_outlined,
                          color: Colors.white, size: 22)),
                  const SizedBox(width: 12),
                  const Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                    Text('Receive Items',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    Text('Scan or search item to receive stock',
                        style:
                            TextStyle(color: Colors.white70, fontSize: 12)),
                  ])),
                  GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.close, color: Colors.white)),
                ]),
              ),
              Padding(
                padding: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    top: 20,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 24),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(children: [
                    Expanded(
                        child: TextField(
                      controller: scanCtrl,
                      decoration: const InputDecoration(
                        hintText:
                            'Barcode, QR, item number or name...',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.search),
                      ),
                      onSubmitted: (_) async {
                        setModal(() => searching = true);
                        final master =
                            await _findItemMaster(scanCtrl.text);
                        if (master != null) {
                          final stockSnap = await _db
                              .where('num', isEqualTo: master['num'])
                              .limit(1)
                              .get();
                          foundStock = stockSnap.docs.isNotEmpty
                              ? {
                                  'id': stockSnap.docs.first.id,
                                  ...stockSnap.docs.first.data()
                                      as Map<String, dynamic>
                                }
                              : null;
                        } else {
                          foundStock = null;
                        }
                        setModal(() => searching = false);
                      },
                    )),
                    const SizedBox(width: 8),
                    IconButton(
                      style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFF003087),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.all(10)),
                      icon: const Icon(Icons.qr_code_scanner,
                          color: Colors.white, size: 22),
                      onPressed: () async {
                        final result =
                            await Navigator.push<String>(context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  const BarcodeScannerScreen()));
                        if (result != null) {
                          scanCtrl.text = result;
                          setModal(() => searching = true);
                          final master =
                              await _findItemMaster(result);
                          if (master != null) {
                            final stockSnap = await _db
                                .where('num', isEqualTo: master['num'])
                                .limit(1)
                                .get();
                            foundStock = stockSnap.docs.isNotEmpty
                                ? {
                                    'id': stockSnap.docs.first.id,
                                    ...stockSnap.docs.first.data()
                                        as Map<String, dynamic>
                                  }
                                : null;
                          } else {
                            foundStock = null;
                          }
                          setModal(() => searching = false);
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () async {
                        setModal(() => searching = true);
                        final master =
                            await _findItemMaster(scanCtrl.text);
                        if (master != null) {
                          final stockSnap = await _db
                              .where('num', isEqualTo: master['num'])
                              .limit(1)
                              .get();
                          foundStock = stockSnap.docs.isNotEmpty
                              ? {
                                  'id': stockSnap.docs.first.id,
                                  ...stockSnap.docs.first.data()
                                      as Map<String, dynamic>
                                }
                              : null;
                        } else {
                          foundStock = null;
                        }
                        setModal(() => searching = false);
                      },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF003087),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8))),
                      child: const Text('Search'),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  if (searching)
                    const Center(child: CircularProgressIndicator()),
                  if (!searching && foundStock != null) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: const Color(0xFFebf8ff),
                          border: Border.all(
                              color: const Color(0xFF90cdf4)),
                          borderRadius: BorderRadius.circular(12)),
                      child: Row(children: [
                        Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                                color: const Color(0xFF003087),
                                borderRadius:
                                    BorderRadius.circular(10)),
                            child: const Icon(
                                Icons.inventory_2_outlined,
                                color: Colors.white,
                                size: 22)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                          Text(
                              foundStock!['name'] as String? ?? '',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14)),
                          Text(
                              '${foundStock!['num']} • ${foundStock!['group']}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF718096))),
                          Text(
                              'Current stock: ${foundStock!['stock']} ${foundStock!['uom']}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF2c5282),
                                  fontWeight: FontWeight.w500)),
                        ])),
                        GestureDetector(
                            onTap: () => setModal(() {
                                  foundStock = null;
                                  scanCtrl.clear();
                                }),
                            child: const Icon(Icons.close,
                                size: 18, color: Color(0xFF718096))),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: qtyCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Quantity Received *',
                        border: const OutlineInputBorder(),
                        prefixIcon:
                            const Icon(Icons.add_box_outlined),
                        helperText:
                            'Will be added to current stock of ${foundStock!['stock']} ${foundStock!['uom']}',
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(children: [
                      Expanded(
                          child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancel'))),
                      const SizedBox(width: 12),
                      Expanded(
                          child: ElevatedButton(
                        onPressed: () async {
                          final qty =
                              int.tryParse(qtyCtrl.text) ?? 0;
                          if (qty <= 0) return;
                          final currentStock =
                              (foundStock!['stock'] as num?)
                                      ?.toInt() ??
                                  0;
                          final newStock = currentStock + qty;
                          final min =
                              (foundStock!['min'] as num?)?.toInt() ??
                                  0;
                          try {
                            await _db
                                .doc(foundStock!['id'] as String)
                                .update({
                              'stock': newStock,
                              'status': newStock > min ? 'OK' : 'Low',
                              'updatedAt':
                                  FieldValue.serverTimestamp(),
                            });
                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(
                                content: Row(children: const [
                                  Icon(
                                      Icons.check_circle_outline,
                                      color: Colors.white,
                                      size: 18),
                                  SizedBox(width: 8),
                                  Text(
                                      'Stock received successfully!')
                                ]),
                                backgroundColor: Colors.green,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(10)),
                              ));
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(
                                      content: Text('Error: $e'),
                                      backgroundColor: Colors.red));
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF003087),
                            foregroundColor: Colors.white),
                        child: const Text('✅ Confirm'),
                      )),
                    ]),
                  ] else if (!searching &&
                      scanCtrl.text.isNotEmpty &&
                      foundStock == null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: Colors.red.shade200)),
                      child: const Row(children: [
                        Icon(Icons.error_outline,
                            color: Colors.red, size: 16),
                        SizedBox(width: 8),
                        Text(
                            'No stock item found for that code.',
                            style: TextStyle(
                                color: Colors.red, fontSize: 12)),
                      ]),
                    ),
                ]),
              ),
            ]),
          ),
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
    final stockCtrl =
        TextEditingController(text: '${item['stock']}');
    final minCtrl = TextEditingController(text: '${item['min']}');
    final maxCtrl = TextEditingController(text: '${item['max']}');
    final reorderCtrl =
        TextEditingController(text: '${item['reorder']}');

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
                  Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.edit_outlined,
                          color: Colors.white, size: 22)),
                  const SizedBox(width: 12),
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
                      _infoRow('Item Number',
                          item['num'] as String),
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
                      decoration: const InputDecoration(
                          labelText: 'Reorder Quantity *',
                          border: OutlineInputBorder())),
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
                          await _db
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
                          });
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
    final scanCtrl = TextEditingController();
    final stockCtrl = TextEditingController();
    final minCtrl = TextEditingController();
    final maxCtrl = TextEditingController();
    final reorderCtrl = TextEditingController();
    Map<String, dynamic>? foundMaster;
    bool searching = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          builder: (_, ctrl) => SingleChildScrollView(
            controller: ctrl,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                decoration: const BoxDecoration(
                    color: _red,
                    borderRadius: BorderRadius.vertical(
                        top: Radius.circular(24))),
                child: Row(children: [
                  Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.add_box_outlined,
                          color: Colors.white, size: 22)),
                  const SizedBox(width: 12),
                  const Expanded(
                      child: Text('Add Stock Item',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold))),
                  GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child:
                          const Icon(Icons.close, color: Colors.white)),
                ]),
              ),
              Padding(
                padding: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    top: 20,
                    bottom:
                        MediaQuery.of(context).viewInsets.bottom + 24),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(children: [
                    Expanded(
                        child: TextField(
                      controller: scanCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Scan or search item...',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.search),
                      ),
                      onSubmitted: (_) async {
                        setModal(() => searching = true);
                        foundMaster =
                            await _findItemMaster(scanCtrl.text);
                        setModal(() => searching = false);
                      },
                    )),
                    const SizedBox(width: 8),
                    IconButton(
                      style: IconButton.styleFrom(
                          backgroundColor: _red,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.all(10)),
                      icon: const Icon(Icons.qr_code_scanner,
                          color: Colors.white, size: 22),
                      onPressed: () async {
                        final result =
                            await Navigator.push<String>(context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  const BarcodeScannerScreen()));
                        if (result != null) {
                          scanCtrl.text = result;
                          setModal(() => searching = true);
                          foundMaster =
                              await _findItemMaster(result);
                          setModal(() => searching = false);
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () async {
                        setModal(() => searching = true);
                        foundMaster =
                            await _findItemMaster(scanCtrl.text);
                        setModal(() => searching = false);
                      },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _red,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8))),
                      child: const Text('Search'),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  if (searching)
                    const Center(child: CircularProgressIndicator()),
                  if (!searching && foundMaster != null)
                    FutureBuilder<QuerySnapshot>(
                      future: _db
                          .where('num',
                              isEqualTo: foundMaster!['num'])
                          .limit(1)
                          .get(),
                      builder: (ctx, dupSnap) {
                        if (dupSnap.connectionState ==
                            ConnectionState.waiting) {
                          return const SizedBox.shrink();
                        }
                        final alreadyExists =
                            (dupSnap.data?.docs.isNotEmpty) == true;
                        if (alreadyExists) {
                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                border: Border.all(
                                    color: Colors.orange.shade300),
                                borderRadius:
                                    BorderRadius.circular(12)),
                            child: const Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                              Row(children: [
                                Icon(Icons.warning_amber_outlined,
                                    color: Colors.orange, size: 16),
                                SizedBox(width: 6),
                                Text('Already in Stock',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Colors.orange,
                                        fontSize: 12)),
                              ]),
                              SizedBox(height: 6),
                              Text(
                                  'This item already exists. Use Edit to update it.',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.orange)),
                            ]),
                          );
                        }
                        return Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                                color: const Color(0xFFf0fff4),
                                border: Border.all(
                                    color: const Color(0xFF68d391)),
                                borderRadius:
                                    BorderRadius.circular(12)),
                            child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                              const Row(children: [
                                Icon(Icons.check_circle_outline,
                                    color: Colors.green, size: 16),
                                SizedBox(width: 6),
                                Text('Item Found',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Colors.green,
                                        fontSize: 12)),
                              ]),
                              const SizedBox(height: 8),
                              _infoRow('Item Number',
                                  foundMaster!['num'] as String),
                              _infoRow('Item Name',
                                  foundMaster!['name'] as String),
                              _infoRow('Group',
                                  foundMaster!['group'] as String),
                              _infoRow('UOM',
                                  foundMaster!['uom'] as String),
                            ]),
                          ),
                          const SizedBox(height: 14),
                          const Text('Stock Level Settings',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13)),
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
                                    keyboardType:
                                        TextInputType.number,
                                    decoration:
                                        const InputDecoration(
                                            labelText: 'Min Level *',
                                            border:
                                                OutlineInputBorder()))),
                            const SizedBox(width: 10),
                            Expanded(
                                child: TextField(
                                    controller: maxCtrl,
                                    keyboardType:
                                        TextInputType.number,
                                    decoration:
                                        const InputDecoration(
                                            labelText: 'Max Level *',
                                            border:
                                                OutlineInputBorder()))),
                          ]),
                          const SizedBox(height: 10),
                          TextField(
                              controller: reorderCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                  labelText: 'Reorder Quantity *',
                                  border: OutlineInputBorder())),
                          const SizedBox(height: 20),
                          Row(children: [
                            Expanded(
                                child: OutlinedButton(
                                    onPressed: () =>
                                        Navigator.pop(context),
                                    child: const Text('Cancel'))),
                            const SizedBox(width: 12),
                            Expanded(
                                child: ElevatedButton(
                              onPressed: () async {
                                final stock = int.tryParse(
                                        stockCtrl.text) ??
                                    0;
                                final min =
                                    int.tryParse(minCtrl.text) ??
                                        0;
                                final max =
                                    int.tryParse(maxCtrl.text) ??
                                        0;
                                final reorder = int.tryParse(
                                        reorderCtrl.text) ??
                                    0;
                                final data = <String, dynamic>{
                                  'num': foundMaster!['num'],
                                  'name': foundMaster!['name'],
                                  'group': foundMaster!['group'],
                                  'uom': foundMaster!['uom'],
                                  'stock': stock,
                                  'min': min,
                                  'max': max,
                                  'reorder': reorder,
                                  'status': stock > min
                                      ? 'OK'
                                      : 'Low',
                                  'createdAt':
                                      FieldValue.serverTimestamp(),
                                  'updatedAt':
                                      FieldValue.serverTimestamp(),
                                };
                                try {
                                  final existing = await _db
                                      .where('num',
                                          isEqualTo:
                                              foundMaster!['num'])
                                      .limit(1)
                                      .get();
                                  if (existing.docs.isNotEmpty) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(const SnackBar(
                                        content: Text(
                                            'Already in stock inventory.'),
                                        backgroundColor:
                                            Colors.orange,
                                      ));
                                    }
                                    return;
                                  }
                                  await _db.add(data);
                                  if (context.mounted) {
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(SnackBar(
                                      content: Row(children: const [
                                        Icon(
                                            Icons
                                                .check_circle_outline,
                                            color: Colors.white,
                                            size: 18),
                                        SizedBox(width: 8),
                                        Text(
                                            'Stock item added successfully!')
                                      ]),
                                      backgroundColor: Colors.green,
                                      behavior:
                                          SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(
                                                  10)),
                                    ));
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(SnackBar(
                                            content: Text('Error: $e'),
                                            backgroundColor:
                                                Colors.red));
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
                                Text('Save'),
                              ]),
                            )),
                          ]),
                        ]);
                      },
                    )
                  else if (!searching &&
                      scanCtrl.text.isNotEmpty &&
                      foundMaster == null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: Colors.red.shade200)),
                      child: const Row(children: [
                        Icon(Icons.error_outline,
                            color: Colors.red, size: 16),
                        SizedBox(width: 8),
                        Text('No item found.',
                            style: TextStyle(
                                color: Colors.red, fontSize: 12)),
                      ]),
                    ),
                ]),
              ),
            ]),
          ),
        ),
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
                      Text('Stock item deleted successfully!')
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
