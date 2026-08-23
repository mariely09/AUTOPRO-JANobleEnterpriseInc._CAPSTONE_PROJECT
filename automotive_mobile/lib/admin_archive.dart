import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_inventory_stock.dart';

// ── Shared helper ────────────────────────────────────────────
String _fmtArchivedAt(dynamic ts) {
  if (ts == null) return '—';
  DateTime dt;
  if (ts is Timestamp) {
    dt = ts.toDate();
  } else {
    return '—';
  }
  const months = [
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
  final h24 = dt.hour;
  final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
  final ampm = h24 >= 12 ? 'PM' : 'AM';
  final min = dt.minute.toString().padLeft(2, '0');
  return '${months[dt.month - 1]} ${dt.day}, ${dt.year}  $h12:$min $ampm';
}

class AdminArchive extends StatefulWidget {
  const AdminArchive({super.key});
  @override
  State<AdminArchive> createState() => _AdminArchiveState();
}

class _AdminArchiveState extends State<AdminArchive> {
  static const _red = Color(0xFFE8001C);

  // 0=Item Master, 1=Maintenance, 2=Vehicles, 3=Users
  int _tab = 0;
  bool _searching = false;
  final _searchCtrl = TextEditingController();

  static const _tabs = ['Item Master', 'Maintenance', 'Vehicles', 'Users'];
  static const _tabTitles = [
    'Archived Items',
    'Archived Records',
    'Archived Vehicles',
    'Archived Users',
  ];

  @override
  void initState() {
    super.initState();
    _migrateOldArchivedItems();
  }

  /// Move any item_master docs with archived:true into archive/item_master/items
  Future<void> _migrateOldArchivedItems() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('item_master')
          .where('archived', isEqualTo: true)
          .get();
      for (final doc in snap.docs) {
        try {
          final archiveRef = FirebaseFirestore.instance
              .collection('archive')
              .doc('item_master')
              .collection('items')
              .doc(doc.id);
          final existing = await archiveRef.get();
          final data = doc.data();
          if (!existing.exists) {
            await archiveRef.set(data);
          }
          await doc.reference.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String get _searchQuery => _searching ? _searchCtrl.text.toLowerCase() : '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF004B5F),
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF004B5F), Color(0xFFEE152A)],
              stops: [0.0, 1.0],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        title: _searching
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Search...',
                  hintStyle: TextStyle(color: Colors.white54),
                  border: InputBorder.none,
                ),
              )
            : Text(
                _tabTitles[_tab],
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
        actions: [
          IconButton(
            icon: Icon(
              _searching ? Icons.close : Icons.search,
              color: Colors.white,
            ),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) _searchCtrl.clear();
            }),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Container(
            color: Colors.white,
            child: Row(
              children: List.generate(_tabs.length, (i) {
                final active = _tab == i;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _tab = i;
                      _searching = false;
                      _searchCtrl.clear();
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
                        _tabs[i],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: active
                              ? FontWeight.w700
                              : FontWeight.normal,
                          color: active ? _red : const Color(0xFF718096),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          _ItemMasterArchiveTab(searchQuery: _tab == 0 ? _searchQuery : ''),
          _MaintenanceArchiveTab(searchQuery: _tab == 1 ? _searchQuery : ''),
          _VehiclesArchiveTab(searchQuery: _tab == 2 ? _searchQuery : ''),
          _UsersArchiveTab(searchQuery: _tab == 3 ? _searchQuery : ''),
        ],
      ),
    );
  }
}

// ── Item Master Archive Tab ──────────────────────────────────
class _ItemMasterArchiveTab extends StatelessWidget {
  final String searchQuery;
  const _ItemMasterArchiveTab({required this.searchQuery});

  static const _red = Color(0xFFE8001C);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('archive')
          .doc('item_master')
          .collection('items')
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];
        final items = docs
            .map((d) {
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
                'archivedAt': data['archivedAt'],
              };
            })
            .where((i) {
              if (searchQuery.isEmpty) return true;
              return (i['name'] as String).toLowerCase().contains(
                    searchQuery,
                  ) ||
                  (i['num'] as String).toLowerCase().contains(searchQuery) ||
                  (i['supplierCode'] as String).toLowerCase().contains(
                    searchQuery,
                  );
            })
            .toList();

        if (items.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'No archived items found.',
                style: TextStyle(color: Color(0xFF718096)),
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _ItemMasterCard(item: items[i]),
        );
      },
    );
  }
}

class _ItemMasterCard extends StatelessWidget {
  final Map<String, dynamic> item;
  const _ItemMasterCard({required this.item});

  static const _red = Color(0xFFE8001C);

  @override
  Widget build(BuildContext context) {
    final isSvc = item['type'] == 'Service';
    final typeColor = isSvc ? const Color(0xFF003087) : _red;
    final typeBg = isSvc ? const Color(0xFFebf8ff) : const Color(0xFFFFF5F5);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFe2e8f0)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6),
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
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF4a5568),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if ((item['group'] as String).isNotEmpty)
                          item['group']!,
                        if ((item['uom'] as String).isNotEmpty) item['uom']!,
                      ].join(' • '),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF718096),
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
                            isSvc ? 'Service' : 'Material',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: typeColor,
                            ),
                          ),
                        ),
                        if ((item['supplierCode'] as String).isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text(
                            item['supplierCode'] as String,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF718096),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F8FA),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.inventory_2_outlined,
                  size: 18,
                  color: Color(0xFF718096),
                ),
              ),
            ],
          ),
          if (_fmtArchivedAt(item['archivedAt']) != '—') ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(
                  Icons.schedule_outlined,
                  size: 11,
                  color: Color(0xFFa0aec0),
                ),
                const SizedBox(width: 4),
                Text(
                  'Archived: ${_fmtArchivedAt(item['archivedAt'])}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFFa0aec0),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _restore(context, item),
                  icon: const Icon(Icons.restore, size: 15),
                  label: const Text('Restore', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    foregroundColor: const Color(0xFF38a169),
                    side: const BorderSide(color: Color(0xFF38a169)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _permanentDelete(context, item),
                  icon: const Icon(
                    Icons.delete_forever_outlined,
                    size: 15,
                    color: Colors.red,
                  ),
                  label: const Text(
                    'Delete',
                    style: TextStyle(fontSize: 12, color: Colors.red),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    side: const BorderSide(color: Colors.red),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _restore(BuildContext context, Map<String, dynamic> item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Restore Item'),
        content: Text(
          'Are you sure you want to restore "${item['name']}" back to Item Master?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Restore',
              style: TextStyle(color: Color(0xFF38a169)),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final archiveRef = FirebaseFirestore.instance
          .collection('archive')
          .doc('item_master')
          .collection('items')
          .doc(item['id'] as String);
      final archiveSnap = await archiveRef.get();
      if (!archiveSnap.exists) throw Exception('Archive doc not found');
      final data = Map<String, dynamic>.from(
        archiveSnap.data() as Map<String, dynamic>,
      );
      data.remove('archivedAt');
      data.remove('archived'); // remove old soft-archive flag
      await FirebaseFirestore.instance
          .collection('item_master')
          .doc(item['id'] as String)
          .set(data);
      await archiveRef.delete();

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '"${item['name']}" restored! Setting up stock levels...',
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AdminInventoryStock(
            prefilledItemNum: item['num'] as String? ?? '',
            prefilledItemName: item['name'] as String? ?? '',
            prefilledGroup: item['group'] as String? ?? '',
            prefilledUom: item['uom'] as String? ?? '',
            prefilledSupplierCode: item['supplierCode'] as String? ?? '',
          ),
        ),
      );
    } catch (e) {
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
    }
  }

  Future<void> _permanentDelete(
    BuildContext context,
    Map<String, dynamic> item,
  ) async {
    final name = item['name'] as String;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: EdgeInsets.zero,
        title: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFE31E24), Color(0xFFC41E3A)],
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Text('⚠️', style: TextStyle(fontSize: 18)),
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Permanently Delete Item?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        content: RichText(
          text: TextSpan(
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF4a5568),
              height: 1.6,
            ),
            children: [
              const TextSpan(
                text:
                    'This action cannot be undone. Are you sure you want to permanently delete ',
              ),
              TextSpan(
                text: '"$name"',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1a202c),
                ),
              ),
              const TextSpan(text: ' from the archive?\n\n'),
              const TextSpan(
                text:
                    'This will remove all records and history associated with this item.',
                style: TextStyle(fontSize: 12, color: Color(0xFF718096)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF718096)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Yes, Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final num = item['num'] as String? ?? '';
      await FirebaseFirestore.instance
          .collection('archive')
          .doc('item_master')
          .collection('items')
          .doc(item['id'] as String)
          .delete();
      if (num.isNotEmpty) {
        final stockSnap = await FirebaseFirestore.instance
            .collection('stock_inventory')
            .where('num', isEqualTo: num)
            .limit(1)
            .get();
        if (stockSnap.docs.isNotEmpty)
          await stockSnap.docs.first.reference.delete();
      }
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"${item['name']}" permanently deleted.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
    } catch (e) {
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
    }
  }
}

// ── Maintenance Records Archive Tab ──────────────────────────
class _MaintenanceArchiveTab extends StatelessWidget {
  final String searchQuery;
  const _MaintenanceArchiveTab({required this.searchQuery});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('archive')
          .doc('maintenance')
          .collection('records')
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];
        final items = docs
            .map((d) {
              final data = d.data() as Map<String, dynamic>;
              return {
                'id': d.id,
                'plate': data['plate'] ?? '—',
                'desc': data['desc'] ?? '',
                'mechanic': data['mechanic'] ?? '—',
                'date': data['date'] ?? '—',
                'cost': data['cost'] ?? '₱0.00',
                'status': data['status'] ?? 'Ongoing',
                'archivedAt': data['archivedAt'],
              };
            })
            .where((i) {
              if (searchQuery.isEmpty) return true;
              return (i['plate'] as String).toLowerCase().contains(
                    searchQuery,
                  ) ||
                  (i['mechanic'] as String).toLowerCase().contains(
                    searchQuery,
                  ) ||
                  (i['desc'] as String).toLowerCase().contains(searchQuery);
            })
            .toList();

        if (items.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'No archived maintenance records found.',
                style: TextStyle(color: Color(0xFF718096)),
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _MaintenanceArchiveCard(item: items[i]),
        );
      },
    );
  }
}

class _MaintenanceArchiveCard extends StatelessWidget {
  final Map<String, dynamic> item;
  const _MaintenanceArchiveCard({required this.item});

  Color _statusColor(String s) {
    switch (s.toLowerCase()) {
      case 'completed':
        return Colors.green;
      case 'ongoing':
        return Colors.orange;
      default:
        return const Color(0xFF718096);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sc = _statusColor(item['status'] as String);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFe2e8f0)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6),
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
                      item['plate'] as String,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF1a202c),
                      ),
                    ),
                    if ((item['desc'] as String).isNotEmpty)
                      Text(
                        item['desc'] as String,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF4a5568),
                        ),
                      ),
                    const SizedBox(height: 2),
                    Text(
                      '${item['mechanic']}  •  ${item['date']}',
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
                    item['cost'] as String,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: sc.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      item['status'] as String,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: sc,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.archive_outlined,
                size: 18,
                color: Color(0xFF718096),
              ),
            ],
          ),
          if (_fmtArchivedAt(item['archivedAt']) != '—') ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(
                  Icons.schedule_outlined,
                  size: 11,
                  color: Color(0xFFa0aec0),
                ),
                const SizedBox(width: 4),
                Text(
                  'Archived: ${_fmtArchivedAt(item['archivedAt'])}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFFa0aec0),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _restore(context),
                  icon: const Icon(Icons.restore, size: 15),
                  label: const Text('Restore', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    foregroundColor: const Color(0xFF38a169),
                    side: const BorderSide(color: Color(0xFF38a169)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _permanentDelete(context),
                  icon: const Icon(
                    Icons.delete_forever_outlined,
                    size: 15,
                    color: Colors.red,
                  ),
                  label: const Text(
                    'Delete',
                    style: TextStyle(fontSize: 12, color: Colors.red),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    side: const BorderSide(color: Colors.red),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _restore(BuildContext context) async {
    final plate = item['plate'] as String;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Restore Record'),
        content: Text(
          'Are you sure you want to restore the service record for "$plate"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Restore',
              style: TextStyle(color: Color(0xFF38a169)),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final archiveRef = FirebaseFirestore.instance
          .collection('archive')
          .doc('maintenance')
          .collection('records')
          .doc(item['id'] as String);
      final archiveSnap = await archiveRef.get();
      if (!archiveSnap.exists) throw Exception('Archive doc not found');
      final data = Map<String, dynamic>.from(
        archiveSnap.data() as Map<String, dynamic>,
      );
      data.remove('archivedAt');
      await FirebaseFirestore.instance
          .collection('maintenance')
          .doc(item['id'] as String)
          .set(data);
      await archiveRef.delete();
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Service record for "$plate" restored!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
    } catch (e) {
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
    }
  }

  Future<void> _permanentDelete(BuildContext context) async {
    final plate = item['plate'] as String;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: EdgeInsets.zero,
        title: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFE31E24), Color(0xFFC41E3A)],
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Text('⚠️', style: TextStyle(fontSize: 18)),
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Permanently Delete Record?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        content: RichText(
          text: TextSpan(
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF4a5568),
              height: 1.6,
            ),
            children: [
              const TextSpan(
                text:
                    'This action cannot be undone. Are you sure you want to permanently delete ',
              ),
              TextSpan(
                text: '"$plate"',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1a202c),
                ),
              ),
              const TextSpan(text: ' from the archive?\n\n'),
              const TextSpan(
                text:
                    'This will remove all records and history associated with this service record.',
                style: TextStyle(fontSize: 12, color: Color(0xFF718096)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF718096)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Yes, Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await FirebaseFirestore.instance
          .collection('archive')
          .doc('maintenance')
          .collection('records')
          .doc(item['id'] as String)
          .delete();
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Service record for "$plate" permanently deleted.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
    } catch (e) {
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
    }
  }
}

// ── Vehicles Archive Tab ─────────────────────────────────────
class _VehiclesArchiveTab extends StatelessWidget {
  final String searchQuery;
  const _VehiclesArchiveTab({required this.searchQuery});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('archive')
          .doc('vehicles')
          .collection('vehicles')
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];
        final items = docs
            .map((d) {
              final data = d.data() as Map<String, dynamic>;
              return {
                'id': d.id,
                'plate':
                    data['plate']?.toString() ??
                    data['plateNumber']?.toString() ??
                    '—',
                'type': data['type']?.toString() ?? '—',
                'owner': data['owner']?.toString() ?? '—',
                'odo': data['odo']?.toString() ?? '',
                'lastSvcDate':
                    data['lastSvcDate']?.toString() ??
                    data['lastServiceDate']?.toString() ??
                    '',
                'svcFreq': data['svcFreq']?.toString() ?? '',
                'archivedAt': data['archivedAt'],
              };
            })
            .where((v) {
              if (searchQuery.isEmpty) return true;
              return (v['plate'] as String).toLowerCase().contains(
                    searchQuery,
                  ) ||
                  (v['owner'] as String).toLowerCase().contains(searchQuery) ||
                  (v['type'] as String).toLowerCase().contains(searchQuery);
            })
            .toList();

        if (items.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.archive_outlined,
                  size: 52,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(height: 12),
                const Text(
                  'No archived vehicles found.',
                  style: TextStyle(color: Color(0xFF718096)),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _VehiclesArchiveCard(item: items[i]),
        );
      },
    );
  }
}

class _VehiclesArchiveCard extends StatelessWidget {
  final Map<String, dynamic> item;
  const _VehiclesArchiveCard({required this.item});

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

  String _fmtDate(String d) {
    if (d.isEmpty) return '—';
    final dt = DateTime.tryParse(d);
    if (dt == null) return d;
    return '${_monthsFull[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final plate = item['plate'] as String;
    final odo = (item['odo'] as String).isNotEmpty
        ? item['odo'] as String
        : '—';
    final lastSvc = _fmtDate(item['lastSvcDate'] as String);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade100),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.archive_outlined,
                  color: Colors.orange,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plate,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF1a202c),
                      ),
                    ),
                    Text(
                      '${item['type']}  •  ${item['owner']}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF4a5568),
                      ),
                    ),
                    Text(
                      '$odo  •  Last service: $lastSvc',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF718096),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_fmtArchivedAt(item['archivedAt']) != '—') ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(
                  Icons.schedule_outlined,
                  size: 11,
                  color: Color(0xFFa0aec0),
                ),
                const SizedBox(width: 4),
                Text(
                  'Archived: ${_fmtArchivedAt(item['archivedAt'])}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFFa0aec0),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _restore(context),
                  icon: const Icon(Icons.restore, size: 15),
                  label: const Text('Restore', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    foregroundColor: const Color(0xFF38a169),
                    side: const BorderSide(color: Color(0xFF38a169)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _permanentDelete(context),
                  icon: const Icon(
                    Icons.delete_forever_outlined,
                    size: 15,
                    color: Colors.red,
                  ),
                  label: const Text(
                    'Delete',
                    style: TextStyle(fontSize: 12, color: Colors.red),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    side: const BorderSide(color: Colors.red),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _restore(BuildContext context) async {
    final plate = item['plate'] as String;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.unarchive_outlined, color: Color(0xFF003087), size: 22),
            SizedBox(width: 8),
            Text(
              'Restore Vehicle',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to restore "$plate" back to the active vehicle list?',
          style: const TextStyle(fontSize: 14, color: Color(0xFF4a5568)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF718096)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF003087),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final archiveRef = FirebaseFirestore.instance
          .collection('archive')
          .doc('vehicles')
          .collection('vehicles')
          .doc(item['id'] as String);
      final archiveSnap = await archiveRef.get();
      if (!archiveSnap.exists) throw Exception('Archive doc not found');
      final data = Map<String, dynamic>.from(
        archiveSnap.data() as Map<String, dynamic>,
      );
      data.remove('archivedAt');
      data.remove('archived');
      await FirebaseFirestore.instance
          .collection('vehicles')
          .doc(item['id'] as String)
          .set(data);
      await archiveRef.delete();
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"$plate" restored to active vehicles!'),
            backgroundColor: const Color(0xFF003087),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
    } catch (e) {
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
    }
  }

  Future<void> _permanentDelete(BuildContext context) async {
    final plate = item['plate'] as String;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: EdgeInsets.zero,
        title: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFE31E24), Color(0xFFC41E3A)],
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Text('⚠️', style: TextStyle(fontSize: 18)),
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Permanently Delete Vehicle?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        content: RichText(
          text: TextSpan(
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF4a5568),
              height: 1.6,
            ),
            children: [
              const TextSpan(
                text:
                    'This action cannot be undone. Are you sure you want to permanently delete ',
              ),
              TextSpan(
                text: '"$plate"',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1a202c),
                ),
              ),
              const TextSpan(text: ' from the archive?\n\n'),
              const TextSpan(
                text:
                    'This will remove all records and history associated with this vehicle.',
                style: TextStyle(fontSize: 12, color: Color(0xFF718096)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF718096)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Yes, Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await FirebaseFirestore.instance
          .collection('archive')
          .doc('vehicles')
          .collection('vehicles')
          .doc(item['id'] as String)
          .delete();
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"$plate" permanently deleted.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
    } catch (e) {
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
    }
  }
}

// ── Users Archive Tab ────────────────────────────────────────
class _UsersArchiveTab extends StatelessWidget {
  final String searchQuery;
  const _UsersArchiveTab({required this.searchQuery});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('archive')
          .doc('users')
          .collection('users')
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];
        final items = docs
            .map((d) {
              final data = d.data() as Map<String, dynamic>;
              return {
                'id': d.id,
                'name': data['name']?.toString() ?? '—',
                'email': data['email']?.toString() ?? '—',
                'role': data['role']?.toString() ?? '—',
                'status': data['status']?.toString() ?? 'Inactive',
                'companyName': data['companyName']?.toString() ?? '',
                'archivedAt': data['archivedAt'],
              };
            })
            .where((u) {
              if (searchQuery.isEmpty) return true;
              return (u['name'] as String).toLowerCase().contains(
                    searchQuery,
                  ) ||
                  (u['email'] as String).toLowerCase().contains(searchQuery) ||
                  (u['role'] as String).toLowerCase().contains(searchQuery);
            })
            .toList();

        if (items.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.person_off_outlined,
                  size: 52,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(height: 12),
                const Text(
                  'No archived users found.',
                  style: TextStyle(color: Color(0xFF718096)),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _UsersArchiveCard(item: items[i]),
        );
      },
    );
  }
}

class _UsersArchiveCard extends StatelessWidget {
  final Map<String, dynamic> item;
  const _UsersArchiveCard({required this.item});

  Color _roleColor(String role) {
    if (role == 'admin') return const Color(0xFFE8001C);
    if (role == 'staff') return const Color(0xFF003087);
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    final name = item['name'] as String;
    final role = item['role'] as String;
    final status = item['status'] as String;
    final rc = _roleColor(role);
    final roleLabel = role.isNotEmpty
        ? role[0].toUpperCase() + role.substring(1)
        : '—';
    final statusLower = status.toLowerCase();
    final statusColor = statusLower == 'active'
        ? Colors.green
        : const Color(0xFF718096);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade100),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: rc.withOpacity(0.12),
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: rc,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: Color(0xFF1a202c),
                      ),
                    ),
                    Text(
                      item['email'] as String,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF718096),
                      ),
                    ),
                    if ((item['companyName'] as String).isNotEmpty)
                      Text(
                        item['companyName'] as String,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF718096),
                        ),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: rc.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      roleLabel,
                      style: TextStyle(
                        fontSize: 10,
                        color: rc,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (_fmtArchivedAt(item['archivedAt']) != '—') ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(
                  Icons.schedule_outlined,
                  size: 11,
                  color: Color(0xFFa0aec0),
                ),
                const SizedBox(width: 4),
                Text(
                  'Archived: ${_fmtArchivedAt(item['archivedAt'])}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFFa0aec0),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _restore(context),
                  icon: const Icon(Icons.restore, size: 15),
                  label: const Text('Restore', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    foregroundColor: const Color(0xFF38a169),
                    side: const BorderSide(color: Color(0xFF38a169)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _permanentDelete(context),
                  icon: const Icon(
                    Icons.delete_forever_outlined,
                    size: 15,
                    color: Colors.red,
                  ),
                  label: const Text(
                    'Delete',
                    style: TextStyle(fontSize: 12, color: Colors.red),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    side: const BorderSide(color: Colors.red),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _restore(BuildContext context) async {
    final name = item['name'] as String;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.unarchive_outlined, color: Colors.green, size: 22),
            SizedBox(width: 8),
            Text(
              'Restore User',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to restore "$name" back to User Management?',
          style: const TextStyle(fontSize: 14, color: Color(0xFF4a5568)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF718096)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final docId = item['id'] as String;
      final archiveRef = FirebaseFirestore.instance
          .collection('archive')
          .doc('users')
          .collection('users')
          .doc(docId);
      final archiveSnap = await archiveRef.get();
      if (!archiveSnap.exists) throw Exception('Archive doc not found');
      final data = Map<String, dynamic>.from(
        archiveSnap.data() as Map<String, dynamic>,
      );
      data.remove('archivedAt');
      await FirebaseFirestore.instance.collection('users').doc(docId).set(data);
      await archiveRef.delete();
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"$name" restored to User Management!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
    } catch (e) {
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
    }
  }

  Future<void> _permanentDelete(BuildContext context) async {
    final name = item['name'] as String;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: EdgeInsets.zero,
        title: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFE31E24), Color(0xFFC41E3A)],
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Text('⚠️', style: TextStyle(fontSize: 18)),
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Permanently Delete User?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        content: RichText(
          text: TextSpan(
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF4a5568),
              height: 1.6,
            ),
            children: [
              const TextSpan(
                text:
                    'This action cannot be undone. Are you sure you want to permanently delete ',
              ),
              TextSpan(
                text: '"$name"',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1a202c),
                ),
              ),
              const TextSpan(text: ' from the archive?\n\n'),
              const TextSpan(
                text:
                    'This will remove all records and history associated with this user.',
                style: TextStyle(fontSize: 12, color: Color(0xFF718096)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF718096)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Yes, Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await FirebaseFirestore.instance
          .collection('archive')
          .doc('users')
          .collection('users')
          .doc(item['id'] as String)
          .delete();
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"$name" permanently deleted.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
    } catch (e) {
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
    }
  }
}
