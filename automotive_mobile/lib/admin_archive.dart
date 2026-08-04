import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminArchive extends StatelessWidget {
  const AdminArchive({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFE8001C),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Archive',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      ),
      body: const AdminArchiveBody(),
    );
  }
}

class AdminArchiveBody extends StatefulWidget {
  const AdminArchiveBody({super.key});
  @override
  State<AdminArchiveBody> createState() => _AdminArchiveBodyState();
}

class _AdminArchiveBodyState extends State<AdminArchiveBody> {
  static const _red = Color(0xFFE8001C);
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Search bar
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _searchQuery = v.toLowerCase().trim()),
          style: const TextStyle(fontSize: 13, color: Color(0xFF1a202c)),
          decoration: InputDecoration(
            hintText: 'Search archived items...',
            hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFa0aec0)),
            prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFFa0aec0)),
            suffixIcon: _searchQuery.isNotEmpty
                ? GestureDetector(
                    onTap: () { _searchCtrl.clear(); setState(() => _searchQuery = ''); },
                    child: const Icon(Icons.close, size: 16, color: Color(0xFFa0aec0)),
                  )
                : null,
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFe2e8f0))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFe2e8f0))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _red, width: 1.5)),
          ),
        ),
      ),
      // List
      Expanded(
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('item_master')
              .where('archived', isEqualTo: true)
              .snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snap.data?.docs ?? [];
            final items = docs.map((d) {
              final data = d.data() as Map<String, dynamic>;
              return {
                'id': d.id,
                'num': data['num'] ?? '—',
                'name': data['name'] ?? '—',
                'uom': data['uom'] ?? '',
                'group': data['group'] ?? '',
                'supplierCode': data['supplierCode'] ?? '',
                'cost': data['cost'] ?? '₱0',
                'type': data['type'] ?? 'Material',
              };
            }).where((i) {
              if (_searchQuery.isEmpty) return true;
              return (i['name'] as String).toLowerCase().contains(_searchQuery) ||
                     (i['num']  as String).toLowerCase().contains(_searchQuery) ||
                     (i['supplierCode'] as String).toLowerCase().contains(_searchQuery);
            }).toList();

            if (items.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('No archived items found.', style: TextStyle(color: Color(0xFF718096))),
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _archivedCard(items[i]),
            );
          },
        ),
      ),
    ]);
  }

  Widget _archivedCard(Map<String, dynamic> item) {
    final isSvc = item['type'] == 'Service';
    final typeColor = isSvc ? const Color(0xFF003087) : _red;
    final typeBg    = isSvc ? const Color(0xFFebf8ff) : const Color(0xFFFFF5F5);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFe2e8f0)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item['name'] as String,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF4a5568))),
            const SizedBox(height: 2),
            Text(
              [if ((item['group'] as String).isNotEmpty) item['group']!, if ((item['uom'] as String).isNotEmpty) item['uom']!].join(' • '),
              style: const TextStyle(fontSize: 11, color: Color(0xFF718096)),
            ),
            const SizedBox(height: 4),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: typeBg, borderRadius: BorderRadius.circular(20)),
                child: Text(isSvc ? 'Service' : 'Material',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: typeColor)),
              ),
              if ((item['supplierCode'] as String).isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(item['supplierCode'] as String,
                    style: const TextStyle(fontSize: 10, color: Color(0xFF718096))),
              ],
            ]),
          ])),
          // Archive box icon
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: const Color(0xFFF7F8FA), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.inventory_2_outlined, size: 18, color: Color(0xFF718096)),
          ),
        ]),
        const SizedBox(height: 12),
        // Actions
        Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: () => _restore(item),
            icon: const Icon(Icons.restore, size: 15),
            label: const Text('Restore', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 8),
              foregroundColor: const Color(0xFF38a169),
              side: const BorderSide(color: Color(0xFF38a169)),
            ),
          )),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(
            onPressed: () => _permanentDelete(item),
            icon: const Icon(Icons.delete_forever_outlined, size: 15, color: Colors.red),
            label: const Text('Delete', style: TextStyle(fontSize: 12, color: Colors.red)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 8),
              side: const BorderSide(color: Colors.red),
            ),
          )),
        ]),
      ]),
    );
  }

  Future<void> _restore(Map<String, dynamic> item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Restore Item'),
        content: Text('Restore "${item['name']}" back to Item Master?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Restore', style: TextStyle(color: Color(0xFF38a169)))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await FirebaseFirestore.instance
          .collection('item_master')
          .doc(item['id'] as String)
          .update({'archived': false, 'archivedAt': null});
      // Restore stock_inventory status from Inactive back to proper status
      final num = item['num'] as String? ?? '';
      if (num.isNotEmpty) {
        final stockSnap = await FirebaseFirestore.instance
            .collection('stock_inventory').where('num', isEqualTo: num).limit(1).get();
        if (stockSnap.docs.isNotEmpty) {
          final data = stockSnap.docs.first.data() as Map<String, dynamic>;
          final stock = int.tryParse(data['stock']?.toString() ?? '0') ?? 0;
          final minLevel = int.tryParse(data['min']?.toString() ?? '0') ?? 0;
          final restoredStatus = stock > minLevel ? 'OK' : 'Low';
          await stockSnap.docs.first.reference.update({'status': restoredStatus}).catchError((_) {});
        }
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('"${item['name']}" restored successfully!'),
        backgroundColor: Colors.green, behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _permanentDelete(Map<String, dynamic> item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Permanently'),
        content: Text('Permanently delete "${item['name']}"? This CANNOT be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final num = item['num'] as String? ?? '';
      await FirebaseFirestore.instance.collection('item_master').doc(item['id'] as String).delete();
      // Also delete matching stock_inventory
      if (num.isNotEmpty) {
        final stockSnap = await FirebaseFirestore.instance
            .collection('stock_inventory').where('num', isEqualTo: num).limit(1).get();
        if (stockSnap.docs.isNotEmpty) await stockSnap.docs.first.reference.delete();
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('"${item['name']}" permanently deleted.'),
        backgroundColor: Colors.red, behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }
}
