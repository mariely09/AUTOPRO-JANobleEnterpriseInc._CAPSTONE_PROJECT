import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminDomainManagement extends StatefulWidget {
  const AdminDomainManagement({super.key});

  @override
  State<AdminDomainManagement> createState() => _AdminDomainManagementState();
}

class _AdminDomainManagementState extends State<AdminDomainManagement> {
  static const _red = Color(0xFFE8001C);

  final _domains = [
    {
      'key': 'commodity_groups',
      'label': 'Commodity Groups',
      'icon': Icons.category_outlined,
      'color': _red,
    },
    {
      'key': 'uom',
      'label': 'Units of Measure',
      'icon': Icons.straighten_outlined,
      'color': _red,
    },
    {
      'key': 'vehicle_types',
      'label': 'Vehicle Types',
      'icon': Icons.directions_car_outlined,
      'color': _red,
    },
  ];

  static const _seeds = {
    'commodity_groups': [
      'Lubricants',
      'Filters',
      'Brakes',
      'Tires',
      'Electrical',
      'Body Parts',
      'Fluids',
      'Labor',
    ],
    'uom': ['pcs', 'L', 'set', 'job', 'kg', 'box', 'pair', 'm'],
    'vehicle_types': [
      'Truck',
      'SUV',
      'Sedan',
      'Van',
      'Motorcycle',
      'Bus',
      'Pickup',
    ],
  };

  @override
  void initState() {
    super.initState();
    _seedAll();
  }

  Future<void> _seedAll() async {
    for (final entry in _seeds.entries) {
      final col = FirebaseFirestore.instance
          .collection('domains')
          .doc(entry.key)
          .collection('items');
      final snap = await col.limit(1).get();
      if (snap.docs.isEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        for (final name in entry.value) {
          batch.set(col.doc(), {
            'name': name,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }
    }
  }

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
        title: const Text(
          'Domain Management',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _domains.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final d = _domains[i];
          final color = d['color'] as Color;
          return GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _DomainDetailScreen(
                  collectionKey: d['key'] as String,
                  label: d['label'] as String,
                  color: color,
                  icon: d['icon'] as IconData,
                ),
              ),
            ),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      d['label'] as String,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Color(0xFF1a202c),
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    color: Color(0xFFcbd5e0),
                    size: 20,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DomainDetailScreen extends StatefulWidget {
  final String collectionKey;
  final String label;
  final Color color;
  final IconData icon;

  const _DomainDetailScreen({
    required this.collectionKey,
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  State<_DomainDetailScreen> createState() => _DomainDetailScreenState();
}

class _DomainDetailScreenState extends State<_DomainDetailScreen> {
  CollectionReference get _col => FirebaseFirestore.instance
      .collection('domains')
      .doc(widget.collectionKey)
      .collection('items');

  void _showAddEdit({DocumentSnapshot? doc}) {
    final ctrl = TextEditingController(
      text: doc != null ? (doc['name'] as String? ?? '') : '',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return _AddEditSheet(
          ctrl: ctrl,
          doc: doc,
          label: widget.label,
          color: widget.color,
          col: _col,
          parentContext: context,
          parentMounted: () => mounted,
        );
      },
    );
  }

  void _confirmDelete(DocumentSnapshot doc) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Delete from ${widget.label}'),
        content: Text('Are you sure you want to delete "${doc['name']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              try {
                await doc.reference.delete();
                if (mounted)
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Row(
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            color: Colors.white,
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Text('Deleted successfully!'),
                        ],
                      ),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
              } catch (e) {
                if (mounted)
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
              }
            },
            child: const Text(
              'Yes, Delete',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEdit(),
        backgroundColor: widget.color,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      appBar: AppBar(
        backgroundColor: widget.color,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          widget.label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _col.orderBy('name').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Text(
                    'No ${widget.label} yet',
                    style: const TextStyle(color: Color(0xFF718096)),
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final doc = docs[i];
              final name = doc['name'] as String? ?? '—';
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(
                        Icons.more_vert,
                        size: 18,
                        color: Color(0xFF718096),
                      ),
                      onSelected: (val) {
                        if (val == 'edit') _showAddEdit(doc: doc);
                        if (val == 'delete') _confirmDelete(doc);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit_outlined, size: 16),
                              SizedBox(width: 8),
                              Text('Edit'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(
                                Icons.delete_outline,
                                size: 16,
                                color: Colors.red,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Delete',
                                style: TextStyle(color: Colors.red),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _AddEditSheet extends StatefulWidget {
  final TextEditingController ctrl;
  final DocumentSnapshot? doc;
  final String label;
  final Color color;
  final CollectionReference col;
  final BuildContext parentContext;
  final bool Function() parentMounted;

  const _AddEditSheet({
    required this.ctrl,
    required this.doc,
    required this.label,
    required this.color,
    required this.col,
    required this.parentContext,
    required this.parentMounted,
  });

  @override
  State<_AddEditSheet> createState() => _AddEditSheetState();
}

class _AddEditSheetState extends State<_AddEditSheet> {
  bool _saving = false;

  @override
  void dispose() {
    widget.ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  widget.doc == null ? 'Add ${widget.label}' : 'Edit',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close, color: Color(0xFF718096)),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: widget.ctrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Name *',
                border: const OutlineInputBorder(),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: widget.color, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _saving
                        ? null
                        : () async {
                            final name = widget.ctrl.text.trim();
                            if (name.isEmpty) return;
                            setState(() => _saving = true);
                            try {
                              if (widget.doc == null) {
                                await widget.col.add({
                                  'name': name,
                                  'createdAt': FieldValue.serverTimestamp(),
                                });
                                if (context.mounted) Navigator.pop(context);
                                if (widget.parentMounted()) {
                                  ScaffoldMessenger.of(
                                    widget.parentContext,
                                  ).showSnackBar(
                                    SnackBar(
                                      content: const Row(
                                        children: [
                                          Icon(
                                            Icons.check_circle_outline,
                                            color: Colors.white,
                                            size: 18,
                                          ),
                                          SizedBox(width: 8),
                                          Text('Added successfully!'),
                                        ],
                                      ),
                                      backgroundColor: Colors.green,
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                  );
                                }
                              } else {
                                await widget.doc!.reference.update({
                                  'name': name,
                                });
                                if (context.mounted) Navigator.pop(context);
                                if (widget.parentMounted()) {
                                  ScaffoldMessenger.of(
                                    widget.parentContext,
                                  ).showSnackBar(
                                    SnackBar(
                                      content: const Row(
                                        children: [
                                          Icon(
                                            Icons.check_circle_outline,
                                            color: Colors.white,
                                            size: 18,
                                          ),
                                          SizedBox(width: 8),
                                          Text('Updated successfully!'),
                                        ],
                                      ),
                                      backgroundColor: Colors.green,
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                  );
                                }
                              }
                            } catch (e) {
                              if (mounted) setState(() => _saving = false);
                              if (widget.parentMounted()) {
                                ScaffoldMessenger.of(
                                  widget.parentContext,
                                ).showSnackBar(
                                  SnackBar(
                                    content: Text('Error: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.color,
                      foregroundColor: Colors.white,
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.save_outlined, size: 16),
                              const SizedBox(width: 6),
                              Text(widget.doc == null ? 'Save' : 'Update'),
                            ],
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
}
