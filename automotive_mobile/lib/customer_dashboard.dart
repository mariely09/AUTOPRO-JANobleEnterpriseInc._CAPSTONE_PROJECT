import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login.dart';
import 'customer_pms_history.dart';
import 'customer_smart_ai.dart';
import 'customer_book_service.dart';
import 'customer_mybookings.dart';
import 'profile.dart';
import 'notifications.dart';
import 'customer_bottomnavbar.dart';
import 'customer_calendar_floating.dart';

class CustomerDashboard extends StatefulWidget {
  const CustomerDashboard({super.key});

  @override
  State<CustomerDashboard> createState() => _CustomerDashboardState();
}

class _CustomerDashboardState extends State<CustomerDashboard> {
  int _currentIndex = 0;
  static const _red = Color(0xFFE8001C);
  static const _bg = Color(0xFFF7F8FA);
  String _initials = '?';
  String? _photoUrl;
  String _userName = '';
  IconData _fleetNavIcon = Icons.directions_car_outlined;
  bool _iconComputed = false; // Flag to prevent recomputing icon on every rebuild

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
    if (name.isEmpty && photo == null) return;
    String ini = '?';
    if (name.isNotEmpty) {
      final parts = name.trim().split(' ');
      ini = parts.length >= 2
          ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
          : parts[0][0].toUpperCase();
    }
    if (mounted) setState(() { _initials = ini; _photoUrl = photo; _userName = name; });
  }

  // nav items moved to CustomerBottomNavBar
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildTopBar(),
      body: Stack(children: [
        _buildBody(),
        // ── Floating calendar overlay (always visible) ──
        const CustomerCalendarFloating(),
      ]),
      bottomNavigationBar: CustomerBottomNavBar(
        currentIndex: _currentIndex,
        onTap: (i) {
          if (i == 1) {
            // My Bookings opens as a full separate screen (no dashboard bottom nav)
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const CustomerMyBookings()));
          } else if (i == 2) {
            // Smart AI opens as a full separate screen (no app header / bottom nav)
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const CustomerSmartAI()));
          } else if (i == 3) {
            // PMS History opens as a full separate screen (no bottom nav)
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const CustomerPmsScreen()));
          } else if (i == 4) {
            // Profile opens as a full screen then refreshes initials
            Navigator.push(context,
                MaterialPageRoute(
                    builder: (_) =>
                        const UserProfile(role: UserRole.customer)))
                .then((_) => _loadInitials());
          } else {
            setState(() => _currentIndex = i);
          }
        },
      ),
    );
  }

  PreferredSizeWidget _buildTopBar() {
    return AppBar(
      backgroundColor: _red,
      elevation: 0,
      automaticallyImplyLeading: false,
      title: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const UserProfile(role: UserRole.customer)))
              .then((_) => _loadInitials()),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: Colors.white24,
              backgroundImage: _photoUrl != null ? NetworkImage(_photoUrl!) : null,
              child: _photoUrl == null
                  ? Text(_initials, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold))
                  : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(_userName.isNotEmpty ? _userName : 'My Vehicles',
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
            overflow: TextOverflow.ellipsis)),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: NotifBadge(
            role: NotificationRole.customer,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AppNotifications(role: NotificationRole.customer))),
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildBody() {
    switch (_currentIndex) {
      case 0: return _buildVehicles();
      // cases 1, 2, 3, 4 all handled via Navigator.push
      default: return _buildVehicles();
    }
  }

  // ── MY VEHICLES ──
  Widget _buildVehicles() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('vehicles')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final uid = FirebaseAuth.instance.currentUser?.uid;
        final allDocs = snapshot.data?.docs ?? [];

        // Filter vehicles owned by this customer (match by owner name)
        // We'll match by owner field after loading user name
        return FutureBuilder<DocumentSnapshot>(
          future: uid != null
              ? FirebaseFirestore.instance.collection('users').doc(uid).get()
              : Future.value(null),
          builder: (context, userSnap) {
            final userName = (userSnap.data?.data() as Map<String, dynamic>?)?['name'] as String? ?? '';

            // Auto-update statuses based on next PMS due date
            if (userName.isNotEmpty && snapshot.hasData) {
              _refreshVehicleStatuses(snapshot.data!.docs, userName);
            }

            final vehicles = allDocs
                .where((d) {
                  final data = d.data() as Map<String, dynamic>;
                  final owner = data['owner'] as String? ?? '';
                  return owner.toLowerCase() == userName.toLowerCase();
                })
                .map((d) {
                  final data = d.data() as Map<String, dynamic>;
                  return {
                    'id': d.id,
                    'plate': data['plate'] as String? ?? '',
                    'desc': data['desc'] as String? ?? '',
                    'type': data['type'] as String? ?? '',
                    'status': data['status'] as String? ?? 'Active',
                    'lastSvcDate': data['lastSvcDate'] as String? ?? '',
                    'lastSvcOdo': (data['lastSvcOdo'] ?? data['lastServiceOdometer'] ?? '').toString(),
                    'odo': data['odo'] as String? ?? '',
                    'svcFreq': data['svcFreq'] as String? ?? '',
                  };
                }).toList();

            final maint    = vehicles.where((v) => v['status'] == 'Under Maintenance').length;
            final overdue  = vehicles.where((v) => v['status'] == 'Overdue').length;
            final dueWeek  = vehicles.where((v) => v['status'] == 'Due This Week').length;
            final dueToday = vehicles.where((v) => v['status'] == 'Due Today').length;
            final active   = vehicles.where((v) => v['status'] == 'On Track' || v['status'] == 'Scheduled').length;

            // Update nav icon based on fleet type (only once when vehicles first load)
            if (!_iconComputed && vehicles.isNotEmpty) {
              _iconComputed = true;
              _fleetNavIcon = _fleetIcon(vehicles);
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                GridView.count(
                  crossAxisCount: 2, shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.4,
                  children: [
                    _miniStat('Total Vehicles',  '${vehicles.length}', _fleetIcon(vehicles),           _red),
                    _miniStat('Active',           '$active',            Icons.check_circle_outline,     Colors.green),
                    _miniStat('Maintenance',      '$maint',             Icons.build_outlined,           Colors.orange),
                    _miniStat('PMS Overdue',      '$overdue',           Icons.warning_amber_outlined,   Colors.red),
                    _miniStat('Due This Week',    '$dueWeek',           Icons.event_available_outlined, const Color(0xFFdd6b20)),
                    _miniStat('Due Today',        '$dueToday',          Icons.today_outlined,           const Color(0xFF0033A0)),
                  ],
                ),
                const SizedBox(height: 20),
                const SizedBox(height: 12),
                if (vehicles.isEmpty)
                  const Center(child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('No vehicles registered under your name.', style: TextStyle(color: Color(0xFF718096))),
                  ))
                else
                  ...vehicles.map((v) => _vehicleCard(v)),
              ]),
            );
          },
        );
      },
    );
  }

  Widget _miniStat(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 6),
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color))),
          Text(label, style: const TextStyle(fontSize: 9, color: Color(0xFF718096)), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _vehicleIcon(String type, {double size = 26, Color color = _red}) {
    final t = type.toLowerCase();
    final icon = t.contains('truck')
        ? Icons.local_shipping_outlined
        : Icons.directions_car_outlined;
    return Icon(icon, color: color, size: size);
  }

  /// Returns a single icon that best represents the whole fleet.
  /// All trucks → truck icon. All cars → car icon. Mixed → directions_car (generic).
  IconData _fleetIcon(List<Map<String, String>> vehicles) {
    if (vehicles.isEmpty) return Icons.directions_car_outlined;
    final allTruck = vehicles.every((v) => (v['type'] ?? '').toLowerCase().contains('truck'));
    final allCar   = vehicles.every((v) => !(v['type'] ?? '').toLowerCase().contains('truck'));
    if (allTruck) return Icons.local_shipping_outlined;
    if (allCar)   return Icons.directions_car_outlined;
    return Icons.commute_outlined; // mixed fleet
  }

  Widget _vehicleCard(Map<String, String> v) {
    final status = v['status'] ?? 'On Track';
    final statusColor = status == 'Overdue'           ? _red
        : status == 'Due Today'                       ? const Color(0xFF0033A0)
        : status == 'Due This Week'                   ? const Color(0xFFdd6b20)
        : status == 'Due Soon'                        ? Colors.orange
        : status == 'Under Maintenance'               ? Colors.orange
        : Colors.green; // On Track + Scheduled → Active
    final statusBg = status == 'Overdue'              ? const Color(0xFFFFF5F5)
        : status == 'Due Today'                       ? const Color(0xFFEEF2FF)
        : status == 'Due This Week'                   ? const Color(0xFFFFFBEB)
        : status == 'Due Soon'                        ? const Color(0xFFFFF8E1)
        : status == 'Under Maintenance'               ? const Color(0xFFFFF8E1)
        : const Color(0xFFF0FFF4);
    final statusLabel = status == 'Overdue'           ? 'Overdue'
        : status == 'Due Today'                       ? 'Due Today'
        : status == 'Due This Week'                   ? 'Due This Week'
        : status == 'Due Soon'                        ? 'Due Soon'
        : status == 'Under Maintenance'               ? 'Under Maintenance'
        : 'Active'; // On Track + Scheduled

    return GestureDetector(
      onTap: () => _showVehicleHistory(v),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFe2e8f0), width: 1),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Header: plate/desc + status badge ──
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(v['plate']!, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF1a202c))),
                const SizedBox(height: 2),
                Text(v['desc']!, style: const TextStyle(fontSize: 12, color: Color(0xFF718096))),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(statusLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: statusColor)),
              ),
            ]),
          ),

          // ── Body: meta row (odometer + last service) ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Row(children: [
              _metaItem(Icons.speed_outlined, v['odo']!.isNotEmpty ? v['odo']! : '—'),
              const SizedBox(width: 20),
              _metaItem(Icons.calendar_today_outlined, v['lastSvcDate']!.isNotEmpty ? _fmtDateLong(v['lastSvcDate']!) : '—'),
            ]),
          ),

          // ── Footer: "View details" + chevron ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(14)),
              border: Border(top: BorderSide(color: Color(0xFFF0F4F8))),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('View details', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFE8001C))),
                Icon(Icons.chevron_right, size: 16, color: Color(0xFFE8001C)),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _metaItem(IconData icon, String text) {
    return Row(children: [
      Icon(icon, size: 13, color: const Color(0xFF718096)),
      const SizedBox(width: 5),
      Text(text, style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
    ]);
  }

  static const _monthsFull = ['January','February','March','April','May','June','July','August','September','October','November','December'];

  String _fmtDateLong(String dateStr) {
    if (dateStr.isEmpty) return '—';
    final d = DateTime.tryParse(dateStr);
    if (d == null) return dateStr;
    return '${_monthsFull[d.month - 1]} ${d.day}, ${d.year}';
  }

  Widget _stripDivider() => Container(
    width: 1, height: 14, color: const Color(0xFFe2e8f0),
    margin: const EdgeInsets.symmetric(horizontal: 10),
  );

  Widget _infoChip(IconData icon, String text) {
    return Row(children: [
      Icon(icon, size: 13, color: const Color(0xFF718096)),
      const SizedBox(width: 4),
      Text(text, style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
    ]);
  }

  void _showVehicleHistory(Map<String, String> v) {
    final status = v['status'] ?? 'On Track';
    final statusColor = status == 'Overdue'           ? _red
        : status == 'Due Today'                       ? const Color(0xFF0033A0)
        : status == 'Due This Week'                   ? const Color(0xFFdd6b20)
        : status == 'Due Soon'                        ? Colors.orange
        : status == 'Under Maintenance'               ? Colors.orange
        : Colors.green; // On Track + Scheduled → Active

    // Compute next PMS
    String nextPms = '—';
    int? daysUntil;
    final lastSvcDate = v['lastSvcDate'] ?? '';
    final svcFreq = v['svcFreq'] ?? '';
    if (lastSvcDate.isNotEmpty && svcFreq.isNotEmpty) {
      final date = DateTime.tryParse(lastSvcDate);
      final months = int.tryParse(svcFreq);
      if (date != null && months != null) {
        final next = DateTime(date.year, date.month + months, date.day);
        nextPms = '${next.year}-${next.month.toString().padLeft(2, '0')}-${next.day.toString().padLeft(2, '0')}';
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final nextMidnight = DateTime(next.year, next.month, next.day);
        daysUntil = nextMidnight.difference(today).inDays;
      }
    }

    String statusLabel;
    if (status == 'Under Maintenance') {
      statusLabel = 'Under Maintenance';
    } else if (daysUntil == null) {
      statusLabel = status;
    } else if (daysUntil < 0) {
      statusLabel = 'Overdue ${(-daysUntil)} day${(-daysUntil) != 1 ? 's' : ''}';
    } else if (daysUntil == 0) {
      statusLabel = 'Due Today';
    } else if (daysUntil <= 7) {
      statusLabel = 'Due in $daysUntil day${daysUntil != 1 ? 's' : ''} (This Week)';
    } else if (daysUntil <= 14) {
      statusLabel = 'Due in $daysUntil days (Due Soon)';
    } else if (daysUntil <= 30) {
      statusLabel = 'Due in $daysUntil days (Scheduled)';
    } else {
      statusLabel = 'Due in $daysUntil days (On Track)';
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        expand: false, initialChildSize: 0.75, maxChildSize: 0.95,
        builder: (_, ctrl) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF7F8FA),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              decoration: const BoxDecoration(color: _red,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
              child: Column(children: [
                Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.white38, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(v['plate']!, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    Text(v['desc']!, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ])),
                ]),
              ]),
            ),
            // Body
            Expanded(
              child: SingleChildScrollView(
                controller: ctrl,
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Vehicle info card
                  Container(
                    width: double.infinity, padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
                    child: Column(children: [
                      _detailRow(Icons.speed_outlined, 'Last Service Odometer', v['lastSvcOdo']!.isNotEmpty && v['lastSvcOdo'] != '0' ? '${int.tryParse(v['lastSvcOdo']!.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0} km' : '—', const Color(0xFF718096)),
                      _divider(),
                      _detailRow(Icons.calendar_today_outlined, 'Last Service', lastSvcDate.isNotEmpty ? _fmtDateLong(lastSvcDate) : '—', const Color(0xFF2b6cb0)),
                      _divider(),
                      _detailRow(Icons.event_outlined, 'Next PMS Due', _fmtDateLong(nextPms), statusColor),
                      _divider(),
                      _detailRow(Icons.info_outline, 'Status', statusLabel, statusColor),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  if (status == 'Overdue') ...[
                    FutureBuilder<QuerySnapshot>(
                      future: FirebaseFirestore.instance
                          .collection('service_bookings')
                          .where('vehicleId', isEqualTo: v['id'])
                          .where('status', whereIn: ['Pending', 'Approved'])
                          .limit(1)
                          .get(),
                      builder: (context, bookSnap) {
                        // While checking show a subtle loader
                        if (bookSnap.connectionState == ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Center(child: SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE8001C)))),
                          );
                        }

                        final hasBooking = (bookSnap.data?.docs.isNotEmpty) ?? false;
                        final bookingStatus = hasBooking
                            ? (bookSnap.data!.docs.first.data() as Map<String, dynamic>)['status'] as String? ?? 'Pending'
                            : '';

                        if (hasBooking) {
                          // Already booked — show status badge instead of Book button
                          final isApproved = bookingStatus == 'Approved';
                          final badgeColor = isApproved ? Colors.green : Colors.orange;
                          final badgeBg    = isApproved ? const Color(0xFFF0FFF4) : const Color(0xFFFFF8E1);
                          final badgeBorder= isApproved ? const Color(0xFFC6F6D5) : const Color(0xFFFBD38D);
                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: badgeBg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: badgeBorder, width: 1.5),
                            ),
                            child: Row(children: [
                              Container(
                                width: 38, height: 38,
                                decoration: BoxDecoration(
                                  color: badgeColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10)),
                                child: Icon(
                                  isApproved ? Icons.check_circle_outline : Icons.access_time_outlined,
                                  size: 18, color: badgeColor),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('Service Already Booked',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: badgeColor)),
                                const SizedBox(height: 2),
                                Text(
                                  isApproved
                                    ? 'Your booking is confirmed. See you at the shop!'
                                    : 'Your booking is pending admin approval.',
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
                              ])),
                              GestureDetector(
                                onTap: () {
                                  Navigator.pop(context); // close modal
                                  Navigator.push(context,
                                    MaterialPageRoute(builder: (_) => const CustomerMyBookings()));
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: badgeColor,
                                    borderRadius: BorderRadius.circular(8)),
                                  child: const Text('View',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                                ),
                              ),
                            ]),
                          );
                        }

                        // No active booking — show Book Now button
                        return GestureDetector(
                          onTap: () {
                            Navigator.pop(context); // close modal
                            Navigator.push(context,
                              MaterialPageRoute(builder: (_) => CustomerBookService(preselectedVehicleId: v['id']!)));
                          },
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF5F5),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFFED7D7), width: 1.5),
                            ),
                            child: Row(children: [
                              Container(
                                width: 38, height: 38,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE8001C).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10)),
                                child: const Icon(Icons.calendar_month_outlined, size: 18, color: Color(0xFFE8001C)),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('PMS is overdue', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFE8001C))),
                                SizedBox(height: 2),
                                Text('Book a service now to avoid further issues.', style: TextStyle(fontSize: 11, color: Color(0xFF718096))),
                              ])),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE8001C),
                                  borderRadius: BorderRadius.circular(8)),
                                child: const Text('Book', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                              ),
                            ]),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _svcMatLabel(IconData icon, String label, Color color) {
    return Row(children: [
      Container(padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
        child: Icon(icon, size: 13, color: color)),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
    ]);
  }

  Widget _svcMatRow(Map<String, dynamic> item, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(children: [
        Container(width: 4, height: 4, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(child: Text(item['name'] as String? ?? '', style: const TextStyle(fontSize: 12, color: Color(0xFF1a202c)))),
        Text('${item['qty']} ${item['uom']}', style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
      ]),
    );
  }

  Widget _detailRow(IconData icon, String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 17, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1a202c))),
        ])),
      ]),
    );
  }

  Widget _divider() => const Divider(height: 1, indent: 62, endIndent: 12);

  // ── STATUS COMPUTATION — mirrors admin_dss.dart PMS Scheduling ──
  // Overdue < 0, Due This Week ≤ 7, Due Soon ≤ 14, Scheduled ≤ 30, On Track > 30
  String _computeStatus(String lastSvcDate, String svcFreq) {
    if (lastSvcDate.isEmpty || svcFreq.isEmpty) return 'On Track';
    final date = DateTime.tryParse(lastSvcDate);
    final months = int.tryParse(svcFreq);
    if (date == null || months == null) return 'On Track';
    final nextPms = DateTime(date.year, date.month + months, date.day);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final nextMidnight = DateTime(nextPms.year, nextPms.month, nextPms.day);
    final daysUntil = nextMidnight.difference(today).inDays;
    if (daysUntil < 0)   return 'Overdue';
    if (daysUntil == 0)  return 'Due Today';
    if (daysUntil <= 7)  return 'Due This Week';
    if (daysUntil <= 14) return 'Due Soon';
    if (daysUntil <= 30) return 'Scheduled';
    return 'On Track';
  }

  Future<void> _refreshVehicleStatuses(List<QueryDocumentSnapshot> docs, String userName) async {
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final owner = data['owner'] as String? ?? '';
      if (owner.toLowerCase() != userName.toLowerCase()) continue;
      final currentStatus = data['status'] as String? ?? '';
      if (currentStatus == 'Under Maintenance') continue; // don't override active maintenance
      final computed = _computeStatus(
        data['lastSvcDate'] as String? ?? '',
        data['svcFreq'] as String? ?? '',
      );
      if (computed != currentStatus) {
        await doc.reference.update({'status': computed});
      }
    }
  }

  // ── SMART REPORTS ──
  final List<Map<String, String>> _chatMessages = [];
  final _chatCtrl = TextEditingController();

  Widget _buildSmartReports() {
    return Column(children: [
      // Chat header
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: Colors.white,
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: const Color(0xFFF0F4FF), borderRadius: BorderRadius.circular(20)),
            child: const Text('🤖', style: TextStyle(fontSize: 20), textAlign: TextAlign.center),
          ),
          const SizedBox(width: 10),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Smart Reports AI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            Row(children: [
              CircleAvatar(radius: 4, backgroundColor: Colors.green),
              SizedBox(width: 4),
              Text('Online', style: TextStyle(fontSize: 11, color: Color(0xFF718096))),
            ]),
          ])),
          TextButton(onPressed: () => setState(() => _chatMessages.clear()),
            child: const Text('🗑️ Clear', style: TextStyle(color: Color(0xFF718096), fontSize: 12))),
        ]),
      ),
      // Messages
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_chatMessages.isEmpty) _buildWelcomeBubble(),
            ..._chatMessages.map((m) => _buildChatBubble(m['text']!, m['role'] == 'user')),
          ],
        ),
      ),
      // Quick chips
      if (_chatMessages.isEmpty)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            _chip('🚛 All my vehicles', 'Show all my vehicles'),
            _chip('🔵 Under maintenance', 'Which vehicles are under maintenance?'),
            _chip('⚠️ PMS overdue', 'Which vehicles have PMS overdue?'),
            _chip('📅 Due soon', 'Which vehicles have PMS due soon?'),
            _chip('📋 History', 'Show maintenance history'),
          ]),
        ),
      // Input
      Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        color: Colors.white,
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _chatCtrl,
              decoration: InputDecoration(
                hintText: 'Ask about your vehicles...',
                filled: true, fillColor: const Color(0xFFF7F8FA),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onSubmitted: (v) => _sendMessage(v),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _sendMessage(_chatCtrl.text),
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: _red, borderRadius: BorderRadius.circular(22)),
              child: const Icon(Icons.send, color: Colors.white, size: 18),
            ),
          ),
        ]),
      ),
    ]);
  }

  Widget _buildWelcomeBubble() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
      child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("Hello! I'm your Smart Reports assistant. 👋",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        SizedBox(height: 4),
        Text('Ask me anything about your vehicles — PMS status, maintenance history, and more.',
          style: TextStyle(fontSize: 12, color: Color(0xFF718096))),
      ]),
    );
  }

  Widget _buildChatBubble(String text, bool isUser) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isUser ? _red : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6)],
        ),
        child: Text(text, style: TextStyle(fontSize: 13, color: isUser ? Colors.white : const Color(0xFF1a202c))),
      ),
    );
  }

  Widget _chip(String label, String query) {
    return GestureDetector(
      onTap: () => _sendMessage(query),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFe2e8f0)),
        ),
        child: Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF4a5568))),
      ),
    );
  }

  void _sendMessage(String text) {
    if (text.trim().isEmpty) return;
    setState(() {
      _chatMessages.add({'role': 'user', 'text': text});
      _chatCtrl.clear();
      // Simple mock AI response
      final lower = text.toLowerCase();
      String reply;
      if (lower.contains('maintenance')) {
        reply = 'Toyota Hilux (XYZ-5678) is currently under maintenance.';
      } else if (lower.contains('overdue')) {
        reply = 'Mitsubishi L300 (DEF-9012) has PMS overdue. Please schedule a service soon.';
      } else if (lower.contains('due soon')) {
        reply = 'Isuzu Truck NQR (ABC-1234) has PMS due in 2 months.';
      } else if (lower.contains('history')) {
        reply = 'Your vehicles have a total of 9 service records. Tap any vehicle to view full history.';
      } else if (lower.contains('vehicle') || lower.contains('fleet')) {
        reply = 'You have 3 vehicles:\n• ABC-1234 - Isuzu Truck NQR (Good)\n• XYZ-5678 - Toyota Hilux (Maintenance)\n• DEF-9012 - Mitsubishi L300 (Overdue)';
      } else {
        reply = 'I can help you with vehicle status, PMS schedules, and maintenance history. Try asking about your fleet!';
      }
      _chatMessages.add({'role': 'ai', 'text': reply});
    });
  }

  // ── NOTIFICATIONS ──
  Widget _buildNotifications() {
    final notifs = [
      {'title': 'PMS Overdue', 'msg': 'DEF-9012 Mitsubishi L300 is overdue for PMS', 'time': '1 hr ago', 'icon': Icons.warning_amber_outlined, 'color': Colors.red},
      {'title': 'Service Complete', 'msg': 'ABC-1234 oil change has been completed', 'time': '3 hrs ago', 'icon': Icons.check_circle_outline, 'color': Colors.green},
      {'title': 'PMS Due Soon', 'msg': 'ABC-1234 Isuzu Truck is due for PMS in 2 months', 'time': 'Yesterday', 'icon': Icons.schedule_outlined, 'color': Colors.amber},
    ];
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('🔔 Notifications', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          TextButton(onPressed: () {}, child: const Text('Clear All', style: TextStyle(color: Color(0xFF718096), fontSize: 12))),
        ]),
      ),
      Expanded(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          itemCount: notifs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final n = notifs[i];
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)]),
              child: Row(children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(color: (n['color'] as Color).withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                  child: Icon(n['icon'] as IconData, color: n['color'] as Color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(n['title'] as String, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  Text(n['msg'] as String, style: const TextStyle(fontSize: 12, color: Color(0xFF718096))),
                ])),
                Text(n['time'] as String, style: const TextStyle(fontSize: 10, color: Color(0xFF718096))),
              ]),
            );
          },
        ),
      ),
    ]);
  }

}

// ── PMS Reschedule Request Widget ────────────────────────────
class _RescheduleWidget extends StatefulWidget {
  final String vehicleId;
  final String plate;
  const _RescheduleWidget({required this.vehicleId, required this.plate});

  @override
  State<_RescheduleWidget> createState() => _RescheduleWidgetState();
}

class _RescheduleWidgetState extends State<_RescheduleWidget> {
  DateTime? _selectedDate;
  bool _loading = false;
  bool _sent = false;
  bool _alreadyPending = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _checkExisting();
  }

  Future<void> _checkExisting() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final snap = await FirebaseFirestore.instance
        .collection('pms_reschedule_requests')
        .where('vehicleId', isEqualTo: widget.vehicleId)
        .where('customerId', isEqualTo: uid)
        .where('status', isEqualTo: 'Pending')
        .limit(1)
        .get();
    if (mounted) setState(() { _alreadyPending = snap.docs.isNotEmpty; _checking = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    if (_alreadyPending) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.amber.shade200),
        ),
        child: const Row(children: [
          Icon(Icons.schedule_outlined, color: Colors.amber, size: 20),
          SizedBox(width: 10),
          Expanded(child: Text(
            'You already have a pending reschedule request for this vehicle.',
            style: TextStyle(fontSize: 12, color: Colors.amber, fontWeight: FontWeight.w600),
          )),
        ]),
      );
    }

    if (_sent) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.shade200),
        ),
        child: const Row(children: [
          Icon(Icons.check_circle_outline, color: Colors.green, size: 20),
          SizedBox(width: 10),
          Expanded(child: Text(
            'Reschedule request sent! The admin will review it shortly.',
            style: TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w600),
          )),
        ]),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5F5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFED7D7), width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.warning_amber_outlined, color: Color(0xFFE8001C), size: 16),
          SizedBox(width: 6),
          Text('PMS is overdue — request a reschedule',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFE8001C))),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now().add(const Duration(days: 1)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                  builder: (c, child) => Theme(
                    data: Theme.of(c).copyWith(
                      colorScheme: const ColorScheme.light(primary: Color(0xFFE8001C))),
                    child: child!),
                );
                if (picked != null) setState(() => _selectedDate = picked);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFe2e8f0)),
                ),
                child: Row(children: [
                  const Icon(Icons.calendar_today_outlined, size: 15, color: Color(0xFF718096)),
                  const SizedBox(width: 8),
                  Text(
                    _selectedDate != null
                        ? '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2,'0')}-${_selectedDate!.day.toString().padLeft(2,'0')}'
                        : 'Select preferred date',
                    style: TextStyle(
                      fontSize: 12,
                      color: _selectedDate != null ? const Color(0xFF1a202c) : const Color(0xFFa0aec0),
                    ),
                  ),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 40,
            child: ElevatedButton(
              onPressed: _loading || _selectedDate == null ? null : () async {
                setState(() => _loading = true);
                try {
                  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
                  final dateStr = '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2,'0')}-${_selectedDate!.day.toString().padLeft(2,'0')}';
                  await FirebaseFirestore.instance.collection('pms_reschedule_requests').add({
                    'vehicleId': widget.vehicleId,
                    'plate': widget.plate,
                    'customerId': uid,
                    'preferredDate': dateStr,
                    'status': 'Pending',
                    'createdAt': FieldValue.serverTimestamp(),
                  });
                  if (mounted) setState(() { _sent = true; _loading = false; });
                } catch (e) {
                  if (mounted) {
                    setState(() => _loading = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE8001C),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: _loading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Request', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ]),
    );
  }
}
