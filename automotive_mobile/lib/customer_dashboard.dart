import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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

// ─────────────────────────────────────────────────────────────────────────────
//  Self-contained AI FAB — owns its own AnimationController + backend check
//  so it survives Navigator push/pop without losing state.
//  Supports long-press drag to reposition anywhere on screen.
// ─────────────────────────────────────────────────────────────────────────────
class _AiStatusFab extends StatefulWidget {
  final VoidCallback onTap;
  final VoidCallback? onDragStart;
  final void Function(Offset globalPosition)? onDragUpdate;
  final VoidCallback? onDragEnd;
  const _AiStatusFab({
    required this.onTap,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
  });

  @override
  State<_AiStatusFab> createState() => _AiStatusFabState();
}

class _AiStatusFabState extends State<_AiStatusFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _online = true;

  static const _kBaseUrl = String.fromEnvironment(
    'AI_BACKEND_URL',
    defaultValue: 'https://caltex-autopro-capstone-project.onrender.com',
  );

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _checkBackend();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _checkBackend() async {
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        final r = await http
            .get(Uri.parse('$_kBaseUrl/health'))
            .timeout(const Duration(seconds: 60));
        if (r.statusCode == 200) {
          if (mounted) setState(() => _online = true);
          return;
        }
      } catch (_) {
        if (attempt < 3) await Future.delayed(const Duration(seconds: 5));
      }
    }
    if (mounted) setState(() => _online = false);
    // Retry after 60 s
    Future.delayed(const Duration(seconds: 60), () {
      if (mounted) _checkBackend();
    });
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _online
        ? const Color(0xFF4ade80)
        : const Color(0xFFF97316);

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        // Compute phase for the second (offset) ring — matches admin AppBar
        final phase = (_ctrl.value + 0.45) % 1.0;

        return SizedBox(
          width: 96,
          height: 96,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // Outer pulse ring — expands & fades out
              Container(
                width: 58 + (_ctrl.value * 28),
                height: 58 + (_ctrl.value * 28),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: statusColor.withOpacity(
                      (1 - _ctrl.value) * 0.55,
                    ),
                    width: 2,
                  ),
                ),
              ),
              // Inner pulse ring — offset phase
              Container(
                width: 58 + (phase * 28),
                height: 58 + (phase * 28),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: statusColor.withOpacity(
                      (1 - phase) * 0.55,
                    ),
                    width: 1.5,
                  ),
                ),
              ),
              // Main button — white circle with status-colour border
              GestureDetector(
                onTap: widget.onTap,
                onLongPressStart: (_) => widget.onDragStart?.call(),
                onLongPressMoveUpdate: (d) =>
                    widget.onDragUpdate?.call(d.globalPosition),
                onLongPressEnd: (_) => widget.onDragEnd?.call(),
                child: Material(
                  color: Colors.transparent,
                  elevation: 6,
                  shape: const CircleBorder(),
                  child: Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(
                        color: statusColor,
                        width: 2.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: statusColor.withOpacity(0.45),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                        BoxShadow(
                          color: Colors.black.withOpacity(0.10),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        ClipOval(
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Image.asset(
                              'assets/img/AI_LOGO.png',
                              width: 46,
                              height: 46,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        // Status dot
                        Positioned(
                          bottom: 3,
                          right: 3,
                          child: Container(
                            width: 13,
                            height: 13,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: statusColor,
                              border: Border.all(
                                color: Colors.white,
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: statusColor.withOpacity(0.8),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class CustomerDashboard extends StatefulWidget {
  const CustomerDashboard({super.key});

  @override
  State<CustomerDashboard> createState() => _CustomerDashboardState();
}

class _CustomerDashboardState extends State<CustomerDashboard> {
  int _currentIndex = 0;
  static const _red = Color(0xFFE8001C);
  static const _darkerTeal = Color(0xFF004B5F);
  static const _bg = Color(0xFFF7F8FA);
  String _initials = '?';
  String? _photoUrl;
  String _userName = '';
  String _firstName = '';
  String _userEmail = '';
  String _companyName = '';
  IconData _fleetNavIcon = Icons.directions_car_outlined;
  bool _iconComputed = false;

  // ── Draggable FAB position (bottom-right offset from bottom-right corner) ──
  double _fabRight  = 16.0;
  double _fabBottom = 16.0;
  bool   _fabDragging = false;

  // Cache so photo is available immediately on re-entry (no flicker)
  static String? _cachedPhotoUrl;
  static String _cachedInitials = '?';
  static String _cachedName = '';
  static String _cachedEmail = '';
  static String _cachedCompany = '';
  static Uint8List? _cachedImageBytes;

  StreamSubscription<DocumentSnapshot>? _userSub;

  // ── Live clock ──
  late DateTime _now;
  late final Timer _clockTimer;

  // ── Services auto-advance ──
  Timer? _svcTimer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    // Apply cache instantly — no async gap
    if (_cachedName.isNotEmpty || _cachedPhotoUrl != null) {
      _initials = _cachedInitials;
      _photoUrl = _cachedPhotoUrl;
      _userName = _cachedName;
      _userEmail = _cachedEmail;
      _companyName = _cachedCompany;
      if (_cachedPhotoUrl != null && _cachedImageBytes == null) {
        _cachedImageBytes = _decodeBase64Photo(_cachedPhotoUrl!);
      }
    }
    _subscribeToUser();
    Future.delayed(const Duration(seconds: 2), _runOnceStatusRefresh);
    // Init inline calendar
    final now = DateTime.now();
    _calYear = now.year;
    _calMonth = now.month;
    _loadCalendarData();
    _loadServices();
    // Auto-advance services carousel every 4 seconds (same as website)
    _svcTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted && _services.isNotEmpty) {
        setState(() => _svcIndex = (_svcIndex + 1) % _services.length);
      }
    });
  }

  void _subscribeToUser() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _userSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((doc) {
          if (!mounted) return;
          final data = doc.data() ?? {};
          final name = data['name'] as String? ?? '';
          final firstName = data['firstName'] as String? ?? '';
          final companyName = data['companyName'] as String? ?? '';
          final photo = data['photoUrl'] as String?;
          // Prefer Firestore-stored email; fall back to FirebaseAuth if missing
          final email = (data['email'] as String? ?? '').isNotEmpty
              ? data['email'] as String
              : FirebaseAuth.instance.currentUser?.email ?? '';
          debugPrint(
            '🔍 email from Firestore: ${data['email']} | FirebaseAuth: ${FirebaseAuth.instance.currentUser?.email} | resolved: $email',
          );
          String ini = '?';
          if (name.isNotEmpty) {
            final parts = name.trim().split(' ');
            ini = parts.length >= 2
                ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
                : parts[0][0].toUpperCase();
          }
          // Decode base64 once here — not on every build()
          if (photo != null && photo != _cachedPhotoUrl) {
            _cachedImageBytes = _decodeBase64Photo(photo);
          } else if (photo == null) {
            _cachedImageBytes = null;
          }
          _cachedInitials = ini;
          _cachedPhotoUrl = photo;
          _cachedName = name;
          _cachedEmail = email;
          _cachedCompany = companyName;
          final nameChanged = name != _userName;
          if (mounted)
            setState(() {
              _initials = ini;
              _photoUrl = photo;
              _userName = name;
              _userEmail = email;
              _firstName = firstName.isNotEmpty
                  ? firstName
                  : name.split(' ').first;
              _companyName = companyName;
            });
          // Reload calendar/agenda when user name first resolves or changes
          if (nameChanged && name.isNotEmpty) {
            _loadCalendarData();
            _loadRecentTransactions(name);
          }
        });
  }

  // Keep for back-compat
  Future<void> _loadInitials() async {}

  static Uint8List? _decodeBase64Photo(String url) {
    if (url.startsWith('data:image')) {
      final comma = url.indexOf(',');
      if (comma != -1) {
        try {
          return base64Decode(url.substring(comma + 1));
        } catch (_) {}
      }
    }
    return null;
  }

  Future<void> _runOnceStatusRefresh() async {
    if (!mounted || _statusRefreshDone) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('vehicles')
          .get();
      await _refreshVehicleStatuses(snap.docs, _userName);
    } catch (_) {}
  }

  @override
  void dispose() {
    _userSub?.cancel();
    _clockTimer.cancel();
    _svcTimer?.cancel();
    super.dispose();
  }

  /// Returns the correct ImageProvider — uses pre-decoded bytes to avoid per-frame decoding.
  ImageProvider _avatarProvider(String url) {
    if (_cachedImageBytes != null && url.startsWith('data:image')) {
      return MemoryImage(_cachedImageBytes!);
    }
    return NetworkImage(url);
  }

  // nav items moved to CustomerBottomNavBar
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildTopBar(),
      body: Stack(
        children: [
          _buildBody(),
          // ── Draggable AI FAB ───────────────────────────────────────────
          Positioned(
            right:  _fabRight,
            bottom: _fabBottom,
            child: AnimatedScale(
              scale: _fabDragging ? 1.12 : 1.0,
              duration: const Duration(milliseconds: 150),
              child: _AiStatusFab(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CustomerSmartAI()),
                ),
                onDragStart: () => setState(() => _fabDragging = true),
                onDragUpdate: (globalPos) {
                  final size = MediaQuery.of(context).size;
                  setState(() {
                    _fabRight  = (size.width  - globalPos.dx - 45).clamp(0.0, size.width  - 90);
                    _fabBottom = (size.height - globalPos.dy - 45).clamp(0.0, size.height - 90);
                  });
                },
                onDragEnd: () => setState(() => _fabDragging = false),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: CustomerBottomNavBar(
        currentIndex: _currentIndex,
        onTap: (i) {
          if (i == 1) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CustomerMyBookings()),
            );
          } else if (i == 2) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CustomerPmsScreen()),
            );
          } else if (i == 3) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const UserProfile(role: UserRole.customer),
              ),
            ).then((_) => _loadInitials());
          } else {
            setState(() => _currentIndex = i);
          }
        },
      ),
    );
  }

  PreferredSizeWidget _buildTopBar() {
    final fullName = _userName.isNotEmpty ? _userName : 'Guest';
    final email = _userEmail.isNotEmpty ? _userEmail : '';

    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      toolbarHeight: 72,
      automaticallyImplyLeading: false,
      title: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const UserProfile(role: UserRole.customer),
              ),
            ).then((_) => _loadInitials()),
            child: CircleAvatar(
              radius: 24,
              backgroundColor: const Color(0xFFf0f4f8),
              backgroundImage: _photoUrl != null
                  ? _avatarProvider(_photoUrl!)
                  : null,
              onBackgroundImageError: _photoUrl != null ? (_, __) {} : null,
              child: Text(
                _initials,
                style: TextStyle(
                  color: (_photoUrl != null && _cachedImageBytes != null)
                      ? Colors.transparent
                      : const Color(0xFF1a202c),
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  fullName,
                  style: const TextStyle(
                    color: Color(0xFF1a202c),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                if (email.isNotEmpty)
                  Text(
                    email,
                    style: const TextStyle(
                      color: Color(0xFFa0aec0),
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      height: 1.2,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: NotifBadge(
            role: NotificationRole.customer,
            iconColor: const Color(0xFF1a3560),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    const AppNotifications(role: NotificationRole.customer),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    switch (_currentIndex) {
      case 0:
        return _buildVehicles();
      // cases 1, 2, 3, 4 all handled via Navigator.push
      default:
        return _buildVehicles();
    }
  }

  // ── MY VEHICLES ──
  Widget _buildVehicles() {
    if (_userName.isEmpty) {
      // Show card with zeros while user data loads
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildWelcomeCard(),
            const SizedBox(height: 16),
            _buildInlineCalendar(),
            const SizedBox(height: 16),
            const Text(
              'My Vehicles',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1a202c),
              ),
            ),
            const SizedBox(height: 40),
            const Center(child: CircularProgressIndicator()),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: _red,
      onRefresh: () async {
        _statusRefreshDone = false; // allow re-check on manual refresh
        await _loadCalendarData();
        final snap = await FirebaseFirestore.instance
            .collection('vehicles')
            .get();
        await _refreshVehicleStatuses(snap.docs, _userName);
      },
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('service_bookings')
            .where('customerId', isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '')
            .snapshots(),
        builder: (context, bookingSnap) {
          // Collect vehicle IDs/plates that are currently Under Maintenance from bookings
          final underMaintenancePlates = <String>{};
          final underMaintenanceVehicleIds = <String>{};
          for (final doc in bookingSnap.data?.docs ?? []) {
            final data = doc.data() as Map<String, dynamic>;
            final status = (data['status'] as String? ?? '').toLowerCase();
            if (status == 'under maintenance') {
              final plate = (data['plate'] as String? ?? '').toLowerCase();
              final vehicleId = (data['vehicleId'] as String? ?? '');
              if (plate.isNotEmpty) underMaintenancePlates.add(plate);
              if (vehicleId.isNotEmpty) underMaintenanceVehicleIds.add(vehicleId);
            }
          }

        return StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('vehicles').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final allDocs = snapshot.data?.docs ?? [];
          final userName = _userName;

          final vehicles = allDocs
              .where((d) {
                final data = d.data() as Map<String, dynamic>;
                final owner = (data['owner'] as String? ?? '').toLowerCase();
                final uname = userName.toLowerCase();
                final cname = _companyName.toLowerCase();
                return owner == uname || (cname.isNotEmpty && owner == cname);
              })
              .map((d) {
                final data = d.data() as Map<String, dynamic>;
                final plate = data['plate'] as String? ?? '';
                final docId = d.id;
                final lastSvcDate = data['lastSvcDate'] as String? ?? '';
                final svcFreq = data['svcFreq'] as String? ?? '';
                // Override status from booking if vehicle has an active
                // 'Under Maintenance' booking in service_bookings
                final isUnderMaintenance =
                    underMaintenancePlates.contains(plate.toLowerCase()) ||
                    underMaintenanceVehicleIds.contains(docId);
                // Use live-computed PMS status so Due Today / Due This Week
                // are always accurate regardless of stale Firestore field
                final liveStatus = isUnderMaintenance
                    ? 'Under Maintenance'
                    : _computeStatus(lastSvcDate, svcFreq);
                return <String, String>{
                  'id': docId,
                  'plate': plate,
                  'desc': data['desc'] as String? ?? '',
                  'type': data['type'] as String? ?? '',
                  'status': liveStatus,
                  'lastSvcDate': lastSvcDate,
                  'lastSvcOdo':
                      (data['lastSvcOdo'] ?? data['lastServiceOdometer'] ?? '')
                          .toString(),
                  'odo': data['odo'] as String? ?? '',
                  'svcFreq': svcFreq,
                };
              })
              .toList();

          // Update nav icon based on fleet type (only once when vehicles first load)
          if (!_iconComputed && vehicles.isNotEmpty) {
            _iconComputed = true;
            _fleetNavIcon = _fleetIcon(vehicles);
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildWelcomeCard(
                  active: vehicles.where((v) {
                    final s = (v['status'] ?? '').toLowerCase();
                    if (s == 'under maintenance') return false;
                    // Exclude if under maintenance via booking
                    final plate = (v['plate'] ?? '').toLowerCase();
                    final vId = v['id'] ?? '';
                    if (underMaintenancePlates.contains(plate) ||
                        underMaintenanceVehicleIds.contains(vId)) return false;
                    final computed = _computeStatus(
                      v['lastSvcDate'] ?? '',
                      v['svcFreq'] ?? '',
                    ).toLowerCase();
                    // Active = not any PMS alert and not under maintenance
                    return computed != 'overdue' &&
                        computed != 'due today' &&
                        computed != 'due this week' &&
                        computed != 'due soon' &&
                        s != 'overdue' &&
                        s != 'due today' &&
                        s != 'due this week' &&
                        s != 'due soon';
                  }).length,
                  dueToday: vehicles.where((v) {
                    // Use live-computed status so it's always accurate
                    final computed = _computeStatus(
                      v['lastSvcDate'] ?? '',
                      v['svcFreq'] ?? '',
                    );
                    // Also accept stored 'due today' in case compute can't run
                    final stored = (v['status'] ?? '').toLowerCase();
                    return computed == 'Due Today' || stored == 'due today';
                  }).length,
                  dueThisWeek: vehicles.where((v) {
                    final computed = _computeStatus(
                      v['lastSvcDate'] ?? '',
                      v['svcFreq'] ?? '',
                    );
                    final stored = (v['status'] ?? '').toLowerCase();
                    // Due This Week — live computed wins; exclude Due Today
                    if (computed == 'Due Today') return false;
                    return computed == 'Due This Week' || stored == 'due this week';
                  }).length,
                  maintenance: vehicles.where((v) {
                    final s = (v['status'] ?? '').toLowerCase();
                    if (s == 'under maintenance') return true;
                    // Also count if this vehicle has an active Under Maintenance booking
                    final plate = (v['plate'] ?? '').toLowerCase();
                    final vId = v['id'] ?? '';
                    return underMaintenancePlates.contains(plate) ||
                        underMaintenanceVehicleIds.contains(vId);
                  }).length,
                ),
                const SizedBox(height: 16),
                // ── Services carousel ──
                _buildServicesCarousel(),
                const SizedBox(height: 16),
                // ── Inline calendar ──
                _buildInlineCalendar(),
                const SizedBox(height: 16),
                // ── My Vehicles overview ──
                _buildVehiclesOverview(vehicles),
                const SizedBox(height: 16),
                // ── Recent Service Transactions ──
                _buildRecentTransactions(vehicles),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ); // closes vehicles StreamBuilder
        }, // closes bookings StreamBuilder builder
      ), // closes bookings StreamBuilder
    );
  }

  Widget _buildWelcomeCard({
    int active = 0,
    int dueToday = 0,
    int dueThisWeek = 0,
    int maintenance = 0,
  }) {
    const dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    const monthNames = [
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

    final day = dayNames[_now.weekday % 7];
    final mon = monthNames[_now.month - 1];
    final dayNum = '${_now.day}';

    final h = _now.hour;
    final greet = h < 12
        ? 'Good morning,'
        : h < 17
        ? 'Good afternoon,'
        : 'Good evening,';
    final first = _firstName.isNotEmpty
        ? _firstName
        : _userName.isNotEmpty
        ? () {
            final parts = _userName.split(' ');
            if (parts.length >= 2) {
              return '${parts[0]} ${parts[1]}';
            }
            return parts.first;
          }()
        : 'Guest';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF004B5F), Color(0xFFEE152A)],
          stops: [0.0, 1.0],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0x40EE152A),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Greeting row ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ── Left: greeting + first name ──
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        greet,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          height: 1.2,
                        ),
                      ),
                      Text(
                        first,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
                // ── Right: square date box ──
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white24, width: 1),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$mon ${_now.year}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dayNum,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        day,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Today's message row ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Builder(
              builder: (ctx) {
                final todayKey =
                    '${_now.year}-${_now.month.toString().padLeft(2, '0')}-${_now.day.toString().padLeft(2, '0')}';
                final todayEvents = _calEvents[todayKey] ?? [];
                final hasPms = todayEvents.any((e) => e['type'] == 'pms');
                final hasBooking = todayEvents.any(
                  (e) => e['type'] == 'booking',
                );

                final String icon;
                final String line1;
                final String line2;

                if (hasPms && hasBooking) {
                  icon = '🚗';
                  line1 = 'PMS & service booked';
                  line2 = 'You have scheduled activities today.';
                } else if (hasPms) {
                  icon = '🔧';
                  line1 = 'PMS due today';
                  line2 = 'Your vehicle needs attention today.';
                } else if (hasBooking) {
                  icon = '📅';
                  line1 = 'Service scheduled today';
                  line2 = 'Your appointment is ready. Drive safe!';
                } else {
                  icon = '✅';
                  line1 = 'All clear today';
                  line2 = 'No scheduled services for today.';
                }

                return Row(
                  children: [
                    Text(icon, style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            line1,
                            style: TextStyle(
                              color: (hasPms || hasBooking)
                                  ? const Color(0xFFfcd34d)
                                  : Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            line2,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 10,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          // ── Stats grid ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _customerStatCard(icon: Icons.check_circle_outline, value: '$active', label: 'Active')),
                  const SizedBox(width: 8),
                  Expanded(child: _customerStatCard(icon: Icons.today_outlined, value: '$dueToday', label: 'Due\nToday')),
                  const SizedBox(width: 8),
                  Expanded(child: _customerStatCard(icon: Icons.date_range_outlined, value: '$dueThisWeek', label: 'This\nWeek')),
                  const SizedBox(width: 8),
                  Expanded(child: _customerStatCard(icon: Icons.build_circle_outlined, value: '$maintenance', label: 'Under\nMaintenance')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _inlineStatItem(String label, String value, Color color) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: color.withOpacity(0.7),
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dividerLine() => Container(
    width: 1,
    height: 28,
    color: Colors.white12,
    margin: const EdgeInsets.symmetric(horizontal: 4),
  );

  /// Frosted-glass stat card for the customer greeting banner.
  Widget _customerStatCard({
    required IconData icon,
    required String value,
    required String label,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, color: Colors.white, size: 16),
            ),
            const Spacer(),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vehicleIcon(
    String type, {
    double size = 26,
    Color color = _darkerTeal,
  }) {
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
    final allTruck = vehicles.every(
      (v) => (v['type'] ?? '').toLowerCase().contains('truck'),
    );
    final allCar = vehicles.every(
      (v) => !(v['type'] ?? '').toLowerCase().contains('truck'),
    );
    if (allTruck) return Icons.local_shipping_outlined;
    if (allCar) return Icons.directions_car_outlined;
    return Icons.commute_outlined; // mixed fleet
  }

  Widget _buildRecentTransactions(List<Map<String, String>> vehicles) {
    if (vehicles.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(
                bottom: BorderSide(color: Color(0xFFe2e8f0), width: 1),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Recent Services',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1a202c),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CustomerPmsScreen(),
                    ),
                  ),
                  child: const Text(
                    'See all →',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFE8001C),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ── Body ──
          if (_txnsLoading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_recentTxns.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: Text(
                  'No completed services yet.',
                  style: TextStyle(color: Color(0xFF718096), fontSize: 12),
                ),
              ),
            )
          else
            Column(
              children: _recentTxns.asMap().entries.map((entry) {
                final i = entry.key;
                final data = entry.value;
                final plate = data['plate'] as String? ?? '—';
                final desc =
                    data['desc'] as String? ??
                    data['vehicleDesc'] as String? ??
                    '';
                final date =
                    data['date'] as String? ??
                    data['serviceDate'] as String? ??
                    '';
                // Try svcRows first (list of {name, qty, uom} maps), then services list, then serviceType
                final svcRows = data['svcRows'] as List? ?? [];
                final svcNames = svcRows
                    .where(
                      (r) =>
                          r is Map && (r['name'] as String? ?? '').isNotEmpty,
                    )
                    .map((r) => r['name'] as String)
                    .toList();
                final svcs = (data['services'] as List?)?.cast<String>() ?? [];
                final svcText = svcNames.isNotEmpty
                    ? svcNames.join(', ')
                    : svcs.isNotEmpty
                    ? svcs.join(', ')
                    : (data['serviceType'] as String? ??
                          data['type'] as String? ??
                          'Service');
                final isLast = i == _recentTxns.length - 1;

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: const Color(0xFF1a3560).withOpacity(0.08),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.build_outlined,
                              color: Color(0xFF1a3560),
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  svcText,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1a202c),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '$plate${desc.isNotEmpty ? ' · $desc' : ''}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF718096),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
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
                                  color: Colors.green.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  'Completed',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.green,
                                  ),
                                ),
                              ),
                              if (date.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  date,
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
                    if (!isLast)
                      const Divider(height: 1, indent: 68, endIndent: 16),
                  ],
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildVehiclesOverview(List<Map<String, String>> vehicles) {
    if (vehicles.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
          ],
        ),
        child: const Center(
          child: Text(
            'No vehicles registered under your name.',
            style: TextStyle(color: Color(0xFF718096)),
          ),
        ),
      );
    }

    // Status color + label helpers
    Color _sColor(String s) {
      switch (s.toLowerCase()) {
        case 'overdue':
          return const Color(0xFFE8001C);
        case 'due today':
          return const Color(0xFF0033A0);
        case 'due this week':
          return const Color(0xFFdd6b20);
        case 'due soon':
          return Colors.orange;
        case 'under maintenance':
          return const Color(0xFFea580c);
        default:
          return const Color(0xFF16a34a);
      }
    }

    String _sLabel(String s) {
      switch (s.toLowerCase()) {
        case 'overdue':
          return 'Overdue';
        case 'due today':
          return 'Due Today';
        case 'due this week':
          return 'Due This Week';
        case 'due soon':
          return 'Due Soon';
        case 'under maintenance':
          return 'Under Maintenance';
        default:
          return 'Active';
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(
                bottom: BorderSide(color: Color(0xFFe2e8f0), width: 1),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'My Vehicles',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1a202c),
                  ),
                ),
                Text(
                  '${vehicles.length} vehicle${vehicles.length != 1 ? 's' : ''}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF718096),
                  ),
                ),
              ],
            ),
          ),

          // ── Body: list + donut ──
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ── Vehicle list ──
                Expanded(
                  child: Column(
                    children: vehicles.map((v) {
                      final color = _sColor(v['status'] ?? '');
                      final label = _sLabel(v['status'] ?? '');
                      final isTruck = (v['type'] ?? '').toLowerCase().contains(
                        'truck',
                      );
                      return GestureDetector(
                        onTap: () => _showVehicleHistory(v),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF1a3560,
                                  ).withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  isTruck
                                      ? Icons.local_shipping_outlined
                                      : Icons.directions_car_outlined,
                                  color: const Color(0xFF1a3560),
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      v['plate']!,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF1a202c),
                                      ),
                                    ),
                                    Text(
                                      v['desc']!,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFF718096),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: color,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: () => _showVehicleHistory(v),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.transparent,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: const Color(0xFFE8001C),
                                      width: 1,
                                    ),
                                  ),
                                  child: const Text(
                                    'View',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFFE8001C),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _vehicleCard(Map<String, String> v) {
    final status = v['status'] ?? 'On Track';
    final statusColor = status == 'Overdue'
        ? _red
        : status == 'Due Today'
        ? const Color(0xFF0033A0)
        : status == 'Due This Week'
        ? const Color(0xFFdd6b20)
        : status == 'Due Soon'
        ? Colors.orange
        : status == 'Under Maintenance'
        ? const Color(0xFFea580c)
        : const Color(0xFF16a34a); // On Track + Scheduled → Active
    final statusBg = status == 'Overdue'
        ? const Color(0xFFFFF5F5)
        : status == 'Due Today'
        ? const Color(0xFFEEF2FF)
        : status == 'Due This Week'
        ? const Color(0xFFFFFBEB)
        : status == 'Due Soon'
        ? const Color(0xFFFFF8E1)
        : status == 'Under Maintenance'
        ? const Color(0xFFFFF8E1)
        : const Color(0xFFF0FFF4);
    final statusLabel = status == 'Overdue'
        ? 'Overdue'
        : status == 'Due Today'
        ? 'Due Today'
        : status == 'Due This Week'
        ? 'Due This Week'
        : status == 'Due Soon'
        ? 'Due Soon'
        : status == 'Under Maintenance'
        ? 'Under Maintenance'
        : 'Active'; // On Track + Scheduled

    return GestureDetector(
      onTap: () => _showVehicleHistory(v),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFe2e8f0), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header: plate/desc + status badge ──
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          v['plate']!,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: Color(0xFF1a202c),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          v['desc']!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF718096),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Body: meta row (odometer + last service) ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Row(
                children: [
                  _metaItem(
                    Icons.speed_outlined,
                    v['odo']!.isNotEmpty ? v['odo']! : '—',
                  ),
                  const SizedBox(width: 20),
                  _metaItem(
                    Icons.calendar_today_outlined,
                    v['lastSvcDate']!.isNotEmpty
                        ? _fmtDateLong(v['lastSvcDate']!)
                        : '—',
                  ),
                ],
              ),
            ),

            // ── Footer: "View details" + chevron ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(14),
                ),
                border: Border(top: BorderSide(color: Color(0xFFF0F4F8))),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'View details',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFE8001C),
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 16, color: Color(0xFFE8001C)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metaItem(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 13, color: const Color(0xFF718096)),
        const SizedBox(width: 5),
        Text(
          text,
          style: const TextStyle(fontSize: 11, color: Color(0xFF718096)),
        ),
      ],
    );
  }

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

  String _fmtDateLong(String dateStr) {
    if (dateStr.isEmpty) return '—';
    final d = DateTime.tryParse(dateStr);
    if (d == null) return dateStr;
    return '${_monthsFull[d.month - 1]} ${d.day}, ${d.year}';
  }

  Widget _stripDivider() => Container(
    width: 1,
    height: 14,
    color: const Color(0xFFe2e8f0),
    margin: const EdgeInsets.symmetric(horizontal: 10),
  );

  Widget _infoChip(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 13, color: const Color(0xFF718096)),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(fontSize: 11, color: Color(0xFF718096)),
        ),
      ],
    );
  }

  void _showVehicleHistory(Map<String, String> v) {
    final status = v['status'] ?? 'On Track';
    final statusColor = status == 'Overdue'
        ? _red
        : status == 'Due Today'
        ? const Color(0xFF0033A0)
        : status == 'Due This Week'
        ? const Color(0xFFdd6b20)
        : status == 'Due Soon'
        ? Colors.orange
        : status == 'Under Maintenance'
        ? const Color(0xFFea580c)
        : const Color(0xFF16a34a); // On Track + Scheduled → Active

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
        nextPms =
            '${next.year}-${next.month.toString().padLeft(2, '0')}-${next.day.toString().padLeft(2, '0')}';
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
      statusLabel =
          'Overdue ${(-daysUntil)} day${(-daysUntil) != 1 ? 's' : ''}';
    } else if (daysUntil == 0) {
      statusLabel = 'Due Today';
    } else if (daysUntil <= 7) {
      statusLabel =
          'Due in $daysUntil day${daysUntil != 1 ? 's' : ''} (This Week)';
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
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (_, ctrl) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF7F8FA),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF004B5F), Color(0xFFEE152A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white38,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                v['plate']!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                v['desc']!,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Body
              Expanded(
                child: SingleChildScrollView(
                  controller: ctrl,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Vehicle info card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            _detailRow(
                              Icons.speed_outlined,
                              'Last Service Odometer',
                              v['lastSvcOdo']!.isNotEmpty &&
                                      v['lastSvcOdo'] != '0'
                                  ? '${int.tryParse(v['lastSvcOdo']!.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0} km'
                                  : '—',
                              const Color(0xFF1a3560),
                            ),
                            _divider(),
                            _detailRow(
                              Icons.calendar_today_outlined,
                              'Last Service',
                              lastSvcDate.isNotEmpty
                                  ? _fmtDateLong(lastSvcDate)
                                  : '—',
                              const Color(0xFF1a3560),
                            ),
                            _divider(),
                            _detailRow(
                              Icons.event_outlined,
                              'Next PMS Due',
                              _fmtDateLong(nextPms),
                              const Color(0xFF1a3560),
                            ),
                            _divider(),
                            _detailRow(
                              Icons.info_outline,
                              'Status',
                              statusLabel,
                              const Color(0xFF1a3560),
                            ),
                          ],
                        ),
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
                            if (bookSnap.connectionState ==
                                ConnectionState.waiting) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFFE8001C),
                                    ),
                                  ),
                                ),
                              );
                            }

                            final hasBooking =
                                (bookSnap.data?.docs.isNotEmpty) ?? false;
                            final bookingData = hasBooking
                                ? bookSnap.data!.docs.first.data()
                                      as Map<String, dynamic>
                                : <String, dynamic>{};
                            final bookingStatus = hasBooking
                                ? bookingData['status'] as String? ?? 'Pending'
                                : '';
                            final bookingDate = hasBooking
                                ? bookingData['preferredDate'] as String? ?? ''
                                : '';
                            final bookingTime = hasBooking
                                ? bookingData['preferredTime'] as String? ?? ''
                                : '';
                            final previousDate = hasBooking
                                ? bookingData['previousDate'] as String? ?? ''
                                : '';
                            final isRescheduled =
                                previousDate.isNotEmpty &&
                                previousDate != bookingDate;
                            if (hasBooking) {
                              // Already booked — show status badge instead of Book button
                              final isApproved = bookingStatus == 'Approved';
                              final badgeColor = isApproved
                                  ? Colors.green
                                  : Colors.orange;
                              final badgeBg = isApproved
                                  ? const Color(0xFFF0FFF4)
                                  : const Color(0xFFFFF8E1);
                              final badgeBorder = isApproved
                                  ? const Color(0xFFC6F6D5)
                                  : const Color(0xFFFBD38D);

                              // Format the booking date for display
                              String formattedDate = '';
                              if (bookingDate.isNotEmpty) {
                                final parts = bookingDate.split('-');
                                if (parts.length == 3) {
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
                                  final m = (int.tryParse(parts[1]) ?? 1) - 1;
                                  final d = int.tryParse(parts[2]) ?? 1;
                                  final y = int.tryParse(parts[0]) ?? 0;
                                  formattedDate = '${months[m]} $d, $y';
                                }
                              }

                              return Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: badgeBg,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: badgeBorder,
                                    width: 1.5,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        color: badgeColor.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(
                                        isApproved
                                            ? Icons.check_circle_outline
                                            : Icons.access_time_outlined,
                                        size: 18,
                                        color: badgeColor,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            isRescheduled
                                                ? 'Booking Rescheduled'
                                                : 'Service Already Booked',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: badgeColor,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            isRescheduled
                                                ? 'Rescheduled${formattedDate.isNotEmpty ? ' to $formattedDate${bookingTime.isNotEmpty ? ', $bookingTime' : ''}' : ''}.'
                                                : isApproved
                                                ? 'Confirmed${formattedDate.isNotEmpty ? ' — $formattedDate${bookingTime.isNotEmpty ? ', $bookingTime' : ''}' : ''}.'
                                                : 'Pending approval${formattedDate.isNotEmpty ? ' — $formattedDate${bookingTime.isNotEmpty ? ', $bookingTime' : ''}' : ''}.',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Color(0xFF718096),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () {
                                        Navigator.pop(context); // close modal
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const CustomerMyBookings(),
                                          ),
                                        );
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: badgeColor,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: const Text(
                                          'View',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            // No active booking — show Book Now button
                            return GestureDetector(
                              onTap: () {
                                Navigator.pop(context); // close modal
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => CustomerBookService(
                                      preselectedVehicleId: v['id']!,
                                    ),
                                  ),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF5F5),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFFFED7D7),
                                    width: 1.5,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFFE8001C,
                                        ).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.calendar_month_outlined,
                                        size: 18,
                                        color: Color(0xFFE8001C),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    const Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'PMS is overdue',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFFE8001C),
                                            ),
                                          ),
                                          SizedBox(height: 2),
                                          Text(
                                            'Book a service now to avoid further issues.',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Color(0xFF718096),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE8001C),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text(
                                        'Book',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _svcMatLabel(IconData icon, String label, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 13, color: color),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _svcMatRow(Map<String, dynamic> item, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item['name'] as String? ?? '',
              style: const TextStyle(fontSize: 12, color: Color(0xFF1a202c)),
            ),
          ),
          Text(
            '${item['qty']} ${item['uom']}',
            style: const TextStyle(fontSize: 11, color: Color(0xFF718096)),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF718096),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1a202c),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
    if (daysUntil < 0) return 'Overdue';
    if (daysUntil == 0) return 'Due Today';
    if (daysUntil <= 7) return 'Due This Week';
    if (daysUntil <= 14) return 'Due Soon';
    if (daysUntil <= 30) return 'Scheduled';
    return 'On Track';
  }

  bool _refreshing = false;
  bool _statusRefreshDone = false; // only run once per session

  // ── Inline calendar state ──
  late int _calYear;
  late int _calMonth;
  String? _calSelectedDay;
  Map<String, List<Map<String, dynamic>>> _calEvents = {};
  bool _calLoading = true;
  static const _calMonths = [
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
  static const _calDow = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  // ── Services carousel state ──
  List<Map<String, String>> _services = [];
  bool _servicesLoading = true;
  int _svcIndex = 0; // current card index for single-card viewer

  // ── Recent transactions cache ──
  List<Map<String, dynamic>> _recentTxns = [];
  bool _txnsLoading = true;

  Future<void> _loadServices() async {
    try {
      // Fetch all items and filter client-side to avoid case/missing-field issues
      final snap = await FirebaseFirestore.instance
          .collection('item_master')
          .get();
      final list = snap.docs
          .map((d) {
            final data = d.data();
            return <String, String>{
              'id': d.id,
              'name': data['name'] as String? ?? '',
              'group': data['group'] as String? ?? '',
              'uom': data['uom'] as String? ?? '',
              'cost': (data['cost'] ?? '').toString(),
              'type': data['type'] as String? ?? '',
            };
          })
          .where(
            (s) =>
                s['name']!.isNotEmpty && s['type']!.toLowerCase() == 'service',
          )
          .toList();
      debugPrint('🔧 Services loaded: ${list.length} items');
      if (mounted)
        setState(() {
          _services = list;
          _servicesLoading = false;
        });
    } catch (e) {
      debugPrint('❌ Services load error: $e');
      if (mounted) setState(() => _servicesLoading = false);
    }
  }

  Future<void> _loadRecentTransactions(String userName) async {
    try {
      // Fetch customer's vehicle plates first
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final uname = (userDoc.data()?['name'] as String? ?? '').toLowerCase();
      final cname = (userDoc.data()?['companyName'] as String? ?? '')
          .toLowerCase();

      final vSnap = await FirebaseFirestore.instance
          .collection('vehicles')
          .get();
      final plates = vSnap.docs
          .where((d) {
            final owner = (d.data()['owner'] as String? ?? '').toLowerCase();
            return owner == uname || (cname.isNotEmpty && owner == cname);
          })
          .map((d) => (d.data()['plate'] as String? ?? '').toLowerCase())
          .where((p) => p.isNotEmpty)
          .toSet();

      if (plates.isEmpty) {
        if (mounted) setState(() => _txnsLoading = false);
        return;
      }

      final snap = await FirebaseFirestore.instance
          .collection('maintenance')
          .where('status', isEqualTo: 'Completed')
          .get();

      final filtered = snap.docs
          .where((d) {
            final plate = (d.data()['plate'] as String? ?? '').toLowerCase();
            return plates.contains(plate);
          })
          .map((d) => <String, dynamic>{...d.data(), '_id': d.id})
          .toList();

      // Sort by createdAt descending client-side
      filtered.sort((a, b) {
        final aTs = a['createdAt'];
        final bTs = b['createdAt'];
        if (aTs is Timestamp && bTs is Timestamp) return bTs.compareTo(aTs);
        return 0;
      });

      if (mounted)
        setState(() {
          _recentTxns = filtered.take(5).toList();
          _txnsLoading = false;
        });
    } catch (e) {
      debugPrint('❌ Transactions load error: $e');
      if (mounted) setState(() => _txnsLoading = false);
    }
  }

  Widget _buildServicesCarousel() {
    if (_servicesLoading) {
      return Container(
        height: 180,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1a202c), Color(0xFF2d3748), Color(0xFFE8001C)],
            stops: [0.0, 0.55, 1.0],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Center(
          child: CircularProgressIndicator(
            color: Colors.white54,
            strokeWidth: 2,
          ),
        ),
      );
    }
    if (_services.isEmpty) {
      return Container(
        height: 180,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1a202c), Color(0xFF2d3748), Color(0xFFE8001C)],
            stops: [0.0, 0.55, 1.0],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Center(
          child: Text(
            'No services available.',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ),
      );
    }

    final serviceIcons = <String, IconData>{
      'oil': Icons.opacity_outlined,
      'tire': Icons.tire_repair_outlined,
      'brake': Icons.disc_full_outlined,
      'battery': Icons.battery_charging_full_outlined,
      'air': Icons.air_outlined,
      'wash': Icons.local_car_wash_outlined,
      'check': Icons.check_circle_outline,
      'lube': Icons.water_drop_outlined,
      'engine': Icons.settings_outlined,
      'filter': Icons.filter_alt_outlined,
      'align': Icons.linear_scale_outlined,
      'wiper': Icons.water_outlined,
      'light': Icons.lightbulb_outline,
      'belt': Icons.link_outlined,
      'fluid': Icons.water_drop_outlined,
    };

    IconData iconFor(String name) {
      final n = name.toLowerCase();
      for (final k in serviceIcons.keys) {
        if (n.contains(k)) return serviceIcons[k]!;
      }
      return Icons.build_outlined;
    }

    final s = _services[_svcIndex % _services.length];
    final icon = iconFor(s['name']!);
    final total = _services.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header ──
        const Text(
          'Our Services',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1a202c),
          ),
        ),
        const SizedBox(height: 12),

        // ── Single card ──
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.08, 0),
                end: Offset.zero,
              ).animate(anim),
              child: child,
            ),
          ),
          child: Container(
            key: ValueKey(_svcIndex),
            height: 210,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Colors.white, Color(0xFFFFECEC), Color(0xFFFFD6D6)],
                stops: [0.0, 0.55, 1.0],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.all(Radius.circular(20)),
              border: Border.all(color: const Color(0xFFFFCCCC), width: 1),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE8001C).withOpacity(0.12),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Stack(
              children: [
                // Content
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Icon badge + service name
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8001C).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              icon,
                              size: 18,
                              color: const Color(0xFFE8001C),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              s['name']!,
                              style: const TextStyle(
                                color: Color(0xFF1a202c),
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      // Car illustration
                      Expanded(
                        child: CustomPaint(
                          painter: const _SvcCarPainter(),
                          child: const SizedBox.expand(),
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Book Now + Next buttons
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CustomerBookService(
                                    preselectedVehicleId: '',
                                  ),
                                ),
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF004B5F),
                                      Color(0xFFEE152A),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(50),
                                ),
                                child: const Text(
                                  'Book Now',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (total > 1) ...[
                            const SizedBox(width: 10),
                            GestureDetector(
                              onTap: () {
                                _svcTimer?.cancel();
                                setState(
                                  () => _svcIndex = (_svcIndex + 1) % total,
                                );
                                // Restart auto-advance after manual tap
                                _svcTimer = Timer.periodic(
                                  const Duration(seconds: 4),
                                  (_) {
                                    if (mounted && _services.isNotEmpty) {
                                      setState(
                                        () => _svcIndex =
                                            (_svcIndex + 1) % _services.length,
                                      );
                                    }
                                  },
                                );
                              },
                              child: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFFE8001C,
                                  ).withOpacity(0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.chevron_right,
                                  color: Color(0xFFE8001C),
                                  size: 22,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _loadCalendarData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _calLoading = false);
      return;
    }
    final db = FirebaseFirestore.instance;
    final today = DateTime.now();
    final todayM = DateTime(today.year, today.month, today.day);
    final events = <String, List<Map<String, dynamic>>>{};

    // ── Bookings ──
    final bookSnap = await db
        .collection('service_bookings')
        .where('customerId', isEqualTo: uid)
        .get();
    for (final doc in bookSnap.docs) {
      final data = doc.data();
      final date = data['preferredDate'] as String? ?? '';
      final status = (data['status'] as String? ?? '').toLowerCase();
      if (date.isEmpty) continue;
      if ([
        'completed',
        'under maintenance',
        'dismissed',
        'cancelled',
        'rejected',
      ].contains(status))
        continue;
      final due = DateTime.tryParse(date);
      if (due == null) continue;
      final days = DateTime(
        due.year,
        due.month,
        due.day,
      ).difference(todayM).inDays;
      events.putIfAbsent(date, () => []);
      events[date]!.add({
        'type': 'booking',
        'plate': data['plate'] ?? '—',
        'desc': data['vehicleDesc'] as String? ?? data['desc'] as String? ?? '',
        'services':
            (data['services'] as List?)?.cast<String>().join(', ') ?? '',
        'status': data['status'] ?? '',
        'time': data['preferredTime'] ?? '',
        'daysUntil': days,
        'urgency': 'booking',
      });
    }

    // ── PMS due dates ──
    final userDoc = await db.collection('users').doc(uid).get();
    final userName = (userDoc.data()?['name'] as String? ?? '').toLowerCase();
    final companyName = (userDoc.data()?['companyName'] as String? ?? '')
        .toLowerCase();
    if (userName.isNotEmpty) {
      final vSnap = await db.collection('vehicles').get();
      for (final doc in vSnap.docs) {
        final data = doc.data();
        final owner = (data['owner'] as String? ?? '').toLowerCase();
        if (owner != userName && (companyName.isEmpty || owner != companyName))
          continue;
        final plate = data['plate'] as String? ?? '';
        final lastSvc = data['lastSvcDate'] as String? ?? '';
        final freq = int.tryParse(data['svcFreq']?.toString() ?? '');
        if (lastSvc.isEmpty || freq == null || plate.isEmpty) continue;
        final lastDate = DateTime.tryParse(lastSvc);
        if (lastDate == null) continue;
        final next = DateTime(
          lastDate.year,
          lastDate.month + freq,
          lastDate.day,
        );
        final days = DateTime(
          next.year,
          next.month,
          next.day,
        ).difference(todayM).inDays;
        final key =
            '${next.year}-${next.month.toString().padLeft(2, '0')}-${next.day.toString().padLeft(2, '0')}';
        final urgency = days < 0
            ? 'overdue'
            : days == 0
            ? 'today'
            : days <= 7
            ? 'week'
            : 'upcoming';
        events.putIfAbsent(key, () => []);
        events[key]!.add({
          'type': 'pms',
          'plate': plate,
          'desc': data['desc'] as String? ?? '',
          'daysUntil': days,
          'urgency': urgency,
          'vehicleId': doc.id,
        });
      }
    }

    if (mounted)
      setState(() {
        _calEvents = events;
        _calLoading = false;
      });
  }

  Color _calUrgencyColor(String urgency) {
    switch (urgency) {
      case 'overdue':
        return const Color(0xFFE8001C);
      case 'today':
        return const Color(0xFF0033A0);
      case 'week':
        return const Color(0xFFed8936);
      case 'booking':
        return const Color(0xFF7c3aed);
      default:
        return const Color(0xFFEAB308);
    }
  }

  Widget _buildInlineCalendar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Header ──
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              border: Border(
                bottom: BorderSide(color: Color(0xFFe2e8f0), width: 1),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.calendar_month_outlined,
                  color: Color(0xFFE8001C),
                  size: 15,
                ),
                const SizedBox(width: 8),
                const Text(
                  'My Calendar',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1a202c),
                    letterSpacing: 0.4,
                  ),
                ),
                const Spacer(),
                // Month nav
                GestureDetector(
                  onTap: () => setState(() {
                    _calMonth--;
                    if (_calMonth < 1) {
                      _calMonth = 12;
                      _calYear--;
                    }
                    _calSelectedDay = null;
                  }),
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: const Color(0xFFf0f4f8),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.chevron_left,
                      size: 18,
                      color: Color(0xFF4a5568),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${_calMonths[_calMonth - 1]} $_calYear',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1a202c),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => setState(() {
                    _calMonth++;
                    if (_calMonth > 12) {
                      _calMonth = 1;
                      _calYear++;
                    }
                    _calSelectedDay = null;
                  }),
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: const Color(0xFFf0f4f8),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: Color(0xFF4a5568),
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (_calLoading)
            const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
              child: _buildCalGrid(),
            ),
            if (_calSelectedDay != null) _buildCalDayDetail(),
            // Legend
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
              child: Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  _calLegend(const Color(0xFFE8001C), 'Overdue'),
                  _calLegend(const Color(0xFFed8936), 'This Week'),
                  _calLegend(const Color(0xFFEAB308), 'Upcoming'),
                  _calLegend(const Color(0xFF0033A0), 'Today'),
                  _calLegend(const Color(0xFF7c3aed), 'Booked'),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _calLegend(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 4),
      Text(
        label,
        style: const TextStyle(fontSize: 10, color: Color(0xFF4a5568)),
      ),
    ],
  );

  Widget _buildCalGrid() {
    final now = DateTime.now();
    final todayKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final firstDay = DateTime(_calYear, _calMonth, 1);
    final offset = firstDay.weekday % 7;
    final daysInM = DateTime(_calYear, _calMonth + 1, 0).day;
    final prevDays = DateTime(_calYear, _calMonth, 0).day;
    final cells = <Widget>[];

    for (final d in _calDow) {
      cells.add(
        Center(
          child: Text(
            d,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: Color(0xFFa0aec0),
            ),
          ),
        ),
      );
    }
    for (int i = offset - 1; i >= 0; i--) {
      cells.add(_calEmptyCell('${prevDays - i}'));
    }
    for (int d = 1; d <= daysInM; d++) {
      final key =
          '$_calYear-${_calMonth.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
      final evts = _calEvents[key] ?? [];
      final isToday = key == todayKey;
      final isSel = key == _calSelectedDay;
      cells.add(
        GestureDetector(
          onTap: evts.isNotEmpty
              ? () => setState(() => _calSelectedDay = isSel ? null : key)
              : null,
          child: Container(
            decoration: BoxDecoration(
              color: isSel
                  ? const Color(0xFFebf8ff)
                  : isToday
                  ? const Color(0xFFf0fdfa)
                  : const Color(0xFFF7F8FA),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isSel
                    ? const Color(0xFF003087)
                    : isToday
                    ? const Color(0xFF0033A0)
                    : Colors.transparent,
                width: 1.5,
              ),
            ),
            padding: const EdgeInsets.all(2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$d',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                    color: isToday
                        ? const Color(0xFF0033A0)
                        : const Color(0xFF4a5568),
                  ),
                ),
                if (evts.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Wrap(
                    spacing: 2,
                    runSpacing: 1,
                    alignment: WrapAlignment.center,
                    children: evts
                        .take(3)
                        .map(
                          (e) => Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: _calUrgencyColor(
                                e['urgency'] as String? ?? 'upcoming',
                              ),
                              borderRadius: BorderRadius.circular(1.5),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }
    final trailing = (offset + daysInM) % 7;
    if (trailing != 0)
      for (int d = 1; d <= 7 - trailing; d++) cells.add(_calEmptyCell('$d'));

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 3,
      crossAxisSpacing: 3,
      childAspectRatio: 1.1,
      children: cells,
    );
  }

  Widget _calEmptyCell(String t) => Container(
    decoration: BoxDecoration(
      color: const Color(0xFFF7F8FA),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Center(
      child: Text(
        t,
        style: TextStyle(fontSize: 11, color: Colors.grey.shade300),
      ),
    ),
  );

  Widget _buildCalDayDetail() {
    final evts = _calEvents[_calSelectedDay] ?? [];
    if (evts.isEmpty) return const SizedBox.shrink();
    final parts = _calSelectedDay!.split('-');
    final title =
        '${_calMonths[int.parse(parts[1]) - 1]} ${int.parse(parts[2])}, ${parts[0]}';
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFe2e8f0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Color(0xFF718096),
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 6),
          ...evts.map((e) {
            final color = _calUrgencyColor(
              e['urgency'] as String? ?? 'upcoming',
            );
            final days = e['daysUntil'] as int;
            final isBooking = e['type'] == 'booking';
            final label = isBooking
                ? (days < 0
                      ? 'Past'
                      : days == 0
                      ? 'Today'
                      : 'In $days day${days != 1 ? 's' : ''}')
                : (days < 0
                      ? '${-days}d overdue'
                      : days == 0
                      ? 'Due Today'
                      : 'In $days day${days != 1 ? 's' : ''}');
            return Container(
              margin: const EdgeInsets.only(bottom: 5),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFe2e8f0)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e['plate'] as String? ?? '—',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1a202c),
                          ),
                        ),
                        if (isBooking &&
                            (e['services'] as String? ?? '').isNotEmpty)
                          Text(
                            e['services'] as String,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF718096),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _refreshVehicleStatuses(
    List<QueryDocumentSnapshot> docs,
    String userName,
  ) async {
    if (_refreshing || _statusRefreshDone) return;
    _refreshing = true;
    try {
      for (final doc in docs) {
        final raw = doc.data();
        if (raw is! Map<String, dynamic>) continue; // skip malformed docs
        final data = raw;
        final owner = data['owner'] as String? ?? '';
        if (owner.toLowerCase() != userName.toLowerCase()) continue;
        final currentStatus = data['status'] as String? ?? '';
        if (currentStatus == 'Under Maintenance') continue;
        if (currentStatus == 'Completed') continue;
        final computed = _computeStatus(
          data['lastSvcDate'] as String? ?? '',
          data['svcFreq'] as String? ?? '',
        );
        if (computed != currentStatus) {
          await doc.reference.update({'status': computed});
        }
      }
      _statusRefreshDone =
          true; // mark done so it doesn't run again this session
    } catch (_) {
      // ignore errors — statuses will sync on next app open
    } finally {
      _refreshing = false;
    }
  }

  // ── AI ASSISTANT (legacy inline widget — superseded by CustomerSmartAI full screen) ──
  final List<Map<String, String>> _chatMessages = [];
  final _chatCtrl = TextEditingController();

  Widget _buildSmartReports() {
    return Column(
      children: [
        // Chat header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: Colors.white,
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F4FF),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  '🤖',
                  style: TextStyle(fontSize: 20),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI Assistant',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Row(
                      children: [
                        CircleAvatar(radius: 4, backgroundColor: Colors.green),
                        SizedBox(width: 4),
                        Text(
                          'Online',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF718096),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _chatMessages.clear()),
                child: const Text(
                  '🗑️ Clear',
                  style: TextStyle(color: Color(0xFF718096), fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        // Messages
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_chatMessages.isEmpty) _buildWelcomeBubble(),
              ..._chatMessages.map(
                (m) => _buildChatBubble(m['text']!, m['role'] == 'user'),
              ),
            ],
          ),
        ),
        // Quick chips
        if (_chatMessages.isEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _chip('🚛 All my vehicles', 'Show all my vehicles'),
                _chip(
                  '🔵 Under maintenance',
                  'Which vehicles are under maintenance?',
                ),
                _chip('⚠️ PMS overdue', 'Which vehicles have PMS overdue?'),
                _chip('📅 Due soon', 'Which vehicles have PMS due soon?'),
                _chip('📋 History', 'Show maintenance history'),
              ],
            ),
          ),
        // Input
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          color: Colors.white,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _chatCtrl,
                  decoration: InputDecoration(
                    hintText: 'Ask about your vehicles...',
                    filled: true,
                    fillColor: const Color(0xFFF7F8FA),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                  onSubmitted: (v) => _sendMessage(v),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _sendMessage(_chatCtrl.text),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _red,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Icon(Icons.send, color: Colors.white, size: 18),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWelcomeBubble() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Hello! I'm your AI Assistant. 👋",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          SizedBox(height: 4),
          Text(
            'Ask me anything about your vehicles — PMS status, maintenance history, and more.',
            style: TextStyle(fontSize: 12, color: Color(0xFF718096)),
          ),
        ],
      ),
    );
  }

  Widget _buildChatBubble(String text, bool isUser) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isUser ? _red : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6),
          ],
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            color: isUser ? Colors.white : const Color(0xFF1a202c),
          ),
        ),
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
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF4a5568)),
        ),
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
        reply =
            'Mitsubishi L300 (DEF-9012) has PMS overdue. Please schedule a service soon.';
      } else if (lower.contains('due soon')) {
        reply = 'Isuzu Truck NQR (ABC-1234) has PMS due in 2 months.';
      } else if (lower.contains('history')) {
        reply =
            'Your vehicles have a total of 9 service records. Tap any vehicle to view full history.';
      } else if (lower.contains('vehicle') || lower.contains('fleet')) {
        reply =
            'You have 3 vehicles:\n• ABC-1234 - Isuzu Truck NQR (Good)\n• XYZ-5678 - Toyota Hilux (Maintenance)\n• DEF-9012 - Mitsubishi L300 (Overdue)';
      } else {
        reply =
            'I can help you with vehicle status, PMS schedules, and maintenance history. Try asking about your fleet!';
      }
      _chatMessages.add({'role': 'ai', 'text': reply});
    });
  }

  // ── NOTIFICATIONS ──
  Widget _buildNotifications() {
    final notifs = [
      {
        'title': 'PMS Overdue',
        'msg': 'DEF-9012 Mitsubishi L300 is overdue for PMS',
        'time': '1 hr ago',
        'icon': Icons.warning_amber_outlined,
        'color': Colors.red,
      },
      {
        'title': 'Service Complete',
        'msg': 'ABC-1234 oil change has been completed',
        'time': '3 hrs ago',
        'icon': Icons.check_circle_outline,
        'color': Colors.green,
      },
      {
        'title': 'PMS Due Soon',
        'msg': 'ABC-1234 Isuzu Truck is due for PMS in 2 months',
        'time': 'Yesterday',
        'icon': Icons.schedule_outlined,
        'color': Colors.amber,
      },
    ];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '🔔 Notifications',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              TextButton(
                onPressed: () {},
                child: const Text(
                  'Clear All',
                  style: TextStyle(color: Color(0xFF718096), fontSize: 12),
                ),
              ),
            ],
          ),
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
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: (n['color'] as Color).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        n['icon'] as IconData,
                        color: n['color'] as Color,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            n['title'] as String,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            n['msg'] as String,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF718096),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      n['time'] as String,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF718096),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
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
    if (mounted)
      setState(() {
        _alreadyPending = snap.docs.isNotEmpty;
        _checking = false;
      });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
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
        child: const Row(
          children: [
            Icon(Icons.schedule_outlined, color: Colors.amber, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'You already have a pending reschedule request for this vehicle.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.amber,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
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
        child: const Row(
          children: [
            Icon(Icons.check_circle_outline, color: Colors.green, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Reschedule request sent! The admin will review it shortly.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.green,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5F5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFED7D7), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.warning_amber_outlined,
                color: Color(0xFFE8001C),
                size: 16,
              ),
              SizedBox(width: 6),
              Text(
                'PMS is overdue — request a reschedule',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFE8001C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
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
                          colorScheme: const ColorScheme.light(
                            primary: Color(0xFFE8001C),
                          ),
                        ),
                        child: child!,
                      ),
                    );
                    if (picked != null) setState(() => _selectedDate = picked);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFe2e8f0)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 15,
                          color: Color(0xFF718096),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _selectedDate != null
                              ? '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}'
                              : 'Select preferred date',
                          style: TextStyle(
                            fontSize: 12,
                            color: _selectedDate != null
                                ? const Color(0xFF1a202c)
                                : const Color(0xFFa0aec0),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 40,
                child: ElevatedButton(
                  onPressed: _loading || _selectedDate == null
                      ? null
                      : () async {
                          setState(() => _loading = true);
                          try {
                            final uid =
                                FirebaseAuth.instance.currentUser?.uid ?? '';
                            final dateStr =
                                '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}';
                            await FirebaseFirestore.instance
                                .collection('pms_reschedule_requests')
                                .add({
                                  'vehicleId': widget.vehicleId,
                                  'plate': widget.plate,
                                  'customerId': uid,
                                  'preferredDate': dateStr,
                                  'status': 'Pending',
                                  'createdAt': FieldValue.serverTimestamp(),
                                });
                            if (mounted)
                              setState(() {
                                _sent = true;
                                _loading = false;
                              });
                          } catch (e) {
                            if (mounted) {
                              setState(() => _loading = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Error: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE8001C),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Request',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Service card car illustration painter ────────────────────────────────
class _SvcCarPainter extends CustomPainter {
  const _SvcCarPainter();

  void _drawRRect(
    Canvas c,
    double x,
    double y,
    double w,
    double h,
    double r, {
    Color? fill,
    Color? stroke,
    double lw = 1,
  }) {
    final rr = RRect.fromLTRBR(x, y, x + w, y + h, Radius.circular(r));
    if (fill != null) c.drawRRect(rr, Paint()..color = fill);
    if (stroke != null) {
      c.drawRRect(
        rr,
        Paint()
          ..color = stroke
          ..style = PaintingStyle.stroke
          ..strokeWidth = lw,
      );
    }
  }

  void _wheel(Canvas c, double cx, double cy, double r) {
    // outer
    c.drawCircle(Offset(cx, cy), r, Paint()..color = const Color(0xFFE8001C));
    c.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..color = Colors.white.withOpacity(0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    // hub
    c.drawCircle(
      Offset(cx, cy),
      r * 0.4,
      Paint()..color = Colors.white.withOpacity(0.6),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final gY = h * 0.82;

    final cw = w * 0.52;
    final cx = w * 0.50;
    final ch = cw * 0.40;

    // shadow
    final sg = RadialGradient(
      colors: [Colors.black.withOpacity(0.18), Colors.transparent],
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, gY + 3), width: cw * 0.88, height: 12),
      Paint()
        ..shader = sg.createShader(
          Rect.fromCircle(center: Offset(cx, gY + 3), radius: cw * 0.45),
        ),
    );

    // body
    final bodyGrad = LinearGradient(
      colors: [const Color(0xFFFFCCCC), const Color(0xFFFFB3B3)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    ).createShader(Rect.fromLTWH(cx - cw * 0.5, gY - ch, cw, ch));
    _drawRRect(
      canvas,
      cx - cw * 0.5,
      gY - ch * 0.52,
      cw,
      ch * 0.52,
      10,
      fill: const Color(0xFFFFCCCC),
      stroke: const Color(0xFFE8001C).withOpacity(0.25),
      lw: 1.4,
    );
    // repaint body with gradient
    canvas.drawRRect(
      RRect.fromLTRBR(
        cx - cw * 0.5,
        gY - ch * 0.52,
        cx + cw * 0.5,
        gY,
        const Radius.circular(10),
      ),
      Paint()..shader = bodyGrad,
    );

    // cabin path
    final cabinPath = Path()
      ..moveTo(cx - cw * 0.30, gY - ch * 0.52)
      ..quadraticBezierTo(
        cx - cw * 0.18,
        gY - ch * 0.96,
        cx - cw * 0.04,
        gY - ch * 0.98,
      )
      ..lineTo(cx + cw * 0.19, gY - ch * 0.98)
      ..quadraticBezierTo(
        cx + cw * 0.30,
        gY - ch * 0.94,
        cx + cw * 0.34,
        gY - ch * 0.52,
      )
      ..close();

    final cabGrad = LinearGradient(
      colors: [const Color(0xFFFFB3B3), const Color(0xFFFF9999)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    ).createShader(Rect.fromLTWH(cx - cw * 0.65, gY - ch, cw * 0.65, ch));

    canvas.drawPath(cabinPath, Paint()..shader = cabGrad);
    canvas.drawPath(
      cabinPath,
      Paint()
        ..color = const Color(0xFFE8001C).withOpacity(0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // windshield tint
    canvas.drawPath(cabinPath, Paint()..color = Colors.white.withOpacity(0.35));

    // headlight (right)
    _drawRRect(
      canvas,
      cx + cw * 0.44,
      gY - ch * 0.32,
      12,
      7,
      3,
      fill: const Color(0xFFFEF9C3),
    );
    // tail-light (left)
    _drawRRect(
      canvas,
      cx - cw * 0.50,
      gY - ch * 0.32,
      9,
      7,
      3,
      fill: const Color(0xFFE8001C).withOpacity(0.55),
    );

    // wheels
    _wheel(canvas, cx - cw * 0.30, gY + 1, cw * 0.13);
    _wheel(canvas, cx + cw * 0.26, gY + 1, cw * 0.13);
  }

  @override
  bool shouldRepaint(_SvcCarPainter old) => false;
}
