import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:http/http.dart' as http;
import 'alert_prefs.dart';
import 'admin_service_bookings.dart';
import 'admin_vehicle_maintenance.dart';
import 'admin_receiving.dart';
import 'admin_vehicles_list.dart';
import 'admin_dss.dart';
import 'admin_users.dart';
import 'customer_mybookings.dart';
import 'customer_dashboard.dart';
import 'staff_service_bookings.dart';

enum NotificationRole { admin, staff, customer }

/// Bell icon with a live unread-count badge.
/// Drop-in replacement for the plain IconButton in the AppBar.
class NotifBadge extends StatelessWidget {
  final NotificationRole role;
  final VoidCallback onTap;
  final Color iconColor;

  const NotifBadge({
    super.key,
    required this.role,
    required this.onTap,
    this.iconColor = Colors.white,
  });

  String get _roleString {
    switch (role) {
      case NotificationRole.admin:    return 'admin';
      case NotificationRole.staff:    return 'staff';
      case NotificationRole.customer: return 'customer';
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    // Stream role-targeted + personal notifications, merge, count unread
    final roleStream = FirebaseFirestore.instance
        .collection('notifications')
        .where('targetRole', isEqualTo: _roleString)
        .snapshots();

    final personalStream = uid.isEmpty
        ? const Stream<QuerySnapshot>.empty()
        : FirebaseFirestore.instance
            .collection('notifications')
            .where('targetUid', isEqualTo: uid)
            .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: roleStream,
      builder: (context, roleSnap) {
        return StreamBuilder<QuerySnapshot>(
          stream: personalStream,
          builder: (context, personalSnap) {
            // Merge both streams, deduplicate by doc ID
            final Map<String, QueryDocumentSnapshot> merged = {};
            for (final doc in roleSnap.data?.docs ?? []) merged[doc.id] = doc;
            for (final doc in personalSnap.data?.docs ?? []) merged[doc.id] = doc;

            final unread = merged.values.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              // readBy can be stored as Map<String,dynamic> OR as List (legacy/empty)
              // Handle both safely
              final rawReadBy = data['readBy'];
              bool isRead = false;
              if (rawReadBy is Map) {
                isRead = rawReadBy[uid] == true;
              } else if (rawReadBy is List) {
                isRead = rawReadBy.contains(uid);
              }
              return !isRead;
            }).length;

            return GestureDetector(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(Icons.notifications_outlined, color: iconColor, size: 24),
                    if (unread > 0)
                      Positioned(
                        top: -4, right: -4,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                          decoration: const BoxDecoration(
                            color: Color(0xFFE8001C),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            unread > 99 ? '99+' : '$unread',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ── OneSignal credentials ──
const _kOneSignalAppId  = 'c4f82ac7-5340-4e7a-877d-1d38a6f6f8ea';
const _kOneSignalApiKey = 'os_v2_app_yt4cvr2tibhhvb35du4k637i5l5mjeywytben3fd6lmzeiyhnrp6hzfi3uq77vkidwssmkrud4mdada7wp3sg2dpybuk4vrrtc7cs7y';

/// Sends a push notification via the OneSignal REST API.
/// Uses `include_aliases` with `external_id` (set via OneSignal.login(uid)).
Future<void> _sendViaOneSignal({
  required List<String> userIds,   // Firebase UIDs
  required String title,
  required String message,
  String type = 'info',
}) async {
  if (userIds.isEmpty) return;
  if (kIsWeb) {
    debugPrint('ℹ️ OneSignal push skipped on web');
    return;
  }
  try {
    final res = await http.post(
      Uri.parse('https://api.onesignal.com/notifications'),
      headers: {
        'Authorization': 'Basic $_kOneSignalApiKey',
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: jsonEncode({
        'app_id': _kOneSignalAppId,
        'include_aliases': {
          'external_id': userIds,
        },
        'target_channel': 'push',
        'headings': {'en': title},
        'contents': {'en': message},
        'data': {'type': type},
      }),
    );
    debugPrint('📤 OneSignal → ${res.statusCode}: ${res.body}');
  } catch (e) {
    debugPrint('❌ OneSignal send error: $e');
  }
}

class AppNotifications extends StatefulWidget {
  final NotificationRole role;
  const AppNotifications({super.key, required this.role});

  @override
  State<AppNotifications> createState() => _AppNotificationsState();
}

class _AppNotificationsState extends State<AppNotifications> {
  static const _red  = Color(0xFFE8001C);
  static const _blue = Color(0xFF003087);

  @override
  void initState() {
    super.initState();
    // Ensure OneSignal listeners are set up (init already done in main.dart)
    _setupListeners();
  }

  void _setupListeners() {
    if (kIsWeb) return; // OneSignal not supported on web
    OneSignal.Notifications.addForegroundWillDisplayListener((event) {
      debugPrint('🔔 Foreground: ${event.notification.title}');
      event.preventDefault(); // prevent auto-display so we show our own dialog
      _showNotificationDialog(event.notification);
    });

    OneSignal.Notifications.addClickListener((event) {
      debugPrint('👆 Tapped: ${event.notification.title}');
    });
  }

  void _showNotificationDialog(OSNotification notification) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(notification.title ?? 'Notification'),
        content: Text(notification.body ?? ''),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ── Helpers ──

  String get _roleString {
    switch (widget.role) {
      case NotificationRole.admin:    return 'admin';
      case NotificationRole.staff:    return 'staff';
      case NotificationRole.customer: return 'customer';
    }
  }

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Fetch all Firebase UIDs for a given role
  Future<List<String>> _uidsForRole(String role) async {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: role)
        .get();
    return snap.docs.map((d) => d.id).toList();
  }

  /// Write to /notifications (for in-app display) AND push via OneSignal directly.
  /// [prefKey] — if non-empty, only push to users who have that pref enabled.
  Future<void> _notify({
    required String title,
    required String message,
    required String type,
    String targetRole = '',
    String targetUid = '',
    required List<String> pushTo,  // Firebase UIDs
    String prefKey = '',           // alert pref key to gate on ('' = no gate)
  }) async {
    final db = FirebaseFirestore.instance;

    // 1. Always write to Firestore for in-app notification list
    // Include readBy map and isRead flag so unread tracking works correctly
    await db.collection('notifications').add({
      'title': title,
      'message': message,
      'type': type,
      'targetRole': targetRole,
      'targetUid': targetUid,
      'createdAt': FieldValue.serverTimestamp(),
      'readBy': <String, bool>{},   // empty map — filled as users read it
      'isRead': false,              // convenience flag for quick queries
    });

    // 2. Send email notification via Flask backend (deployed URL)
    try {
      // Build recipient list from targetRole or targetUid
      final List<String> emailUids = [];
      if (targetUid.isNotEmpty) {
        emailUids.add(targetUid);
      } else if (targetRole.isNotEmpty) {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .where('role', isEqualTo: targetRole)
            .get();
        emailUids.addAll(snap.docs.map((d) => d.id));
      }

      for (final uid in emailUids) {
        // Check emailEnabled pref before sending
        try {
          final prefDoc = await FirebaseFirestore.instance
              .collection('users').doc(uid)
              .collection('settings').doc('alerts')
              .get();
          final emailEnabled = (prefDoc.data()?['emailEnabled'] as bool?) ?? true;
          if (!emailEnabled) continue;

          final userDoc = await FirebaseFirestore.instance
              .collection('users').doc(uid).get();
          final userEmail = userDoc.data()?['email'] as String? ?? '';
          final userName  = userDoc.data()?['name']  as String? ?? '';
          if (userEmail.isEmpty) continue;

          await http.post(
            Uri.parse('https://caltex-autopro.onrender.com/api/send-alert-email'),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode({
              'to_email': userEmail,
              'to_name':  userName,
              'title':    title,
              'message':  message,
              'type':     type,
            }),
          );
          debugPrint('📧 Email sent to $userEmail');
        } catch (e) {
          debugPrint('⚠️ Email to $uid failed (non-fatal): $e');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Notification email send failed (non-fatal): $e');
    }

    // 3. Filter by pref then push via OneSignal
    final targets = prefKey.isNotEmpty
        ? await filterByPref(pushTo, prefKey)
        : pushTo;

    await _sendViaOneSignal(
      userIds: targets,
      title: title,
      message: message,
      type: type,
    );
  }

  /// Generate and send DSS alerts based on actual Firestore data
  Future<void> generateDSSAlerts() async {
    final uid = _uid;
    if (uid == null) return;

    final db  = FirebaseFirestore.instance;
    final now = DateTime.now();

    // ── Dedup guard: only generate once per calendar day ──
    final todayStr = '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';
    final markerRef = db.collection('_pmsAlertLog').doc(todayStr);
    try {
      final markerDoc = await markerRef.get();
      if (markerDoc.exists) {
        debugPrint('ℹ️ DSS alerts already generated today ($todayStr), skipping.');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Alerts already sent today.')));
        }
        return;
      }
      // Write marker immediately to prevent race conditions
      await markerRef.set({'generatedAt': FieldValue.serverTimestamp()});
    } catch (e) {
      debugPrint('⚠️ DSS marker check failed: $e — skipping to avoid duplicates');
      return;
    }

    try {
      // Get admin UIDs for push targeting
      final adminIds = await _uidsForRole('admin');

      // ── STOCK ALERTS ──
      final stockSnap     = await db.collection('stock_inventory').get();
      final issuancesSnap = await db.collection('issuances').get();

      final consumptionMap = <String, List<Map<String, dynamic>>>{};
      for (final d in issuancesSnap.docs) {
        final data    = d.data();
        final itemNum = data['itemNum'] as String? ?? '';
        final rawQty  = data['qty'] ?? data['quantity'];
        final qty     = rawQty is num
            ? rawQty.toDouble()
            : double.tryParse(rawQty?.toString() ?? '') ?? 0.0;
        final dateStr = data['date'] as String? ?? '';
        if (itemNum.isEmpty || qty <= 0) continue;
        consumptionMap.putIfAbsent(itemNum, () => []);
        consumptionMap[itemNum]!.add({'date': dateStr, 'qty': qty});
      }

      final now = DateTime.now();

      for (final doc in stockSnap.docs) {
        final data    = doc.data();
        final itemNum = (data['num'] as String?) ?? (data['itemNum'] as String?) ?? doc.id;
        final stock   = (data['stock']  as num?)?.toInt() ?? 0;
        final min     = (data['min']    as num?)?.toInt() ?? 0;
        final max     = (data['max']    as num?)?.toInt() ?? 0;
        final reorder = (data['reorder'] as num?)?.toInt() ?? 0;
        final name    = data['name'] as String? ?? itemNum;
        final uom     = data['uom'] as String? ?? '';

        final records       = consumptionMap[itemNum] ?? [];
        final totalConsumed = records.fold<double>(0.0, (s, r) => s + (r['qty'] as num).toDouble());

        DateTime? earliest;
        for (final r in records) {
          final d2 = _parseIssuanceDate(r['date'] as String? ?? '');
          if (d2 != null && (earliest == null || d2.isBefore(earliest!))) earliest = d2;
        }

        final daySpan     = earliest != null
            ? (now.difference(earliest!).inMilliseconds / 86400000).ceil().clamp(1, 999999)
            : 30;
        final dailyRate   = totalConsumed > 0 ? totalConsumed / daySpan : 0.0;
        final deficit     = (max - stock).clamp(0, 999999);
        final recommendQty = deficit > reorder ? deficit : reorder;

        if (stock == 0) {
          await _notify(
            title: '🚨 URGENT: Out of Stock',
            message: '$name is out of stock. Recommend ordering $recommendQty $uom.',
            type: 'warning',
            targetRole: 'admin',
            pushTo: adminIds,
            prefKey: 'lowStock',
          );
        } else if (stock <= min) {
          await _notify(
            title: '⚠️ Low Stock Alert',
            message: '$name is low ($stock $uom). Recommend ordering $recommendQty $uom.',
            type: 'warning',
            targetRole: 'admin',
            pushTo: adminIds,
            prefKey: 'lowStock',
          );
        }
      }

      // ── PMS ALERTS ──
      final vehiclesSnap = await db.collection('vehicles').get();
      final today        = DateTime(now.year, now.month, now.day);

      for (final vDoc in vehiclesSnap.docs) {
        final data        = vDoc.data();
        final plate       = data['plate'] as String? ?? '';
        final lastSvcDate = data['lastSvcDate'] as String? ?? '';
        final svcFreq     = int.tryParse(data['svcFreq']?.toString() ?? '');

        if (lastSvcDate.isEmpty || svcFreq == null || plate.isEmpty) continue;

        final lastDate = DateTime.tryParse(lastSvcDate);
        if (lastDate == null) continue;

        final nextDate     = DateTime(lastDate.year, lastDate.month + svcFreq, lastDate.day);
        final nextMidnight = DateTime(nextDate.year, nextDate.month, nextDate.day);
        final daysUntil    = nextMidnight.difference(today).inDays;

        // Admin PMS alerts — gated by pref
        if (daysUntil < 0) {
          await _notify(
            title: '🚨 PMS Overdue',
            message: '$plate is ${(-daysUntil)} day(s) overdue for maintenance.',
            type: 'warning',
            targetRole: 'admin',
            pushTo: adminIds,
            prefKey: 'pmsOverdue',
          );
        } else if (daysUntil == 0) {
          await _notify(
            title: '📅 PMS Due Today',
            message: '$plate is due for maintenance today.',
            type: 'warning',
            targetRole: 'admin',
            pushTo: adminIds,
            prefKey: 'pmsDueThisWeek',
          );
        } else if (daysUntil <= 7) {
          await _notify(
            title: '📅 PMS Due This Week',
            message: '$plate is due for maintenance this week ($daysUntil day(s)).',
            type: 'warning',
            targetRole: 'admin',
            pushTo: adminIds,
            prefKey: 'pmsDueThisWeek',
          );
        } else if (daysUntil <= 14) {
          await _notify(
            title: '⚠️ PMS Due Soon',
            message: '$plate is due for maintenance in $daysUntil day(s).',
            type: 'info',
            targetRole: 'admin',
            pushTo: adminIds,
            prefKey: 'pmsDueSoon',
          );
        }

        // Customer PMS alerts — gated by their own prefs
        // Try UID fields first, then fall back to name-based lookup
        String? ownerId = data['ownerId'] as String? ?? data['customerId'] as String?;
        if ((ownerId == null || ownerId.isEmpty)) {
          final ownerName = data['owner'] as String? ?? data['ownerName'] as String? ?? '';
          if (ownerName.isNotEmpty) {
            // Try exact name match
            QuerySnapshot ownerSnap = await db.collection('users')
                .where('name', isEqualTo: ownerName)
                .where('role', isEqualTo: 'customer')
                .limit(1)
                .get();
            if (ownerSnap.docs.isNotEmpty) {
              ownerId = ownerSnap.docs.first.id;
            } else {
              // Fallback: case-insensitive scan of all customers
              final allCustomers = await db.collection('users')
                  .where('role', isEqualTo: 'customer')
                  .get();
              final ownerLower = ownerName.trim().toLowerCase();
              for (final cu in allCustomers.docs) {
                final cuName = ((cu.data() as Map<String, dynamic>)['name'] as String? ?? '').trim().toLowerCase();
                if (cuName == ownerLower) {
                  ownerId = cu.id;
                  break;
                }
              }
            }
            if (ownerId != null && ownerId.isNotEmpty) {
              debugPrint('✅ Resolved owner UID for $ownerName → $ownerId');
            } else {
              debugPrint('⚠️ Could not resolve owner UID for vehicle $plate (owner: $ownerName)');
            }
          }
        }
        if (ownerId != null && ownerId.isNotEmpty) {
          final ownerDoc = await db.collection('users').doc(ownerId).get();
          if (!ownerDoc.exists) continue;

          if (daysUntil < 0) {
            await _notify(
              title: '🚨 Your PMS is Overdue',
              message: 'Your $plate is ${(-daysUntil)} day(s) overdue for maintenance.',
              type: 'warning',
              targetUid: ownerId,
              pushTo: [ownerId],
              prefKey: 'pmsOverdue',
            );
          } else if (daysUntil == 0) {
            await _notify(
              title: '📅 Your PMS is Due Today',
              message: 'Your $plate is due for maintenance today.',
              type: 'warning',
              targetUid: ownerId,
              pushTo: [ownerId],
              prefKey: 'pmsDueThisWeek',
            );
          } else if (daysUntil <= 7) {
            await _notify(
              title: '📅 Your PMS is Due This Week',
              message: 'Your $plate is due for maintenance this week ($daysUntil day(s)).',
              type: 'warning',
              targetUid: ownerId,
              pushTo: [ownerId],
              prefKey: 'pmsDueThisWeek',
            );
          } else if (daysUntil <= 14) {
            await _notify(
              title: '⚠️ Your PMS is Due Soon',
              message: 'Your $plate is due for maintenance in $daysUntil day(s).',
              type: 'info',
              targetUid: ownerId,
              pushTo: [ownerId],
              prefKey: 'pmsDueSoon',
            );
          }
        }
      }

      debugPrint('✅ DSS alerts generated and pushed');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('DSS alerts sent')),
        );
      }
    } catch (e) {
      debugPrint('❌ generateDSSAlerts error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  /// Send a push notification to a specific user
  Future<void> sendPushNotification({
    required String userId,
    required String title,
    required String body,
    String type = 'info',
  }) async {
    await _notify(
      title: title,
      message: body,
      type: type,
      targetUid: userId,
      pushTo: [userId],
    );
  }

  // ── Date parser ──

  static DateTime? _parseIssuanceDate(String s) {
    if (s.isEmpty) return null;
    final iso = DateTime.tryParse(s);
    if (iso != null) return DateTime.utc(iso.year, iso.month, iso.day);
    final parts = s.split('/');
    if (parts.length == 3) {
      final m = int.tryParse(parts[0]);
      final d = int.tryParse(parts[1]);
      final y = int.tryParse(parts[2]);
      if (m != null && d != null && y != null) return DateTime.utc(y, m, d);
    }
    const months = {
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
      'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
    };
    final m = RegExp(r'^(\w+)\s+(\d+),\s+(\d{4})$').firstMatch(s.trim());
    if (m != null) {
      final mon = months[m.group(1)!.toLowerCase().substring(0, 3)];
      final day = int.tryParse(m.group(2)!);
      final yr  = int.tryParse(m.group(3)!);
      if (mon != null && day != null && yr != null) return DateTime.utc(yr, mon, day);
    }
    return null;
  }

  // ── Firestore streams for in-app notification list ──
  // Note: no .orderBy() on the queries — sorting is done client-side after
  // merging both streams. This avoids the need for Firestore composite indexes.

  Stream<QuerySnapshot> get _stream => FirebaseFirestore.instance
      .collection('notifications')
      .where('targetRole', isEqualTo: _roleString)
      .snapshots();

  Stream<QuerySnapshot> get _personalStream {
    final uid = _uid;
    if (uid == null) return const Stream.empty();
    return FirebaseFirestore.instance
        .collection('notifications')
        .where('targetUid', isEqualTo: uid)
        .snapshots();
  }

  Future<void> _markRead(String docId) async {
    final uid = _uid;
    if (uid == null) return;
    await FirebaseFirestore.instance
        .collection('notifications')
        .doc(docId)
        .update({'readBy.$uid': true});
  }

  /// Mark as read then navigate to the relevant screen based on notification title.
  Future<void> _markReadAndNavigate(String docId, String title, String message) async {
    // Mark read first (fire-and-forget is fine here — UI updates immediately)
    _markRead(docId);

    final t = title.toLowerCase();
    final m = message.toLowerCase();

    Widget? screen;

    if (widget.role == NotificationRole.customer) {
      if (t.contains('booking') || t.contains('rescheduled') || m.contains('booking')) {
        screen = const CustomerMyBookings();
      } else if (t.contains('pms') || t.contains('service') || m.contains('pms')) {
        screen = const CustomerDashboard();
      }
    } else if (widget.role == NotificationRole.staff) {
      if (t.contains('pms') || m.contains('pms')) {
        screen = const AdminDSS(initialTab: 1); // tab 1 = PMS scheduling
      } else if (t.contains('booking') || m.contains('booking')) {
        screen = const AdminServiceBookings();
      } else if (t.contains('service') || t.contains('maintenance')) {
        screen = const AdminVehicleMaintenance();
      } else if (t.contains('receiving') || t.contains('delivery')) {
        screen = const AdminReceiving();
      }
    } else {
      // admin
      if (t.contains('pms') || m.contains('pms')) {
        screen = const AdminDSS(initialTab: 1); // tab 1 = PMS scheduling
      } else if (t.contains('stock')) {
        screen = const AdminDSS(initialTab: 0); // tab 0 = Stock replenishment
      } else if (t.contains('booking') || m.contains('booking')) {
        screen = const AdminServiceBookings();
      } else if (t.contains('service') || t.contains('maintenance')) {
        screen = const AdminVehicleMaintenance();
      } else if (t.contains('receiving') || t.contains('delivery')) {
        screen = const AdminReceiving();
      } else if (t.contains('user') || m.contains('account')) {
        screen = const AdminUsers();
      } else if (t.contains('vehicle') || m.contains('plate')) {
        screen = const AdminVehiclesList();
      }
    }

    if (screen != null && mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen!));
    }
  }

  Future<void> _markAllRead(List<QueryDocumentSnapshot> docs) async {
    final uid = _uid;
    if (uid == null) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in docs) {
      batch.update(doc.reference, {'readBy.$uid': true});
    }
    await batch.commit();
  }

  bool _isUnread(Map<String, dynamic> data) {
    final uid = _uid;
    if (uid == null) return false;
    final rawReadBy = data['readBy'];
    bool isRead = false;
    if (rawReadBy is Map) {
      isRead = rawReadBy[uid] == true;
    } else if (rawReadBy is List) {
      isRead = rawReadBy.contains(uid);
    }
    return !isRead;
  }

  Color _typeColor(String type) {
    if (type == 'warning') return Colors.orange;
    if (type == 'success') return const Color(0xFF2c7a7b);
    if (type == 'danger')  return const Color(0xFFE8001C);
    return _blue;
  }

  IconData _typeIcon(String type) {
    if (type == 'warning') return Icons.warning_amber_rounded;
    if (type == 'success') return Icons.check_circle_rounded;
    if (type == 'danger')  return Icons.error_rounded;
    return Icons.notifications_rounded;
  }

  // Map notification title keywords to specific emoji icons (matches website style)
  String _titleEmoji(String title, String type) {
    final t = title.toLowerCase();
    if (t.contains('overdue'))        return '🚨';
    if (t.contains('due this week'))  return '📅';
    if (t.contains('due soon'))       return '⚠️';
    if (t.contains('out of stock'))   return '🚨';
    if (t.contains('low stock'))      return '⚠️';
    if (t.contains('approved'))       return '✅';
    if (t.contains('registration'))   return '🆕';
    if (t.contains('maintenance'))    return '🔧';
    if (type == 'success')            return '✅';
    if (type == 'warning')            return '⚠️';
    if (type == 'danger')             return '🚨';
    return '🔔';
  }

  String _timeAgo(Timestamp? ts) {
    if (ts == null) return '';
    final diff = DateTime.now().difference(ts.toDate());
    if (diff.inSeconds < 60)  return 'Just now';
    if (diff.inMinutes < 60)  return '${diff.inMinutes} min ago';
    if (diff.inHours < 24)    return '${diff.inHours} hr ago';
    if (diff.inDays == 1)     return 'Yesterday';
    return '${diff.inDays} days ago';
  }

  // ── Selection state ──
  final Set<String> _selected = {};
  bool get _isSelecting => _selected.isNotEmpty;

  void _toggleSelect(String docId) {
    setState(() {
      if (_selected.contains(docId)) {
        _selected.remove(docId);
      } else {
        _selected.add(docId);
      }
    });
  }

  void _selectAll(List<QueryDocumentSnapshot> docs) {
    setState(() {
      _selected.addAll(docs.map((d) => d.id));
    });
  }

  void _clearSelection() {
    setState(() => _selected.clear());
  }

  Future<void> _deleteSelected() async {
    final ids = List<String>.from(_selected);
    _clearSelection();
    final batch = FirebaseFirestore.instance.batch();
    for (final id in ids) {
      batch.delete(FirebaseFirestore.instance.collection('notifications').doc(id));
    }
    await batch.commit();
  }

  Future<void> _deleteAll(List<QueryDocumentSnapshot> docs) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete All Notifications',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Text(
          'This will permanently delete all ${docs.length} notification${docs.length > 1 ? 's' : ''}. This cannot be undone.',
          style: const TextStyle(fontSize: 13, color: Color(0xFF4a5568)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF718096))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: _red),
            child: const Text('Delete All', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  Future<void> _confirmDeleteSelected() async {
    final count = _selected.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Notifications',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Text(
          'Delete $count selected notification${count > 1 ? 's' : ''}?',
          style: const TextStyle(fontSize: 13, color: Color(0xFF4a5568)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF718096))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: _red),
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed == true) await _deleteSelected();
  }

  // ── UI ──

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _stream,
      builder: (context, roleSnap) {
        return StreamBuilder<QuerySnapshot>(
          stream: _personalStream,
          builder: (context, personalSnap) {
            if (roleSnap.connectionState == ConnectionState.waiting ||
                personalSnap.connectionState == ConnectionState.waiting) {
              return Scaffold(
                backgroundColor: const Color(0xFFF7F8FA),
                appBar: AppBar(
                backgroundColor: const Color(0xFF1a202c),
                elevation: 0,
                flexibleSpace: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF1a202c), Color(0xFF2d3748), Color(0xFFE8001C)],
                      stops: [0.0, 0.55, 1.0],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
                iconTheme: const IconThemeData(color: Colors.white),
                title: const Text('Notifications',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
                body: const Center(child: CircularProgressIndicator()),
              );
            }

            final Map<String, QueryDocumentSnapshot> merged = {};
            for (final doc in roleSnap.data?.docs ?? []) merged[doc.id] = doc;
            for (final doc in personalSnap.data?.docs ?? []) merged[doc.id] = doc;

            final docs = merged.values.toList()
              ..sort((a, b) {
                final aTs = (a.data() as Map)['createdAt'] as Timestamp?;
                final bTs = (b.data() as Map)['createdAt'] as Timestamp?;
                if (aTs == null && bTs == null) return 0;
                if (aTs == null) return -1;
                if (bTs == null) return 1;
                return bTs.compareTo(aTs);
              });

            final unreadCount = docs
                .where((d) => _isUnread(d.data() as Map<String, dynamic>))
                .length;

            final allSelected = docs.isNotEmpty &&
                docs.every((d) => _selected.contains(d.id));

            return Scaffold(
              backgroundColor: const Color(0xFFF7F8FA),
              appBar: _isSelecting
                  // ── Selection mode AppBar ──
                  ? AppBar(
                      backgroundColor: const Color(0xFF1a202c),
                      elevation: 0,
                      flexibleSpace: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF1a202c), Color(0xFF2d3748), Color(0xFFE8001C)],
                            stops: [0.0, 0.55, 1.0],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                      ),
                      leading: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: _clearSelection,
                      ),
                      title: Text(
                        '${_selected.length} selected',
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      actions: [
                        // Select all / deselect all toggle
                        TextButton.icon(
                          onPressed: allSelected
                              ? _clearSelection
                              : () => _selectAll(docs),
                          icon: Icon(
                            allSelected ? Icons.deselect : Icons.select_all,
                            color: Colors.white, size: 18,
                          ),
                          label: Text(
                            allSelected ? 'Deselect All' : 'Select All',
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                        // Delete selected
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.white),
                          tooltip: 'Delete selected',
                          onPressed: _confirmDeleteSelected,
                        ),
                      ],
                    )
                  // ── Normal AppBar ──
                  : AppBar(
                      backgroundColor: const Color(0xFF1a202c),
                      elevation: 0,
                      flexibleSpace: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF1a202c), Color(0xFF2d3748), Color(0xFFE8001C)],
                            stops: [0.0, 0.55, 1.0],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                      ),
                      iconTheme: const IconThemeData(color: Colors.white),
                      title: const Text('Notifications',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      actions: [
                        if (docs.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.delete_sweep_outlined, color: Colors.white),
                            tooltip: 'Delete all',
                            onPressed: () => _deleteAll(docs),
                          ),
                      ],
                    ),
              body: docs.isEmpty
                  ? const Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.notifications_off_outlined, size: 48, color: Color(0xFFcbd5e0)),
                        SizedBox(height: 12),
                        Text('No notifications yet', style: TextStyle(color: Color(0xFF718096))),
                      ]),
                    )
                  : Column(children: [
                      // ── Toolbar row ──
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                        child: Row(children: [
                          const Icon(Icons.notifications_outlined, size: 16, color: Color(0xFF718096)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _isSelecting
                                  ? 'Long press to select • tap to toggle'
                                  : unreadCount > 0
                                      ? '$unreadCount unread notification${unreadCount > 1 ? 's' : ''}'
                                      : 'All caught up!',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF718096)),
                            ),
                          ),
                          if (!_isSelecting && unreadCount > 0)
                            TextButton(
                              onPressed: () => _markAllRead(docs),
                              style: TextButton.styleFrom(foregroundColor: _red),
                              child: const Text('Mark all read', style: TextStyle(fontSize: 12)),
                            ),
                        ]),
                      ),
                      // ── List ──
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: docs.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final doc       = docs[i];
                            final data      = doc.data() as Map<String, dynamic>;
                            final type      = data['type'] as String? ?? 'info';
                            final title     = data['title'] as String? ?? '';
                            final message   = data['message'] as String? ?? '';
                            final emoji     = _titleEmoji(title, type);
                            final isUnread  = _isUnread(data);
                            final ts        = data['createdAt'] as Timestamp?;
                            final isChecked = _selected.contains(doc.id);

                            return GestureDetector(
                              onTap: () {
                                if (_isSelecting) {
                                  _toggleSelect(doc.id);
                                } else {
                                  _markReadAndNavigate(doc.id, title, message);
                                }
                              },
                              onLongPress: () => _toggleSelect(doc.id),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: isChecked
                                      ? _red.withOpacity(0.06)
                                      : isUnread
                                          ? const Color(0xFFFFF5F5)
                                          : Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: isChecked
                                      ? Border.all(color: _red.withOpacity(0.4), width: 1.5)
                                      : Border.all(color: const Color(0xFFe2e8f0)),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(isUnread ? 0.06 : 0.03),
                                      blurRadius: isUnread ? 10 : 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // ── Emoji icon (matches website style) ──
                                    if (_isSelecting)
                                      Padding(
                                        padding: const EdgeInsets.only(right: 10, top: 2),
                                        child: AnimatedSwitcher(
                                          duration: const Duration(milliseconds: 150),
                                          child: isChecked
                                              ? Icon(Icons.check_circle, color: _red, size: 22, key: const ValueKey('checked'))
                                              : Icon(Icons.radio_button_unchecked, color: const Color(0xFFcbd5e0), size: 22, key: const ValueKey('unchecked')),
                                        ),
                                      )
                                    else
                                      Padding(
                                        padding: const EdgeInsets.only(right: 12, top: 2),
                                        child: Container(
                                          width: 36, height: 36,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF1a3560).withOpacity(0.08),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: const Icon(
                                            Icons.notifications_outlined,
                                            color: Color(0xFF1a3560),
                                            size: 20,
                                          ),
                                        ),
                                      ),
                                    // ── Text ──
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  title,
                                                  style: TextStyle(
                                                    fontWeight: isUnread ? FontWeight.w700 : FontWeight.w600,
                                                    fontSize: 13,
                                                    color: const Color(0xFF1a202c),
                                                    height: 1.3,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                _timeAgo(ts),
                                                style: const TextStyle(fontSize: 10, color: Color(0xFF718096)),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            message,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF4a5568),
                                              height: 1.4,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // ── Unread dot (right side, red) ──
                                    if (!_isSelecting && isUnread) ...[
                                      const SizedBox(width: 8),
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Container(
                                          width: 8, height: 8,
                                          decoration: const BoxDecoration(
                                            color: _red,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ]),
            );
          },
        );
      },
    );
  }
}
