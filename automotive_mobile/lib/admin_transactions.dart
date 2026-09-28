import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_bottomnavbar.dart';
import 'admin_dashboard.dart';
import 'admin_inventory_hub.dart';
import 'admin_vehicles_list.dart';
import 'profile.dart';

class AdminTransactions extends StatelessWidget {
  const AdminTransactions({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: const AdminTransactionsBody(),
      bottomNavigationBar: AdminBottomNavBar(
        currentIndex: 1,
        onTap: (i) {
          if (i == 0) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const AdminDashboard()),
            );
          } else if (i == 1) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => const AdminInventoryHub(initialTab: 4),
              ),
            );
          } else if (i == 2) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const AdminVehiclesList()),
            );
          } else if (i == 3) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => const UserProfile(role: UserRole.admin),
              ),
            );
          }
        },
      ),
    );
  }
}

/// Embeddable body for use inside a tab hub.
class AdminTransactionsBody extends StatefulWidget {
  final String searchQuery;
  const AdminTransactionsBody({super.key, this.searchQuery = ''});

  @override
  State<AdminTransactionsBody> createState() => _AdminTransactionsBodyState();
}

class _AdminTransactionsBodyState extends State<AdminTransactionsBody>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  static const _red = Color(0xFFE8001C);
  String _txnFilter = 'all';

  // Item master UOM lookup (item name -> uom)
  Map<String, String> _itemUomMap = {};

  @override
  void initState() {
    super.initState();
    _loadItemMaster();
  }

  Future<void> _loadItemMaster() async {
    final snap = await FirebaseFirestore.instance
        .collection('item_master')
        .get();
    if (!mounted) return;
    setState(() {
      _itemUomMap = {
        for (final d in snap.docs)
          (d['name'] as String? ?? ''): (d['uom'] as String? ?? ''),
      };
    });
  }

  static const _monthsShort = [
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
  static const _monthsLong = [
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

  String _fmtDateLong(String dateStr) {
    if (dateStr.isEmpty || dateStr == '—') return dateStr;
    for (int i = 0; i < _monthsShort.length; i++) {
      if (dateStr.startsWith(_monthsShort[i])) {
        return dateStr.replaceFirst(_monthsShort[i], _monthsLong[i]);
      }
    }
    final slash = dateStr.split('/');
    if (slash.length == 3) {
      final m = int.tryParse(slash[0]);
      final d = int.tryParse(slash[1]);
      final y = int.tryParse(slash[2]);
      if (m != null && d != null && y != null && m >= 1 && m <= 12) {
        return '${_monthsLong[m - 1]} $d, $y';
      }
    }
    final dt = DateTime.tryParse(dateStr);
    if (dt != null) return '${_monthsLong[dt.month - 1]} ${dt.day}, ${dt.year}';
    return dateStr;
  }

  String _cleanTxnDesc(String raw) {
    if (raw.isEmpty || raw == '—') return raw;
    var d = raw
        .replaceAll(
          RegExp(r'for maintenance SVC-\d+\s*[—\-]\s*', caseSensitive: false),
          'for ',
        )
        .replaceAll(
          RegExp(r'for maintenance SVC-\d+', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'\s*SVC-\d+\s*', caseSensitive: false), '')
        .replaceAll(
          RegExp(
            r'for maintenance\s+[A-Za-z0-9]{15,}\s*[—\-]\s*',
            caseSensitive: false,
          ),
          'for ',
        )
        .replaceAll(
          RegExp(r'for maintenance\s+[A-Za-z0-9]{15,}', caseSensitive: false),
          '',
        )
        .replaceAllMapped(
          RegExp(
            r'^(Stock received|Initial stock received)\s*[—\-]\s*.+$',
            caseSensitive: false,
          ),
          (m) => m.group(1) ?? '',
        )
        .trim();
    if (d.isEmpty) d = '—';
    final issuedMatch = RegExp(
      r'^(Issued (?:to|for)\s+\S+)\s*—\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(d);
    if (issuedMatch != null) d = issuedMatch.group(1)!.trim();
    return d;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('vehicles').snapshots(),
      builder: (context, vehSnapshot) {
        // Build vehMap immediately, even during loading
        final vehMap = <String, String>{};
        if (vehSnapshot.hasData) {
          for (final d in vehSnapshot.data!.docs) {
            final data = d.data() as Map<String, dynamic>;
            final plate = (data['plate'] as String? ?? '').toUpperCase();
            final desc = data['desc'] as String? ?? '';
            if (plate.isNotEmpty) vehMap[plate] = desc;
          }
        }

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('transactions')
              .orderBy('createdAt', descending: true)
              .limit(100)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }

            // Show loading indicator on first load
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final docs = snapshot.data?.docs ?? [];
            final txns = docs.map((d) {
              final data = d.data() as Map<String, dynamic>;
              return {
                'id': d.id,
                'date': data['date'] as String? ?? '—',
                'item': data['item'] as String? ?? '—',
                'desc': data['desc'] as String? ?? '—',
                'type': data['type'] as String? ?? 'IN',
                'qty': data['qty'] as String? ?? '0',
                'by': data['by'] as String? ?? '—',
                'commodityGroup': data['commodityGroup'] as String? ?? '',
                'uom': data['uom'] as String? ?? '',
                'assetDesc': data['assetDesc'] as String? ?? '',
                'plate': data['plate'] as String? ?? '',
              };
            }).toList();

            // Apply external search if provided
            final activeQuery = widget.searchQuery.toLowerCase();
            final searched = activeQuery.isEmpty
                ? txns
                : txns
                      .where(
                        (t) =>
                            (t['item'] ?? '').toLowerCase().contains(
                              activeQuery,
                            ) ||
                            (t['plate'] ?? '').toLowerCase().contains(
                              activeQuery,
                            ) ||
                            (t['by'] ?? '').toLowerCase().contains(activeQuery),
                      )
                      .toList();

            final totalIn = searched.where((t) => t['type'] == 'IN').length;
            final totalOut = searched.where((t) => t['type'] == 'OUT').length;
            final filtered = _txnFilter == 'all'
                ? searched
                : searched.where((t) => t['type'] == _txnFilter).toList();

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      _stat(
                        'Total',
                        '${searched.length}',
                        Icons.swap_horiz,
                        Colors.blue,
                        'all',
                      ),
                      const SizedBox(width: 8),
                      _stat(
                        'Stock In',
                        '$totalIn',
                        Icons.download_outlined,
                        const Color(0xFF003087),
                        'IN',
                      ),
                      const SizedBox(width: 8),
                      _stat(
                        'Stock Out',
                        '$totalOut',
                        Icons.upload_outlined,
                        _red,
                        'OUT',
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(
                          child: Text(
                            'No transactions yet.',
                            style: TextStyle(color: Color(0xFF718096)),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) => _txnCard(filtered[i], vehMap),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _stat(
    String label,
    String value,
    IconData icon,
    Color color,
    String filter,
  ) {
    final isActive = _txnFilter == filter;
    return Expanded(
      child: GestureDetector(
        onTap: () =>
            setState(() => _txnFilter = _txnFilter == filter ? 'all' : filter),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: isActive ? color.withOpacity(0.08) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isActive ? color : Colors.transparent,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6),
            ],
          ),
          child: Column(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 15),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                label,
                style: const TextStyle(fontSize: 9, color: Color(0xFF718096)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _txnCard(Map<String, dynamic> t, Map<String, String> vehMap) {
    final isIn = (t['type'] as String) == 'IN';
    final typeColor = isIn ? const Color(0xFF003087) : _red;
    final cleanDesc = _cleanTxnDesc(t['desc'] ?? '—');

    String vehicleDesc = t['assetDesc'] ?? '';
    if (vehicleDesc.isEmpty) {
      final storedPlate = (t['plate'] ?? '').toUpperCase();
      if (storedPlate.isNotEmpty) vehicleDesc = vehMap[storedPlate] ?? '';
      if (vehicleDesc.isEmpty) {
        final rawDesc = t['desc'] ?? '';
        String extractedPlate = '';
        final emMatch = RegExp(r'—\s*([A-Z0-9][\w\-]*)').firstMatch(rawDesc);
        if (emMatch != null)
          extractedPlate = emMatch.group(1)?.toUpperCase() ?? '';
        if (extractedPlate.isEmpty) {
          final issMatch = RegExp(
            r'Issued (?:to|for)\s+([A-Z0-9][\w\-]*)',
            caseSensitive: false,
          ).firstMatch(rawDesc);
          if (issMatch != null) {
            final cand = issMatch.group(1) ?? '';
            if (cand.toLowerCase() != 'maintenance')
              extractedPlate = cand.toUpperCase();
          }
        }
        if (extractedPlate.isNotEmpty)
          vehicleDesc = vehMap[extractedPlate] ?? '';
      }
    }

    return GestureDetector(
      onTap: () => _showDetail(t),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t['item']!,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  Builder(
                    builder: (_) {
                      final uom = (t['uom'] ?? '').isNotEmpty
                          ? t['uom']!
                          : (_itemUomMap[t['item']] ?? '');
                      if (uom.isEmpty) return const SizedBox.shrink();
                      return Text(
                        uom,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF4a5568),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_outlined,
                        size: 10,
                        color: Color(0xFF718096),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        _fmtDateLong(t['date']!),
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  t['qty']!,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: typeColor,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: typeColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isIn ? 'IN' : 'OUT',
                    style: TextStyle(
                      fontSize: 10,
                      color: typeColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFFa0aec0)),
          ],
        ),
      ),
    );
  }

  void _showDetail(Map<String, dynamic> t) {
    final isIn = (t['type'] as String) == 'IN';
    final typeColor = isIn ? const Color(0xFF003087) : _red;
    final String commodityGroup = t['commodityGroup'] ?? '';
    final String assetDesc = t['assetDesc'] ?? '';
    final String plate = t['plate'] ?? '';

    Future<(String, String)> lookup() async {
      String cg = commodityGroup;
      String vDesc = assetDesc;
      final itemName = t['item'] ?? '';
      if (cg.isEmpty && itemName.isNotEmpty && itemName != '—') {
        final snap = await FirebaseFirestore.instance
            .collection('item_master')
            .where('name', isEqualTo: itemName)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty)
          cg = (snap.docs.first.data()['group'] as String?) ?? '—';
      }
      if (cg.isEmpty) cg = '—';
      if (vDesc.isEmpty && plate.isNotEmpty) {
        final vSnap = await FirebaseFirestore.instance
            .collection('vehicles')
            .where('plate', isEqualTo: plate)
            .limit(1)
            .get();
        if (vSnap.docs.isNotEmpty)
          vDesc = (vSnap.docs.first.data()['desc'] as String?) ?? '';
      }
      if (vDesc.isEmpty) {
        final desc = t['desc'] ?? '';
        String ep = '';
        final m1 = RegExp(r'—\s*([A-Z0-9][\w\-]*)').firstMatch(desc);
        if (m1 != null) ep = m1.group(1) ?? '';
        if (ep.isEmpty) {
          final m2 = RegExp(
            r'Issued (?:to|for)\s+([A-Z0-9][\w\-]*)',
            caseSensitive: false,
          ).firstMatch(desc);
          if (m2 != null) {
            final cand = m2.group(1) ?? '';
            if (cand.toLowerCase() != 'maintenance') ep = cand;
          }
        }
        if (ep.isNotEmpty) {
          final vSnap = await FirebaseFirestore.instance
              .collection('vehicles')
              .where('plate', isEqualTo: ep.toUpperCase())
              .limit(1)
              .get();
          if (vSnap.docs.isNotEmpty)
            vDesc = (vSnap.docs.first.data()['desc'] as String?) ?? '';
        }
      }
      return (cg, vDesc);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => FutureBuilder<(String, String)>(
        future: lookup(),
        builder: (context, snap) {
          final cg =
              snap.data?.$1 ??
              (commodityGroup.isNotEmpty ? commodityGroup : '—');
          final vehDesc = snap.data?.$2 ?? assetDesc;
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.55,
            maxChildSize: 0.75,
            builder: (_, ctrl) => SingleChildScrollView(
              controller: ctrl,
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                    decoration: BoxDecoration(
                      color: typeColor,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t['item']!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Builder(
                                builder: (_) {
                                  final uom = (t['uom'] ?? '').isNotEmpty
                                      ? t['uom']!
                                      : (_itemUomMap[t['item']] ?? '');
                                  return Text(
                                    uom.isNotEmpty
                                        ? uom
                                        : (isIn
                                              ? 'Stock In (Received)'
                                              : 'Stock Out (Issued)'),
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  );
                                },
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
                        _row('Item', t['item'] ?? '—'),
                        _row('Commodity Group', cg),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(
                                width: 120,
                                child: Text(
                                  'Description',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF718096),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _cleanTxnDesc(t['desc'] ?? '—'),
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1a202c),
                                      ),
                                    ),
                                    if (vehDesc.isNotEmpty)
                                      Text(
                                        vehDesc,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF718096),
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        _row(
                          'Type',
                          isIn ? 'Stock In (Received)' : 'Stock Out (Issued)',
                        ),
                        _row('Quantity', t['qty'] ?? '—'),
                        _row('Date', _fmtDateLong(t['date'] ?? '—')),
                        _row('Performed By', t['by'] ?? '—'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
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
