import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'login.dart';
import 'admin_inventory_hub.dart';
import 'admin_inventory_stock.dart';
import 'admin_vehicles_list.dart';
import 'admin_vehicle_maintenance.dart';
import 'profile.dart';
import 'admin_users.dart';
import 'admin_dss.dart';
import 'notifications.dart';
import 'admin_rag_ai.dart';
import 'admin_domain_management.dart';
import 'customer_smart_ai.dart';
import 'admin_archive.dart';
import 'barcode_scanner_screen.dart';
import 'admin_service_bookings.dart';
import 'admin_issuances.dart';
import 'admin_bottomnavbar.dart';
import 'sync_indicator.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _currentIndex = 0;
  static const _red = Color(0xFFE8001C);
  static const _bg = Color(0xFFF7F8FA);
  String _initials = '?';
  String? _photoUrl;
  String _userName = '';

  @override
  void initState() {
    super.initState();
    _loadInitials();
  }

  Future<void> _loadInitials() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = doc.data() ?? {};
    final name = data['name'] as String? ?? '';
    final photo = data['photoUrl'] as String?;
    String ini = '?';
    if (name.isNotEmpty) {
      final parts = name.trim().split(' ');
      ini = parts.length >= 2
          ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
          : parts[0][0].toUpperCase();
    }
    if (mounted) setState(() { _initials = ini; _photoUrl = photo; _userName = name; });
  }

  final _navItems = const [
    (icon: Icons.dashboard_outlined, label: 'Dashboard'),
    (icon: Icons.inventory_2_outlined, label: 'Inventory'),
    (icon: Icons.directions_car_outlined, label: 'Vehicles'),
    (icon: Icons.more_horiz, label: 'More'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildTopBar(),
      body: _buildBody(),
      floatingActionButton: Tooltip(
        message: 'AI Assistant',
        child: FloatingActionButton(
          heroTag: 'admin_dashboard_fab',
          onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const AdminSmartReports())),
          backgroundColor: Colors.white,
          shape: const CircleBorder(),
          elevation: 6,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // AI logo fills the FAB
              ClipOval(
                child: Image.asset(
                  'assets/img/AI_LOGO.png',
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                ),
              ),
              // Red border ring
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _red, width: 2.5),
                ),
              ),
              // Green online dot — bottom-right
              Positioned(
                bottom: 3,
                right: 3,
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF22c55e),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [BoxShadow(
                      color: const Color(0xFF22c55e).withOpacity(0.7),
                      blurRadius: 5,
                    )],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: AdminBottomNavBar(
        currentIndex: _currentIndex,
        onTap: (i) {
          if (i == 1) {
            // Inventory → full-screen hub with own AppBar + tabs
            Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminInventoryHub()));
          } else if (i == 2) {
            // Vehicles → full-screen with own AppBar + tabs
            Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminVehiclesList()));
          } else {
            setState(() => _currentIndex = i);
          }
        },
      ),
    );
  }

  PreferredSizeWidget _buildTopBar() {
    // When on Vehicles tab, show the sub-tab name as the title
    final displayTitle = _userName.isNotEmpty ? _userName : 'Admin Portal';

    return AppBar(
      backgroundColor: _red,
      elevation: 0,
      automaticallyImplyLeading: false,
      title: Row(children: [
        GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UserProfile(role: UserRole.admin)))
              .then((_) => _loadInitials()),
          child: CircleAvatar(radius: 18, backgroundColor: Colors.white24,
            backgroundImage: _photoUrl != null ? NetworkImage(_photoUrl!) : null,
            child: _photoUrl == null
                ? Text(_initials, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold))
                : null),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(displayTitle,
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
          overflow: TextOverflow.ellipsis)),
      ]),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: NotifBadge(
            role: NotificationRole.admin,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AppNotifications(role: NotificationRole.admin))),
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildBody() {
    switch (_currentIndex) {
      case 0: return _buildDashboard();
      case 1: return const SizedBox.shrink(); // Inventory is pushed as full-screen AdminInventoryHub
      case 3: return _buildMore();
      default: return _buildDashboard();
    }
  }

  // ── DASHBOARD ──
  Widget _buildDashboard() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('maintenance')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, maintSnap) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('stock_inventory').snapshots(),
          builder: (context, stockSnap) {
            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('vehicles').snapshots(),
              builder: (context, vehicleSnap) {
                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('transactions')
                      .orderBy('createdAt', descending: true)
                      .snapshots(),
                  builder: (context, txnSnap) {
                    return StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('issuances')
                          .snapshots(),
                      builder: (context, issSnap) {
                        return StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection('users')
                              .snapshots(),
                          builder: (context, usersSnap) {
                final maintDocs = maintSnap.data?.docs ?? [];
                final allServices = maintDocs.map((d) {
                  final data = d.data() as Map<String, dynamic>;
                  return {...data, 'docId': d.id};
                }).toList();

                // Only count Completed services in charts
                final completedServices = allServices
                    .where((s) => (s['status'] as String? ?? '').toLowerCase() == 'completed')
                    .toList();

                // Stats
                final totalVehicles = vehicleSnap.data?.docs.length ?? 0;
                final totalUsers = usersSnap.data?.docs.length ?? 0;
                final stockDocs = stockSnap.data?.docs ?? [];
                final lowStock = stockDocs.where((d) {
                  final data = d.data() as Map<String, dynamic>;
                  final stock = (data['stock'] as num?)?.toInt() ?? 0;
                  final min = (data['min'] as num?)?.toInt() ?? 0;
                  return (data['status'] as String? ?? '') == 'Low' || (min > 0 && stock <= min);
                }).length;
                final vehicleDocs = vehicleSnap.data?.docs ?? [];

                // Services today
                final now = DateTime.now();
                const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
                final todayFormatted = '${months[now.month - 1]} ${now.day}, ${now.year}';
                final servicesToday = allServices.where((s) =>
                  (s['date'] as String? ?? '') == todayFormatted).length;

                // Count assets with PMS due within the next 7 days (0–7) using the
                // EXACT same logic as the DSS PMS tab (admin_dss.dart):
                // nextPMS is computed from lastSvcDate + svcFreq months, then
                // compared midnight-to-midnight.
                final _todayMidnight = DateTime(now.year, now.month, now.day);

                // Returns daysUntil (negative = overdue) for a vehicle doc,
                // mirroring dssAnalyzePMS() in admin.js and the DSS tab in Dart.
                int _computeDiff(Map<String, dynamic> data) {
                  final status = (data['status'] as String? ?? '').toLowerCase();
                  if (status == 'maintenance' || status == 'under maintenance') return 99999;
                  // Prefer stored nextPMSDue; fall back to computing from lastSvcDate + svcFreq
                  String? nextPMSStr = data['nextPMSDue'] as String?;
                  if (nextPMSStr == null || nextPMSStr.isEmpty) {
                    final lastSvc = data['lastSvcDate'] as String? ?? data['lastServiceDate'] as String? ?? '';
                    final freq = int.tryParse((data['svcFreq'] ?? data['serviceFrequency'] ?? '').toString()) ?? 0;
                    if (lastSvc.isNotEmpty && freq > 0) {
                      final lastDate = DateTime.tryParse(lastSvc);
                      if (lastDate != null) {
                        final next = DateTime(lastDate.year, lastDate.month + freq, lastDate.day);
                        nextPMSStr = '${next.year}-${next.month.toString().padLeft(2,'0')}-${next.day.toString().padLeft(2,'0')}';
                      }
                    }
                  }
                  if (nextPMSStr == null || nextPMSStr.isEmpty) return 99999;
                  final due = DateTime.tryParse(nextPMSStr);
                  if (due == null) return 99999;
                  final dueMidnight = DateTime(due.year, due.month, due.day);
                  return dueMidnight.difference(_todayMidnight).inDays;
                }

                final dueForPms = vehicleDocs.where((d) {
                  final diff = _computeDiff(d.data() as Map<String, dynamic>);
                  return diff >= 0 && diff <= 7;
                }).length;

                final isLoading = maintSnap.connectionState == ConnectionState.waiting ||
                    stockSnap.connectionState == ConnectionState.waiting ||
                    vehicleSnap.connectionState == ConnectionState.waiting ||
                    txnSnap.connectionState == ConnectionState.waiting ||
                    issSnap.connectionState == ConnectionState.waiting ||
                    usersSnap.connectionState == ConnectionState.waiting;

                // ── Chart 1: Stacked bar — Services by Type, last 7 days ──
                final Map<String, String> dayKeyToLabel = {};
                final List<String> last7Keys = [];
                final List<String> last7Labels = [];
                for (int i = 6; i >= 0; i--) {
                  final d = now.subtract(Duration(days: i));
                  final key = '${months[d.month - 1]} ${d.day}, ${d.year}';
                  final label = '${months[d.month - 1].substring(0, 3)}\n${d.day}';
                  last7Keys.add(key);
                  last7Labels.add(label);
                  dayKeyToLabel[key] = label;
                }

                // Collect all service type names from svcRows (completed only)
                final Map<String, int> typeCount = {};
                for (final s in completedServices) {
                  final rows = s['svcRows'] as List? ?? [];
                  if (rows.isNotEmpty) {
                    for (final r in rows) {
                      final name = ((r as Map)['name'] as String? ?? '').trim();
                      if (name.isNotEmpty) typeCount[name] = (typeCount[name] ?? 0) + 1;
                    }
                  } else {
                    final name = (s['desc'] as String? ?? '').trim();
                    if (name.isNotEmpty) typeCount[name] = (typeCount[name] ?? 0) + 1;
                  }
                }
                final topTypes = (typeCount.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value)))
                  .take(4).map((e) => e.key).toList();
                final allTypes = [...topTypes, if (typeCount.length > 4) 'Others'];
                const typeColors = [
                  Color(0xFF3b82f6), Color(0xFF22c55e),
                  Color(0xFFf59e0b), Color(0xFFE8001C), Color(0xFF7c3aed),
                ];

                // Count per type per day (completed services only)
                Map<String, List<double>> typeDataMap = {};
                for (final type in allTypes) {
                  typeDataMap[type] = List.generate(7, (di) {
                    final key = last7Keys[di];
                    final dayServices = completedServices.where((s) =>
                      (s['date'] as String? ?? '') == key).toList();
                    return dayServices.fold<double>(0, (acc, s) {
                      final rows = s['svcRows'] as List? ?? [];
                      if (rows.isNotEmpty) {
                        return acc + rows.where((r) {
                          final n = ((r as Map)['name'] as String? ?? '').trim();
                          return type == 'Others' ? !topTypes.contains(n) : n == type;
                        }).length;
                      } else {
                        final n = (s['desc'] as String? ?? '').trim();
                        if (type == 'Others') return acc + (topTypes.contains(n) ? 0 : 1);
                        return acc + (n == type ? 1 : 0);
                      }
                    });
                  });
                }

                // Build stacked max Y (still needed for chart scale)
                double stackedMaxY = 1;
                for (int di = 0; di < 7; di++) {
                  double cumulative = 0;
                  for (final type in allTypes) {
                    cumulative += typeDataMap[type]![di];
                  }
                  if (cumulative > stackedMaxY) stackedMaxY = cumulative;
                }

                // Total completed services in the last 7 days (for badge)
                final total7 = last7Keys.fold<int>(0, (s, k) =>
                  s + completedServices.where((sv) => (sv['date'] as String? ?? '') == k).length);

                // ── Chart 2: Vehicle status donut ──
                // Mirrors admin_dss.dart exactly: maintenance first, then date-math.
                int activeCount = 0, overdueCount = 0, dueSoonCount = 0, maintenanceCount = 0;
                for (final d in vehicleDocs) {
                  final data = d.data() as Map<String, dynamic>;
                  final status = (data['status'] as String? ?? '').toLowerCase();
                  if (status == 'maintenance' || status == 'under maintenance') {
                    maintenanceCount++;
                  } else {
                    final diff = _computeDiff(data);
                    if (diff == 99999) {
                      activeCount++; // no PMS date → treat as active
                    } else if (diff < 0) {
                      overdueCount++;
                    } else if (diff == 0 || diff <= 7) {
                      dueSoonCount++; // "Due Today" + "Due This Week" → same orange slice
                    } else {
                      activeCount++;
                    }
                  }
                }

                // ── Chart 3: Stock In vs Stock Out — last 12 months ──
                final allTxns = txnSnap.data?.docs
                    .map((d) => d.data() as Map<String, dynamic>).toList() ?? [];
                final List<String> monthLabels12 = [];
                final List<({int month, int year})> monthKeys12 = [];
                for (int i = 11; i >= 0; i--) {
                  final d = DateTime(now.year, now.month - i, 1);
                  monthLabels12.add(months[d.month - 1]);
                  monthKeys12.add((month: d.month - 1, year: d.year));
                }

                int parseTxnMonth(Map<String, dynamic> t) {
                  // Try date string first: "Jan 5, 2025"
                  final dateStr = t['date'] as String? ?? '';
                  if (dateStr.isNotEmpty) {
                    final parts = dateStr.split(' ');
                    if (parts.length >= 3) {
                      final m = months.indexOf(parts[0]);
                      if (m != -1) return m;
                    }
                  }
                  // Fallback: createdAt Firestore Timestamp
                  final ts = t['createdAt'];
                  if (ts != null) {
                    DateTime? dt;
                    if (ts is DateTime) dt = ts;
                    else {
                      try { dt = (ts as dynamic).toDate() as DateTime; } catch (_) {}
                    }
                    if (dt != null) return dt.month - 1;
                  }
                  return -1;
                }
                int parseTxnYear(Map<String, dynamic> t) {
                  final dateStr = t['date'] as String? ?? '';
                  if (dateStr.isNotEmpty) {
                    final parts = dateStr.split(' ');
                    if (parts.length >= 3) {
                      final y = int.tryParse(parts[2]);
                      if (y != null) return y;
                    }
                  }
                  final ts = t['createdAt'];
                  if (ts != null) {
                    DateTime? dt;
                    if (ts is DateTime) dt = ts;
                    else {
                      try { dt = (ts as dynamic).toDate() as DateTime; } catch (_) {}
                    }
                    if (dt != null) return dt.year;
                  }
                  return -1;
                }
                double parseQty(dynamic raw) {
                  if (raw is num) return raw.abs().toDouble();
                  final str = raw?.toString() ?? '0';
                  // Strip everything except digits and decimal point
                  return double.tryParse(str.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
                }

                final stockInByMonth = monthKeys12.map((mk) =>
                  allTxns.where((t) {
                    if ((t['type'] as String? ?? '').toUpperCase() != 'IN') return false;
                    final desc = (t['desc'] as String? ?? '').toLowerCase();
                    if (desc.contains('initial stock')) return false;
                    return parseTxnMonth(t) == mk.month && parseTxnYear(t) == mk.year;
                  }).fold<double>(0, (s, t) => s + parseQty(t['qty'] ?? t['quantity']))
                ).toList();

                final stockOutByMonth = monthKeys12.map((mk) =>
                  allTxns.where((t) {
                    if ((t['type'] as String? ?? '').toUpperCase() != 'OUT') return false;
                    return parseTxnMonth(t) == mk.month && parseTxnYear(t) == mk.year;
                  }).fold<double>(0, (s, t) => s + parseQty(t['qty'] ?? t['quantity']))
                ).toList();

                final lineMaxY = ([...stockInByMonth, ...stockOutByMonth, 1.0]
                  .reduce((a, b) => a > b ? a : b)) + 2;

                // ── Chart 4: Top 10 Most Used Parts (Current Month) ──
                // Mirrors the website: materials only, current month, aggregated by itemName.
                final allIssuances = issSnap.data?.docs
                    .map((d) => d.data() as Map<String, dynamic>).toList() ?? [];
                final Map<String, double> partUsage = {};
                for (final iss in allIssuances) {
                  // Skip services — only count materials
                  final itemType = (iss['itemType'] as String? ?? '').toLowerCase();
                  if (itemType == 'service') continue;
                  // Filter to current month — parse "Jan 5, 2025" format first,
                  // fall back to createdAt Timestamp (same logic as website).
                  final dateStr = iss['date'] as String? ?? '';
                  bool inCurrentMonth = false;
                  if (dateStr.isNotEmpty) {
                    final parts = dateStr.split(' ');
                    if (parts.length >= 3) {
                      final m = months.indexOf(parts[0]);
                      final y = int.tryParse(parts[2]) ?? -1;
                      inCurrentMonth = m == now.month - 1 && y == now.year;
                    }
                  }
                  if (!inCurrentMonth) {
                    // Fallback: createdAt Timestamp
                    final ts = iss['createdAt'];
                    if (ts != null) {
                      try {
                        final dt = (ts as dynamic).toDate() as DateTime;
                        inCurrentMonth = dt.month == now.month && dt.year == now.year;
                      } catch (_) {}
                    }
                  }
                  if (!inCurrentMonth) continue;
                  // itemName field (website stores as 'itemName')
                  final rawName = iss['itemName'] ?? iss['item'];
                  final name = rawName?.toString() ?? '';
                  if (name.isEmpty || name == '—') continue;
                  // qty stored as string e.g. "3"; quantity stored as number by some paths
                  final qty = parseQty(iss['quantity'] ?? iss['qty'] ?? 0);
                  if (qty > 0) partUsage[name] = (partUsage[name] ?? 0) + qty;
                }
                final sortedParts = (partUsage.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value)))
                  .take(10).toList();
                final partsMaxY = sortedParts.isEmpty ? 5.0
                    : sortedParts.first.value + 1;

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // ── Stat cards (5 cards, clickable, matching website) ──
                    GridView.count(
                      crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.4,
                      children: [
                        _clickableStatCard(
                          label: 'Total Vehicles',
                          value: isLoading ? '…' : '$totalVehicles',
                          icon: Icons.directions_car_outlined,
                          color: const Color(0xFF003087),
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminVehiclesList())),
                        ),
                        _clickableStatCard(
                          label: 'PMS This Week',
                          value: isLoading ? '…' : '$dueForPms',
                          icon: Icons.build_outlined,
                          color: Colors.orange,
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminDSS(initialTab: 1))),
                        ),
                        _clickableStatCard(
                          label: 'Low Stock',
                          value: isLoading ? '…' : '$lowStock',
                          icon: Icons.warning_amber_outlined,
                          color: _red,
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminInventoryStock())),
                        ),
                        _clickableStatCard(
                          label: 'Services Today',
                          value: isLoading ? '…' : '$servicesToday',
                          icon: Icons.check_circle_outline,
                          color: const Color(0xFF2c7a7b),
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminVehiclesList())),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Total Users — full-width card (5th stat, purple like website)
                    _clickableStatCard(
                      label: 'Total Users',
                      value: isLoading ? '…' : '$totalUsers',
                      icon: Icons.people_outline,
                      color: const Color(0xFF7c3aed),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminUsers())),
                      fullWidth: true,
                    ),
                    const SizedBox(height: 20),

                    // ── Chart 1: Stacked Bar — Services by Type, last 7 days ──
                    // Website-style: gradient icon, inline legend+badge header, flat stacked bars
                    Builder(builder: (context) {
                      final total7 = last7Keys.fold<int>(0, (s, k) =>
                        s + allServices.where((sv) => (sv['date'] as String? ?? '') == k).length);
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFe2e8f0)),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 2))],
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          // ── Header row: icon + title/sub + badge ──
                          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            // Gradient icon
                            Container(
                              width: 32, height: 32,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFE8001C), Color(0xFFc0001a)],
                                  begin: Alignment.topLeft, end: Alignment.bottomRight),
                                borderRadius: BorderRadius.circular(9),
                                boxShadow: [BoxShadow(color: const Color(0xFFE8001C).withOpacity(0.35), blurRadius: 6, offset: const Offset(0, 2))],
                              ),
                              child: const Icon(Icons.bar_chart_rounded, color: Colors.white, size: 15),
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Text('Services by Type — Last 7 Days',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1a202c))),
                              const Text('Completed service types per day',
                                style: TextStyle(fontSize: 10, color: Color(0xFF718096))),
                            ])),
                            // Badge: total count
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFfff5f5),
                                borderRadius: BorderRadius.circular(20)),
                              child: Text('$total7 total',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFE8001C))),
                            ),
                          ]),
                          const SizedBox(height: 10),
                          // ── Inline legend (flex-wrap style) ──
                          if (allTypes.isNotEmpty)
                            Wrap(spacing: 12, runSpacing: 4, children: List.generate(allTypes.length, (i) =>
                              Row(mainAxisSize: MainAxisSize.min, children: [
                                Container(width: 10, height: 10,
                                  decoration: BoxDecoration(
                                    color: typeColors[i % typeColors.length],
                                    borderRadius: BorderRadius.circular(3))),
                                const SizedBox(width: 4),
                                Text(
                                  allTypes[i].length > 14 ? '${allTypes[i].substring(0, 12)}…' : allTypes[i],
                                  style: const TextStyle(fontSize: 9, color: Color(0xFF4a5568))),
                              ]),
                            )),
                          const SizedBox(height: 12),
                          // ── Chart ──
                          isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : SizedBox(
                                height: 210,
                                child: BarChart(
                                  BarChartData(
                                    maxY: stackedMaxY + 1,
                                    groupsSpace: 8,
                                    gridData: FlGridData(
                                      show: true, drawVerticalLine: false,
                                      getDrawingHorizontalLine: (_) => const FlLine(color: Color(0xFFf7f8fa), strokeWidth: 1.5),
                                    ),
                                    borderData: FlBorderData(show: false),
                                    titlesData: FlTitlesData(
                                      leftTitles: AxisTitles(sideTitles: SideTitles(
                                        showTitles: true, reservedSize: 24,
                                        getTitlesWidget: (v, meta) {
                                          if (v != v.roundToDouble()) return const SizedBox.shrink();
                                          return Text(v.toInt().toString(),
                                            style: const TextStyle(fontSize: 9, color: Color(0xFFa0aec0)));
                                        },
                                      )),
                                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                      bottomTitles: AxisTitles(sideTitles: SideTitles(
                                        showTitles: true, reservedSize: 28,
                                        getTitlesWidget: (v, _) {
                                          final i = v.toInt();
                                          if (i < 0 || i >= last7Labels.length) return const SizedBox.shrink();
                                          return Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Text(last7Labels[i], textAlign: TextAlign.center,
                                              style: const TextStyle(fontSize: 9, color: Color(0xFFa0aec0))));
                                        },
                                      )),
                                    ),
                                    barTouchData: BarTouchData(
                                      touchTooltipData: BarTouchTooltipData(
                                        getTooltipColor: (_) => const Color(0xFF1a202c),
                                        tooltipRoundedRadius: 10,
                                        tooltipPadding: const EdgeInsets.all(10),
                                        getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                          // Build multi-line tooltip showing each type + total
                                          final di = group.x;
                                          final lines = <String>[];
                                          double total = 0;
                                          for (int ti = 0; ti < allTypes.length; ti++) {
                                            final val = typeDataMap[allTypes[ti]]![di];
                                            if (val > 0) {
                                              lines.add('${allTypes[ti]}: ${val.toInt()}');
                                              total += val;
                                            }
                                          }
                                          if (total == 0) return null;
                                          lines.add('─────────');
                                          lines.add('Total: ${total.toInt()} service${total != 1 ? 's' : ''}');
                                          return BarTooltipItem(
                                            last7Labels[di].replaceAll('\n', ' ') + '\n',
                                            const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                                            children: lines.map((l) => TextSpan(
                                              text: '$l\n',
                                              style: TextStyle(
                                                color: l.startsWith('Total') ? Colors.white : Colors.white70,
                                                fontWeight: l.startsWith('Total') ? FontWeight.w700 : FontWeight.normal,
                                                fontSize: 10),
                                            )).toList(),
                                          );
                                        },
                                      ),
                                    ),
                                    barGroups: List.generate(7, (di) {
                                      double cumulative = 0;
                                      final rods = <BarChartRodStackItem>[];
                                      for (int ti = 0; ti < allTypes.length; ti++) {
                                        final val = typeDataMap[allTypes[ti]]![di];
                                        if (val > 0) {
                                          rods.add(BarChartRodStackItem(
                                            cumulative, cumulative + val,
                                            typeColors[ti % typeColors.length],
                                            BorderSide.none,
                                          ));
                                          cumulative += val;
                                        }
                                      }
                                      return BarChartGroupData(
                                        x: di,
                                        barRods: [
                                          BarChartRodData(
                                            toY: cumulative == 0 ? 0.001 : cumulative,
                                            rodStackItems: rods,
                                            width: 22,
                                            // Rounded top only on the topmost segment
                                            borderRadius: cumulative > 0
                                              ? const BorderRadius.vertical(top: Radius.circular(5))
                                              : BorderRadius.zero,
                                            color: Colors.transparent,
                                            backDrawRodData: BackgroundBarChartRodData(
                                              show: true,
                                              toY: stackedMaxY + 1,
                                              color: const Color(0xFFF7F8FA),
                                            ),
                                          ),
                                        ],
                                      );
                                    }),
                                  ),
                                ),
                              ),
                        ]),
                      );
                    }),
                    const SizedBox(height: 16),

                    // ── Chart 2: Donut — Vehicle Status ──
                    // Vehicle Status — dark blue gradient icon, center total, website-style legend
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFe2e8f0)),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 2))],
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF003087), Color(0xFF001f5c)],
                                begin: Alignment.topLeft, end: Alignment.bottomRight),
                              borderRadius: BorderRadius.circular(9),
                              boxShadow: [BoxShadow(color: const Color(0xFF003087).withOpacity(0.35), blurRadius: 6, offset: const Offset(0, 2))],
                            ),
                            child: const Icon(Icons.donut_large_rounded, color: Colors.white, size: 15),
                          ),
                          const SizedBox(width: 10),
                          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Vehicle Status', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1a202c))),
                            Text('Fleet health overview', style: TextStyle(fontSize: 10, color: Color(0xFF718096))),
                          ]),
                        ]),
                        const SizedBox(height: 16),
                        isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : totalVehicles == 0
                              ? const Center(child: Padding(
                                  padding: EdgeInsets.all(20),
                                  child: Text('No vehicles yet.', style: TextStyle(color: Color(0xFF718096))),
                                ))
                              : Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                                  SizedBox(
                                    width: 150, height: 150,
                                    child: Stack(alignment: Alignment.center, children: [
                                      PieChart(PieChartData(
                                        sectionsSpace: 3,
                                        centerSpaceRadius: 46,
                                        sections: [
                                          if (activeCount > 0) PieChartSectionData(value: activeCount.toDouble(), color: const Color(0xFF003087), radius: 28, title: ''),
                                          if (dueSoonCount > 0) PieChartSectionData(value: dueSoonCount.toDouble(), color: const Color(0xFFed8936), radius: 28, title: ''),
                                          if (overdueCount > 0) PieChartSectionData(value: overdueCount.toDouble(), color: _red, radius: 28, title: ''),
                                          if (maintenanceCount > 0) PieChartSectionData(value: maintenanceCount.toDouble(), color: const Color(0xFF0d9488), radius: 28, title: ''),
                                        ],
                                      )),
                                      Column(mainAxisSize: MainAxisSize.min, children: [
                                        Text('$totalVehicles', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF1a202c))),
                                        const Text('Vehicles', style: TextStyle(fontSize: 9, color: Color(0xFF718096), fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                                      ]),
                                    ]),
                                  ),
                                  const SizedBox(width: 20),
                                  Expanded(child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _donutLegendRow('Active', activeCount, const Color(0xFF003087)),
                                      _donutLegendRow('Due This Week', dueSoonCount, const Color(0xFFed8936)),
                                      _donutLegendRow('Overdue', overdueCount, _red),
                                      _donutLegendRow('Maintenance', maintenanceCount, const Color(0xFF0d9488)),
                                    ],
                                  )),
                                ]),
                      ]),
                    ),
                    const SizedBox(height: 16),

                    // Stock In vs Stock Out — teal gradient icon, year-range sub, inline legend in header
                    GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminInventoryHub())),
                      child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFe2e8f0)),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 2))],
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF0d9488), Color(0xFF0a7a70)],
                                begin: Alignment.topLeft, end: Alignment.bottomRight),
                              borderRadius: BorderRadius.circular(9),
                              boxShadow: [BoxShadow(color: const Color(0xFF0d9488).withOpacity(0.35), blurRadius: 6, offset: const Offset(0, 2))],
                            ),
                            child: const Icon(Icons.show_chart_rounded, color: Colors.white, size: 15),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Text('Stock In vs Stock Out', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1a202c))),
                            Text(
                              '${months[monthKeys12.first.month]} ${monthKeys12.first.year} – ${months[monthKeys12.last.month]} ${monthKeys12.last.year}',
                              style: const TextStyle(fontSize: 10, color: Color(0xFF718096))),
                          ])),
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            _lineLegendDot(const Color(0xFF003087), 'In'),
                            const SizedBox(width: 10),
                            _lineLegendDot(_red, 'Out'),
                            const SizedBox(width: 8),
                            const Icon(Icons.chevron_right, size: 16, color: Color(0xFFcbd5e0)),
                          ]),
                        ]),
                        const SizedBox(height: 16),
                        isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : allTxns.isEmpty
                              ? const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 24),
                                  child: Center(child: Text('No transactions yet.',
                                    style: TextStyle(color: Color(0xFF718096), fontSize: 13))),
                                )
                              : SizedBox(
                              height: 220,
                              child: LineChart(
                                LineChartData(
                                  minY: 0,
                                  maxY: lineMaxY,
                                  gridData: FlGridData(
                                    show: true, drawVerticalLine: false,
                                    getDrawingHorizontalLine: (_) => const FlLine(color: Color(0xFFf7f8fa), strokeWidth: 1.5),
                                  ),
                                  borderData: FlBorderData(show: false),
                                  titlesData: FlTitlesData(
                                    leftTitles: AxisTitles(sideTitles: SideTitles(
                                      showTitles: true, reservedSize: 28,
                                      getTitlesWidget: (v, meta) {
                                        if (v != v.roundToDouble()) return const SizedBox.shrink();
                                        return Text(v.toInt().toString(), style: const TextStyle(fontSize: 9, color: Color(0xFFa0aec0)));
                                      },
                                    )),
                                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                    bottomTitles: AxisTitles(sideTitles: SideTitles(
                                      showTitles: true, reservedSize: 22,
                                      getTitlesWidget: (v, _) {
                                        final i = v.toInt();
                                        if (i < 0 || i >= monthLabels12.length) return const SizedBox.shrink();
                                        if (i % 2 != 0) return const SizedBox.shrink();
                                        return Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Text(monthLabels12[i], style: const TextStyle(fontSize: 9, color: Color(0xFFa0aec0))));
                                      },
                                    )),
                                  ),
                                  lineTouchData: LineTouchData(
                                    touchTooltipData: LineTouchTooltipData(
                                      getTooltipColor: (_) => const Color(0xFF1a202c),
                                      tooltipRoundedRadius: 10,
                                      tooltipPadding: const EdgeInsets.all(10),
                                      getTooltipItems: (spots) => spots.map((s) {
                                        final label = s.barIndex == 0 ? 'Stock In (Receiving)' : 'Stock Out (Usage)';
                                        return LineTooltipItem(
                                          '  $label: ${s.y.toInt()} units',
                                          TextStyle(color: s.barIndex == 0 ? const Color(0xFF003087) : _red, fontSize: 10, fontWeight: FontWeight.w600),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                  lineBarsData: [
                                    LineChartBarData(
                                      spots: List.generate(12, (i) => FlSpot(i.toDouble(), stockInByMonth[i])),
                                      isCurved: true, curveSmoothness: 0.4,
                                      color: const Color(0xFF003087), barWidth: 2.5,
                                      dotData: FlDotData(show: true,
                                        getDotPainter: (p, x, bar, idx) => FlDotCirclePainter(radius: 4, color: const Color(0xFF003087), strokeWidth: 2, strokeColor: Colors.white)),
                                      belowBarData: BarAreaData(show: true, color: const Color(0xFF003087).withOpacity(0.08)),
                                    ),
                                    LineChartBarData(
                                      spots: List.generate(12, (i) => FlSpot(i.toDouble(), stockOutByMonth[i])),
                                      isCurved: true, curveSmoothness: 0.4,
                                      color: _red, barWidth: 2.5,
                                      dotData: FlDotData(show: true,
                                        getDotPainter: (p, x, bar, idx) => FlDotCirclePainter(radius: 4, color: _red, strokeWidth: 2, strokeColor: Colors.white)),
                                      belowBarData: BarAreaData(show: true, color: _red.withOpacity(0.06)),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                      ]),
                    )),
                    const SizedBox(height: 16),

                    // Top 10 Most Used Parts — purple gradient icon, item-count badge, rich tooltip
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFe2e8f0)),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 2))],
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF7c3aed), Color(0xFF5b21b6)],
                                begin: Alignment.topLeft, end: Alignment.bottomRight),
                              borderRadius: BorderRadius.circular(9),
                              boxShadow: [BoxShadow(color: const Color(0xFF7c3aed).withOpacity(0.35), blurRadius: 6, offset: const Offset(0, 2))],
                            ),
                            child: const Icon(Icons.bar_chart_rounded, color: Colors.white, size: 15),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Text('Top 10 Most Used Parts', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1a202c))),
                            Text('${months[now.month - 1]} ${now.year} · Materials only', style: const TextStyle(fontSize: 10, color: Color(0xFF718096))),
                          ])),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(color: const Color(0xFFf5f3ff), borderRadius: BorderRadius.circular(20)),
                            child: Text('${sortedParts.length} items',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF7c3aed))),
                          ),
                        ]),
                        const SizedBox(height: 16),
                        isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : sortedParts.isEmpty
                              ? const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 24),
                                  child: Center(child: Text(
                                    'No material issuances recorded yet.',
                                    style: TextStyle(color: Color(0xFF718096), fontSize: 13))),
                                )
                              : SizedBox(
                                  height: 220,
                                  child: BarChart(
                                    BarChartData(
                                      maxY: partsMaxY,
                                      groupsSpace: 8,
                                      gridData: FlGridData(
                                        show: true, drawVerticalLine: false,
                                        getDrawingHorizontalLine: (_) => const FlLine(color: Color(0xFFf7f8fa), strokeWidth: 1.5),
                                      ),
                                      borderData: FlBorderData(show: false),
                                      titlesData: FlTitlesData(
                                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                        leftTitles: AxisTitles(sideTitles: SideTitles(
                                          showTitles: true, reservedSize: 24,
                                          getTitlesWidget: (v, meta) {
                                            if (v != v.roundToDouble()) return const SizedBox.shrink();
                                            return Text(v.toInt().toString(), style: const TextStyle(fontSize: 9, color: Color(0xFFa0aec0)));
                                          },
                                        )),
                                        bottomTitles: AxisTitles(sideTitles: SideTitles(
                                          showTitles: true, reservedSize: 44,
                                          getTitlesWidget: (v, _) {
                                            final i = v.toInt();
                                            if (i < 0 || i >= sortedParts.length) return const SizedBox.shrink();
                                            final name = sortedParts[i].key;
                                            final short = name.length > 10 ? '${name.substring(0, 8)}…' : name;
                                            return Padding(
                                              padding: const EdgeInsets.only(top: 6),
                                              child: Text(short, textAlign: TextAlign.center,
                                                style: const TextStyle(fontSize: 9, color: Color(0xFF718096))));
                                          },
                                        )),
                                      ),
                                      barTouchData: BarTouchData(
                                        touchTooltipData: BarTouchTooltipData(
                                          getTooltipColor: (_) => const Color(0xFF1a202c),
                                          tooltipRoundedRadius: 10,
                                          tooltipPadding: const EdgeInsets.all(10),
                                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                            final name = sortedParts[group.x].key;
                                            final qty = rod.toY;
                                            return BarTooltipItem(
                                              '$name\n',
                                              const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                                              children: [TextSpan(
                                                text: '  Used: ${qty.toInt()} unit${qty != 1 ? 's' : ''}',
                                                style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.normal, fontSize: 10),
                                              )],
                                            );
                                          },
                                        ),
                                      ),
                                      barGroups: List.generate(sortedParts.length, (i) {
                                        const palette = [
                                          Color(0xFF7c3aed), Color(0xFF6d28d9), Color(0xFF5b21b6), Color(0xFF4c1d95),
                                          Color(0xFFE8001C), Color(0xFFc0001a), Color(0xFF003087), Color(0xFF1e40af),
                                          Color(0xFF0d9488), Color(0xFF0a7a70),
                                        ];
                                        return BarChartGroupData(
                                          x: i,
                                          barRods: [
                                            BarChartRodData(
                                              toY: sortedParts[i].value,
                                              color: palette[i % palette.length],
                                              width: 20,
                                              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                                            ),
                                          ],
                                        );
                                      }),
                                    ),
                                  ),
                                ),
                      ]),
                    ),
                    const SizedBox(height: 20),

                    // ── Today's services ──
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      _sectionTitle("Today's Services"),
                      TextButton(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminVehiclesList())),
                        child: const Text('See all', style: TextStyle(fontSize: 12, color: Color(0xFF003087)))),
                    ]),
                    const SizedBox(height: 8),
                    if (isLoading)
                      const Center(child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(),
                      ))
                    else if (allServices.where((s) => (s['date'] as String? ?? '') == todayFormatted).isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)]),
                        child: const Center(child: Text('No services for today.',
                          style: TextStyle(color: Color(0xFF718096), fontSize: 13))),
                      )
                    else
                      ...allServices.where((s) => (s['date'] as String? ?? '') == todayFormatted).map((s) {
                        final rows = s['svcRows'] as List?;
                        final serviceName = (rows != null && rows.isNotEmpty)
                            ? (rows.first['name'] as String? ?? '—')
                            : (s['desc'] as String? ?? '—');
                        return _serviceRow(s);
                      }),
                  ]),
                );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _chartCard({required String title, required IconData icon, required Widget child, String? subtitle}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(color: _red.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: _red, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1a202c))),
            if (subtitle != null)
              Text(subtitle, style: const TextStyle(fontSize: 10, color: Color(0xFF718096))),
          ])),
        ]),
        const SizedBox(height: 16),
        child,
      ]),
    );
  }

  Widget _lineLegendDot(Color color, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 16, height: 3, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF4a5568))),
    ]);
  }

  // Website-style donut legend: colored square + label on left, bold count on right
  Widget _donutLegendRow(String label, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Row(children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 7),
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF4a5568))),
        ]),
        const Spacer(),
        Text('$count', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
      ]),
    );
  }

  // Summary chip for the stock line chart footer
  Widget _txnSummaryChip(String label, int count, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.15)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$count', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
            Text(label, style: const TextStyle(fontSize: 9, color: Color(0xFF718096))),
          ]),
        ]),
      ),
    );
  }

  Widget _legendItem(String label, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF4a5568)))),
        Text('$count', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
      ]),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return _clickableStatCard(label: label, value: value, icon: icon, color: color);
  }

  Widget _clickableStatCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
    bool fullWidth = false,
  }) {
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: fullWidth
          ? Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
                Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
              ])),
              if (onTap != null)
                Icon(Icons.chevron_right, color: color.withOpacity(0.4), size: 20),
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.center, mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 34, height: 34,
                decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(height: 6),
              FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color))),
              Text(label, style: const TextStyle(fontSize: 9, color: Color(0xFF718096)), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
            ]),
    );

    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        splashColor: color.withOpacity(0.08),
        highlightColor: color.withOpacity(0.04),
        child: card,
      ),
    );
  }

  Widget _serviceRow(Map<String, dynamic> s) {
    final plate    = s['plate']    as String? ?? '—';
    final mechanic = s['mechanic'] as String? ?? '—';
    final status   = s['status']   as String? ?? '—';
    final rows = s['svcRows'] as List?;
    final serviceName = (rows != null && rows.isNotEmpty)
        ? (rows.first['name'] as String? ?? '—')
        : (s['desc'] as String? ?? '—');

    final statusColor = status == 'Completed' ? Colors.green
        : status == 'Ongoing' ? Colors.orange
        : status == 'Pending' ? const Color(0xFF718096)
        : Colors.green;

    return GestureDetector(
      onTap: () => _showAdminServiceDetails(s),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
        ),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(plate, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            Text('$serviceName • $mechanic', style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
            child: Text(status, style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right, size: 18, color: Color(0xFFa0aec0)),
        ]),
      ),
    );
  }

  void _showAdminServiceDetails(Map<String, dynamic> s) {
    Color statusColor(String st) {
      if (st == 'Completed') return Colors.green;
      if (st == 'Ongoing')   return Colors.orange;
      return const Color(0xFF718096);
    }

    String formatCost(String raw) {
      final clean = raw.replaceAll('₱', '').replaceAll(',', '').trim();
      final val = double.tryParse(clean);
      if (val == null) return raw.startsWith('₱') ? raw : '₱$raw';
      return '₱${val.toStringAsFixed(2)}';
    }

    Widget detailRow(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 130, child: Text(label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF718096), fontWeight: FontWeight.w500))),
        Expanded(child: Text(value.isNotEmpty ? value : '—',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1a202c)))),
      ]),
    );

    Widget rowDetailCard(dynamic r, {required bool isService}) {
      final name     = r['name'] as String? ?? '';
      final qty      = r['qty']  as String? ?? '1';
      final uom      = r['uom']  as String? ?? '';
      final cost     = r['cost'] as String? ?? '0';
      final subtotal = (double.tryParse(cost) ?? 0) * (double.tryParse(qty) ?? 1);
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isService ? const Color(0xFFebf8ff) : const Color(0xFFF0F4FF),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isService ? const Color(0xFF90cdf4) : const Color(0xFFbee3f8)),
        ),
        child: Row(children: [
          Icon(isService ? Icons.build_outlined : Icons.inventory_2_outlined,
            size: 16, color: isService ? const Color(0xFF003087) : _red),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            Text('$qty $uom  •  ₱$cost / unit',
              style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
          ])),
          Text('₱${subtotal.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1a202c))),
        ]),
      );
    }

    final sc = statusColor(s['status'] as String? ?? '');

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => DraggableScrollableSheet(
        expand: false, initialChildSize: 0.6, maxChildSize: 0.92,
        builder: (_, ctrl) => SingleChildScrollView(
          controller: ctrl,
          child: Column(children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              decoration: const BoxDecoration(color: _red,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s['plate'] as String? ?? '—',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(s['desc'] as String? ?? '',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ])),
                GestureDetector(onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close, color: Colors.white)),
              ]),
            ),
            // Body
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                detailRow('Plate Number', s['plate'] as String? ?? ''),
                detailRow('Mechanic',     s['mechanic'] as String? ?? ''),
                detailRow('Service Date', s['date'] as String? ?? ''),
                detailRow('Total Cost',   formatCost(s['cost'] as String? ?? '0')),
                Row(children: [
                  const SizedBox(width: 130, child: Text('Status',
                    style: TextStyle(fontSize: 12, color: Color(0xFF718096), fontWeight: FontWeight.w500))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: sc.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                    child: Text(s['status'] as String? ?? '',
                      style: TextStyle(fontSize: 12, color: sc, fontWeight: FontWeight.w600)),
                  ),
                ]),
                const SizedBox(height: 16),
                // Issues
                if ((s['issues'] as List?)?.isNotEmpty == true) ...[
                  const Text('Vehicle Issues Reported',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF4a5568))),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6,
                    children: (s['issues'] as List).map<Widget>((issue) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF5F5),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFFED7D7), width: 1.5),
                      ),
                      child: Text(issue.toString(),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFE8001C))),
                    )).toList(),
                  ),
                  const SizedBox(height: 16),
                ],
                // Services rendered
                if ((s['svcRows'] as List?)?.isNotEmpty == true) ...[
                  const Text('Services Rendered',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF4a5568))),
                  const SizedBox(height: 8),
                  ...(s['svcRows'] as List)
                      .where((r) => (r['name'] as String? ?? '').isNotEmpty)
                      .map((r) => rowDetailCard(r, isService: true)),
                  const SizedBox(height: 12),
                ],
                // Materials used
                if ((s['matRows'] as List?)?.isNotEmpty == true) ...[
                  const Text('Materials Used',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF4a5568))),
                  const SizedBox(height: 8),
                  ...(s['matRows'] as List)
                      .where((r) => (r['name'] as String? ?? '').isNotEmpty)
                      .map((r) => rowDetailCard(r, isService: false)),
                  const SizedBox(height: 12),
                ],
                // Approve button (Pending)
                if (s['status'] == 'Pending')
                  SizedBox(width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Approve Service'),
                            content: Text('Approve service for ${s['plate']} and set to Ongoing?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                              TextButton(onPressed: () => Navigator.pop(context, true),
                                child: const Text('Approve', style: TextStyle(color: Colors.orange))),
                            ],
                          ),
                        );
                        if (confirm != true) return;
                        final docId = s['docId'] as String? ?? '';
                        if (docId.isEmpty) return;
                        await FirebaseFirestore.instance
                            .collection('maintenance').doc(docId)
                            .update({'status': 'Ongoing'});
                        final plate = (s['plate'] as String? ?? '').trim().toUpperCase();
                        final vSnap = await FirebaseFirestore.instance
                            .collection('vehicles').where('plate', isEqualTo: plate).limit(1).get();
                        if (vSnap.docs.isNotEmpty) {
                          await vSnap.docs.first.reference.update({'status': 'Under Maintenance'});
                        }
                        if (mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: const Row(children: [
                              Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
                              SizedBox(width: 8),
                              Text('Service approved — status set to Ongoing!'),
                            ]),
                            backgroundColor: Colors.orange, behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
                        }
                      },
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: const Text('Approve — Ongoing'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                    )),
                // Complete button (Ongoing)
                if (s['status'] == 'Ongoing') ...[
                  SizedBox(width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Complete Service'),
                            content: Text('Mark service for ${s['plate']} as Completed?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                              TextButton(onPressed: () => Navigator.pop(context, true),
                                child: const Text('Complete', style: TextStyle(color: Colors.green))),
                            ],
                          ),
                        );
                        if (confirm != true) return;
                        final docId = s['docId'] as String? ?? '';
                        if (docId.isEmpty) return;

                        // 1. Update status immediately
                        await FirebaseFirestore.instance
                            .collection('maintenance').doc(docId)
                            .update({'status': 'Completed'});

                        // 2. Close + show success right away
                        if (mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: const Row(children: [
                              Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
                              SizedBox(width: 8),
                              Text('Service marked as Completed!'),
                            ]),
                            backgroundColor: Colors.green, behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
                        }

                        // 3. Background: issuances + stock + vehicle update
                        () async {
                          final uid  = FirebaseAuth.instance.currentUser?.uid ?? '';
                          final uDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
                          final byName = (uDoc.data()?['name'] as String?) ?? 'Admin';
                          final now    = DateTime.now();
                          const _txnMonths = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
                          final dateStr = '${_txnMonths[now.month - 1]} ${now.day}, ${now.year}';
                          final plate   = (s['plate'] as String? ?? '').trim().toUpperCase();
                          for (final r in (s['matRows'] as List<dynamic>? ?? [])) {
                            final name = r['name'] as String? ?? '';
                            final qty  = int.tryParse(r['qty']  as String? ?? '1') ?? 1;
                            final uom  = r['uom']  as String? ?? '';
                            final cost = double.tryParse(r['cost'] as String? ?? '0') ?? 0;
                            if (name.isEmpty || qty <= 0) continue;
                            final iSnap = await FirebaseFirestore.instance
                                .collection('item_master').where('name', isEqualTo: name).limit(1).get();
                            final iData = iSnap.docs.isNotEmpty ? iSnap.docs.first.data() as Map<String, dynamic> : <String, dynamic>{};
                            await FirebaseFirestore.instance.collection('issuances').add({
                              'id': 'ISS-AUTO-${DateTime.now().millisecondsSinceEpoch}',
                              'date': dateStr, 'plate': plate,
                              'assetDesc': s['desc'] ?? '', 'itemNum': iData['num'] ?? '',
                              'itemName': name, 'itemType': 'Material',
                              'commodityGroup': iData['group'] ?? '', 'uom': uom,
                              'qty': '$qty', 'unitCost': cost.toStringAsFixed(2),
                              'subtotal': (cost * qty).toStringAsFixed(2),
                              'createdBy': byName, 'maintenanceId': s['id'],
                              'createdAt': FieldValue.serverTimestamp(),
                            });
                            final stockSnap = await FirebaseFirestore.instance
                                .collection('stock_inventory').where('name', isEqualTo: name).limit(1).get();
                            if (stockSnap.docs.isNotEmpty) {
                              final stockDoc    = stockSnap.docs.first;
                              final currentStock = (stockDoc['stock'] as num?)?.toInt() ?? 0;
                              final newStock     = (currentStock - qty).clamp(0, 99999);
                              final minLevel     = (stockDoc['min'] as num?)?.toInt() ?? 0;
                              await stockDoc.reference.update({
                                'stock': newStock,
                                'status': newStock > minLevel ? 'OK' : 'Low',
                                'updatedAt': FieldValue.serverTimestamp(),
                              });
                            }
                            await FirebaseFirestore.instance.collection('transactions').add({
                              'item': name,
                              'desc': 'Issued for maintenance ${s['id']} — $plate',
                              'type': 'OUT', 'qty': '-$qty', 'date': dateStr, 'by': byName,
                              'commodityGroup': iData['group'] ?? '',
                              'assetDesc': s['desc'] ?? '',
                              'plate': plate,
                              'createdAt': FieldValue.serverTimestamp(),
                            });
                          }
                          for (final r in (s['svcRows'] as List<dynamic>? ?? [])) {
                            final name = r['name'] as String? ?? '';
                            final qty  = int.tryParse(r['qty']  as String? ?? '1') ?? 1;
                            final uom  = r['uom']  as String? ?? '';
                            final cost = double.tryParse(r['cost'] as String? ?? '0') ?? 0;
                            if (name.isEmpty) continue;
                            final iSnap = await FirebaseFirestore.instance
                                .collection('item_master').where('name', isEqualTo: name).limit(1).get();
                            final iData = iSnap.docs.isNotEmpty ? iSnap.docs.first.data() as Map<String, dynamic> : <String, dynamic>{};
                            await FirebaseFirestore.instance.collection('issuances').add({
                              'id': 'ISS-AUTO-${DateTime.now().millisecondsSinceEpoch}-S',
                              'date': dateStr, 'plate': plate,
                              'assetDesc': s['desc'] ?? '', 'itemNum': iData['num'] ?? '',
                              'itemName': name, 'itemType': 'Service',
                              'commodityGroup': iData['group'] ?? '', 'uom': uom,
                              'qty': '$qty', 'unitCost': cost.toStringAsFixed(2),
                              'subtotal': (cost * qty).toStringAsFixed(2),
                              'createdBy': byName, 'maintenanceId': s['id'],
                              'createdAt': FieldValue.serverTimestamp(),
                            });
                          }
                          final vSnap = await FirebaseFirestore.instance
                              .collection('vehicles').where('plate', isEqualTo: plate).limit(1).get();
                          if (vSnap.docs.isNotEmpty) {
                            await vSnap.docs.first.reference.update({
                              'status': 'Completed',
                              'completedAt': FieldValue.serverTimestamp(),
                              'lastSvcDate': '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}',
                            });
                          }
                        }();
                      },
                      icon: const Icon(Icons.done_all, size: 16),
                      label: const Text('Mark as Completed'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                    )),
                  const SizedBox(height: 8),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  // ── MORE ──
  Widget _buildMore() {
    final items = [
      {
        'icon': Icons.smart_toy_outlined,
        'label': 'DSS',
        'sub': 'Decision Support System',
        'color': const Color(0xFF003087),
        'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminDSS())),
      },
      {
        'icon': Icons.people_outline,
        'label': 'User Management',
        'sub': 'Manage system users',
        'color': Colors.teal,
        'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminUsers())),
      },
      {
        'icon': Icons.apps_outlined,
        'label': 'Domain Management',
        'sub': 'Manage lookup values & categories',
        'color': Colors.indigo,
        'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminDomainManagement())),
      },
      {
        'icon': Icons.inventory_2_outlined,
        'label': 'Archive',
        'sub': 'View and restore archived items',
        'color': Colors.blueGrey,
        'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminArchive())),
      },
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 4),
        ...items.map((item) => GestureDetector(
          onTap: item['onTap'] as VoidCallback,
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Row(children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: (item['color'] as Color).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(item['icon'] as IconData, color: item['color'] as Color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item['label'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1a202c))),
                const SizedBox(height: 2),
                Text(item['sub'] as String, style: const TextStyle(fontSize: 12, color: Color(0xFF718096))),
              ])),
              const Icon(Icons.chevron_right, color: Color(0xFFcbd5e0), size: 20),
            ]),
          ),
        )),
      ]),
    );
  }

  // ── USERS ──
  Widget _buildUsersRedirect() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_currentIndex == 4) {
        Navigator.push(context,
          MaterialPageRoute(builder: (_) => const AdminUsers()))
          .then((_) => setState(() => _currentIndex = 0));
      }
    });
    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildUsers() {
    final users = [
      {'name': 'Administrator', 'username': 'admin', 'role': 'Admin', 'status': 'Active'},
      {'name': 'Staff Member', 'username': 'staff', 'role': 'Staff', 'status': 'Active'},
      {'name': 'John Doe', 'username': 'customer', 'role': 'Customer', 'status': 'Active'},
    ];
    return Column(children: [
      _searchBar('Search users...', () {}),
      Expanded(child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: users.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final u = users[i];
          final roleColor = u['role'] == 'Admin' ? _red : u['role'] == 'Staff' ? Colors.blue : Colors.green;
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)]),
            child: Row(children: [
              CircleAvatar(radius: 22, backgroundColor: roleColor.withOpacity(0.15),
                child: Text(u['name']![0], style: TextStyle(color: roleColor, fontWeight: FontWeight.bold))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(u['name']!, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                Text('@${u['username']}', style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: roleColor.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                  child: Text(u['role']!, style: TextStyle(fontSize: 10, color: roleColor, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 4),
                const Text('Active', style: TextStyle(fontSize: 10, color: Colors.green)),
              ]),
            ]),
          );
        },
      )),
    ]);
  }

  void _showProfileSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => DraggableScrollableSheet(
        expand: false, initialChildSize: 0.75, maxChildSize: 0.92,
        builder: (_, ctrl) => SingleChildScrollView(
          controller: ctrl,
          child: Column(children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              decoration: const BoxDecoration(
                color: _red,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                const CircleAvatar(radius: 28, backgroundColor: Colors.white24,
                  child: Text('AD', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold))),
                const SizedBox(width: 14),
                const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Administrator', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  Text('Super Admin', style: TextStyle(color: Colors.white70, fontSize: 12)),
                ])),
                GestureDetector(onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close, color: Colors.white)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                _profileCard('Account Info', [
                  _profileRow(Icons.person_outline, 'Full Name', 'Administrator'),
                  _profileRow(Icons.alternate_email, 'Email', 'admin@caltex.com'),
                  _profileRow(Icons.badge_outlined, 'Role', 'Super Admin'),
                ]),
                const SizedBox(height: 12),
                _profileCard('System Overview', [
                  _profileRow(Icons.directions_car_outlined, 'Total Vehicles', '24'),
                  _profileRow(Icons.people_outline, 'Total Users', '3'),
                  _profileRow(Icons.inventory_2_outlined, 'Inventory Items', '4'),
                  _profileRow(Icons.build_outlined, 'Services This Week', '18'),
                ]),
                const SizedBox(height: 20),
                SizedBox(width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      AdminChatStore.clear();
                      CustomerChatStore.clear();
                      await FirebaseAuth.instance.signOut();
                      if (context.mounted) {
                        Navigator.pop(context);
                        Navigator.pushAndRemoveUntil(context,
                          MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
                      }
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text('Logout'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  )),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  // ── PROFILE ──
  Widget _buildProfile() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        const SizedBox(height: 12),
        const CircleAvatar(radius: 40, backgroundColor: _red,
          child: Text('AD', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold))),
        const SizedBox(height: 12),
        const Text('Administrator', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const Text('Super Admin', style: TextStyle(color: Color(0xFF718096))),
        const SizedBox(height: 20),
        _profileCard('Account Info', [
          _profileRow(Icons.person_outline, 'Full Name', 'Administrator'),
          _profileRow(Icons.alternate_email, 'Email', 'admin@caltex.com'),
          _profileRow(Icons.badge_outlined, 'Role', 'Super Admin'),
        ]),
        const SizedBox(height: 12),
        _profileCard('System Overview', [
          _profileRow(Icons.directions_car_outlined, 'Total Vehicles', '24'),
          _profileRow(Icons.people_outline, 'Total Users', '3'),
          _profileRow(Icons.inventory_2_outlined, 'Inventory Items', '4'),
          _profileRow(Icons.build_outlined, 'Services This Week', '18'),
        ]),
        const SizedBox(height: 20),
        SizedBox(width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () async {
              AdminChatStore.clear();
              CustomerChatStore.clear();
              await FirebaseAuth.instance.signOut();
              if (context.mounted) {
                Navigator.pushAndRemoveUntil(context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
              }
            },
            icon: const Icon(Icons.logout),
            label: const Text('Logout'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          )),
      ]),
    );
  }

  Widget _profileCard(String title, List<Widget> rows) {
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1a202c))),
        const Divider(height: 20),
        ...rows,
      ]),
    );
  }

  Widget _profileRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Icon(icon, size: 18, color: _red),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ])),
      ]),
    );
  }

  Widget _searchBar(String hint, VoidCallback onChanged) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: TextField(
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search, size: 20),
          filled: true, fillColor: const Color(0xFFF7F8FA),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) =>
    Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1a202c)));

  static const _monthsShort = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  static const _monthsLong = ['January','February','March','April','May','June','July','August','September','October','November','December'];

  /// Converts dates to "June 1, 2026" format
  /// Handles: "Jun 1, 2026", "6/1/2026", "2026-06-01"
  String _fmtDateLong(String dateStr) {
    if (dateStr.isEmpty || dateStr == '—') return dateStr;
    // Handle "Jun 1, 2026" short month format
    for (int i = 0; i < _monthsShort.length; i++) {
      if (dateStr.startsWith(_monthsShort[i])) {
        return dateStr.replaceFirst(_monthsShort[i], _monthsLong[i]);
      }
    }
    // Handle "6/1/2026" or "06/01/2026" format
    final slashParts = dateStr.split('/');
    if (slashParts.length == 3) {
      final m = int.tryParse(slashParts[0]);
      final d = int.tryParse(slashParts[1]);
      final y = int.tryParse(slashParts[2]);
      if (m != null && d != null && y != null && m >= 1 && m <= 12) {
        return '${_monthsLong[m - 1]} $d, $y';
      }
    }
    // Handle "2026-06-01" ISO format
    final dt = DateTime.tryParse(dateStr);
    if (dt != null) {
      return '${_monthsLong[dt.month - 1]} ${dt.day}, ${dt.year}';
    }
    return dateStr;
  }

  /// Cleans transaction descriptions — same logic as the website
  /// Returns (cleanedDesc, assetLine) where assetLine is the vehicle description
  (String, String) _cleanTxnDescWithAsset(String raw) {
    if (raw.isEmpty || raw == '—') return (raw, '');
    var d = raw
        .replaceAll(RegExp(r'for maintenance SVC-\d+\s*[—\-]\s*', caseSensitive: false), 'for ')
        .replaceAll(RegExp(r'for maintenance SVC-\d+', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*SVC-\d+\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'for maintenance\s+[A-Za-z0-9]{15,}\s*[—\-]\s*', caseSensitive: false), 'for ')
        .replaceAll(RegExp(r'for maintenance\s+[A-Za-z0-9]{15,}', caseSensitive: false), '')
        .replaceAllMapped(
            RegExp(r'^(Stock received|Initial stock received)\s*[—\-]\s*.+$', caseSensitive: false),
            (m) => m.group(1) ?? '')
        .trim();
    if (d.isEmpty) d = '—';

    // Extract vehicle description from "Issued to/for PLATE — Vehicle Desc"
    String assetLine = '';
    final issuedMatch = RegExp(r'^(Issued (?:to|for)\s+\S+)\s*—\s*(.+)$', caseSensitive: false).firstMatch(d);
    if (issuedMatch != null && (issuedMatch.group(2) ?? '').trim().isNotEmpty) {
      assetLine = issuedMatch.group(2)!.trim();
      d = issuedMatch.group(1)!.trim();
    }

    return (d, assetLine);
  }

  /// Cleans transaction descriptions — same logic as the website
  String _cleanTxnDesc(String raw) {
    final (cleaned, _) = _cleanTxnDescWithAsset(raw);
    return cleaned;
  }
}
