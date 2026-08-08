/// background_dss.dart
///
/// Runs entirely in a background isolate (via workmanager).
/// NO Flutter widgets, NO BuildContext — only Dart + Firebase + HTTP.
///
/// Called by workmanager every ~15 minutes even when the app is closed/killed.
/// Respects each user's alert preferences from users/{uid}/settings/alerts.
/// Respects inAppEnabled / emailEnabled channel preferences.

import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'firebase_options.dart';

// ── OneSignal credentials ──
const _kOneSignalAppId  = 'c4f82ac7-5340-4e7a-877d-1d38a6f6f8ea';
const _kOneSignalApiKey =
    'os_v7_app_yt4cvr2f1hkhvh5ldu4k637i51snjeyuythen3fd61ae1yhnprpy6kbxvn9kjd1pqdhygsqmlrouas4kfuydft32nkgj5flbra3oo5q';

// ── Flask server base URL (email relay) ───────────────────────────────────
// Override with FLASK_BASE_URL env if needed; default matches local dev + prod.
const _kFlaskBaseUrl = 'https://caltex-autopro.onrender.com'; // or http://localhost:5001

@pragma('vm:entry-point')
void backgroundDSSCallback() {}

/// The actual work. Called by workmanager's executeTask callback in main.dart.
Future<bool> runBackgroundDSSCheck() async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('⏭ Background DSS: no user signed in, skipping');
      return true;
    }

    final db  = FirebaseFirestore.instance;
    final now = DateTime.now();

    // ── Deduplication: once per calendar day ──
    final todayKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final sentinelRef  = db.collection('dss_alert_log').doc('bg_$todayKey');
    final sentinelSnap = await sentinelRef.get();
    if (sentinelSnap.exists) {
      debugPrint('⏭ Background DSS: already ran today ($todayKey), skipping');
      return true;
    }
    await sentinelRef.set({'sentAt': FieldValue.serverTimestamp()});

    // ── Get all admin UIDs ──
    final adminSnap = await db.collection('users').where('role', isEqualTo: 'admin').get();
    final adminIds  = adminSnap.docs.map((d) => d.id).toList();
    if (adminIds.isEmpty) {
      debugPrint('⏭ Background DSS: no admin users found');
      return true;
    }

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

      DateTime? earliest;
      for (final r in records) {
        final d2 = _parseDate(r['date'] as String? ?? '');
        if (d2 != null && (earliest == null || d2.isBefore(earliest!))) earliest = d2;
      }

      final deficit      = (max - stock).clamp(0, 999999);
      final recommendQty = deficit > reorder ? deficit : reorder;

      if (stock == 0) {
        final targets = await _filterByPref(db, adminIds, 'lowStock');
        await _sendAlert(
          db: db, targets: targets,
          title: '🚨 URGENT: Out of Stock',
          message: '$name is out of stock. Recommend ordering $recommendQty $uom.',
          type: 'warning', targetRole: 'admin',
        );
      } else if (stock <= min) {
        final targets = await _filterByPref(db, adminIds, 'lowStock');
        await _sendAlert(
          db: db, targets: targets,
          title: '⚠️ Low Stock Alert',
          message: '$name is low ($stock $uom). Recommend ordering $recommendQty $uom.',
          type: 'warning', targetRole: 'admin',
        );
      }
    }

    // ── PMS ALERTS ──
    final vehiclesSnap  = await db.collection('vehicles').get();
    final todayMidnight = DateTime(now.year, now.month, now.day);

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
      final daysUntil    = nextMidnight.difference(todayMidnight).inDays;

      // ── Admin PMS alerts ──
      if (daysUntil < 0) {
        final targets = await _filterByPref(db, adminIds, 'pmsOverdue');
        await _sendAlert(
          db: db, targets: targets,
          title: '🚨 PMS Overdue',
          message: '$plate is ${(-daysUntil)} day(s) overdue for maintenance.',
          type: 'warning', targetRole: 'admin',
        );
      } else if (daysUntil == 0) {
        final targets = await _filterByPref(db, adminIds, 'pmsDueToday');
        await _sendAlert(
          db: db, targets: targets,
          title: '🔔 PMS Due Today',
          message: '$plate is due for maintenance today.',
          type: 'warning', targetRole: 'admin',
        );
      } else if (daysUntil <= 7) {
        final targets = await _filterByPref(db, adminIds, 'pmsDueThisWeek');
        await _sendAlert(
          db: db, targets: targets,
          title: '📅 PMS Due This Week',
          message: '$plate is due for maintenance this week ($daysUntil day(s)).',
          type: 'warning', targetRole: 'admin',
        );
      } else if (daysUntil <= 14) {
        final targets = await _filterByPref(db, adminIds, 'pmsDueSoon');
        await _sendAlert(
          db: db, targets: targets,
          title: '⚠️ PMS Due Soon',
          message: '$plate is due for maintenance in $daysUntil day(s).',
          type: 'info', targetRole: 'admin',
        );
      }

      // ── Customer PMS alerts ──
      final ownerId = data['ownerId'] as String? ?? data['customerId'] as String?;
      if (ownerId != null && ownerId.isNotEmpty) {
        if (daysUntil < 0) {
          final targets = await _filterByPref(db, [ownerId], 'pmsOverdue');
          await _sendAlert(
            db: db, targets: targets,
            title: '🚨 Your PMS is Overdue',
            message: 'Your $plate is ${(-daysUntil)} day(s) overdue for maintenance.',
            type: 'warning', targetRole: '', targetUid: ownerId,
          );
        } else if (daysUntil == 0) {
          final targets = await _filterByPref(db, [ownerId], 'pmsDueToday');
          await _sendAlert(
            db: db, targets: targets,
            title: '🔔 Your PMS is Due Today',
            message: 'Your $plate is due for maintenance today.',
            type: 'warning', targetRole: '', targetUid: ownerId,
          );
        } else if (daysUntil <= 7) {
          final targets = await _filterByPref(db, [ownerId], 'pmsDueThisWeek');
          await _sendAlert(
            db: db, targets: targets,
            title: '📅 Your PMS is Due This Week',
            message: 'Your $plate is due for maintenance this week ($daysUntil day(s)).',
            type: 'warning', targetRole: '', targetUid: ownerId,
          );
        } else if (daysUntil <= 14) {
          final targets = await _filterByPref(db, [ownerId], 'pmsDueSoon');
          await _sendAlert(
            db: db, targets: targets,
            title: '⚠️ Your PMS is Due Soon',
            message: 'Your $plate is due for maintenance in $daysUntil day(s).',
            type: 'info', targetRole: '', targetUid: ownerId,
          );
        }
      }
    }

    // ── BOOKING ALERTS ──
    await _runBookingAlerts(db, adminIds, now);

    debugPrint('✅ Background DSS check complete');
    return true;
  } catch (e) {
    debugPrint('❌ Background DSS error: $e');
    return false;
  }
}

/// Checks service_bookings for events that need push notifications:
///  - New bookings  → notify admin & staff
///  - Cancellations → notify admin & staff
///  - Confirmation  → notify customer
///  - Reminder (1 day before) → notify customer
///  - Status change → notify customer
Future<void> _runBookingAlerts(
  FirebaseFirestore db,
  List<String> adminIds,
  DateTime now,
) async {
  final todayMidnight   = DateTime(now.year, now.month, now.day);
  final tomorrowMidnight = todayMidnight.add(const Duration(days: 1));
  final tomorrowStr     =
      '${tomorrowMidnight.year}-${tomorrowMidnight.month.toString().padLeft(2, '0')}-${tomorrowMidnight.day.toString().padLeft(2, '0')}';

  // Already-notified log key — per-day dedup
  final dayKey =
      '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

  // Get staff UIDs for booking notifications
  final staffSnap = await db.collection('users').where('role', isEqualTo: 'staff').get();
  final staffIds  = staffSnap.docs.map((d) => d.id).toList();
  final staffAndAdminIds = {...staffIds, ...adminIds}.toList();

  final bookingsSnap = await db.collection('service_bookings').get();

  for (final bDoc in bookingsSnap.docs) {
    final data   = bDoc.data();
    final bId    = bDoc.id;
    final plate  = data['plate'] as String? ?? '';
    final status = (data['status'] as String? ?? '').toLowerCase();
    final prefDate = data['preferredDate'] as String? ?? '';
    final customerId = data['customerId'] as String? ?? data['userId'] as String? ?? '';

    // ── New booking request (Pending) → admin & staff ──
    if (status == 'pending') {
      final logKey = 'booking_new_${bId}_$dayKey';
      final alreadySent = await _alreadyLogged(db, logKey);
      if (!alreadySent) {
        final targets = await _filterByPref(db, staffAndAdminIds, 'newBookingRequest');
        await _sendAlert(
          db: db, targets: targets,
          title: '📋 New Booking Request',
          message: 'New service booking for $plate is awaiting confirmation.',
          type: 'info', targetRole: 'admin',
        );
        await _logSent(db, logKey);
      }
    }

    // ── Booking cancelled → admin & staff ──
    if (status == 'cancelled') {
      final logKey = 'booking_cancel_${bId}_$dayKey';
      final alreadySent = await _alreadyLogged(db, logKey);
      if (!alreadySent) {
        final targets = await _filterByPref(db, staffAndAdminIds, 'bookingCancellation');
        await _sendAlert(
          db: db, targets: targets,
          title: '❌ Booking Cancelled',
          message: 'Service booking for $plate has been cancelled.',
          type: 'warning', targetRole: 'admin',
        );
        await _logSent(db, logKey);
      }
    }

    if (customerId.isEmpty) continue;

    // ── Booking confirmed → customer ──
    if (status == 'confirmed' || status == 'approved') {
      final logKey = 'booking_confirmed_${bId}';
      final alreadySent = await _alreadyLogged(db, logKey);
      if (!alreadySent) {
        final targets = await _filterByPref(db, [customerId], 'bookingConfirmed');
        await _sendAlert(
          db: db, targets: targets,
          title: '✅ Booking Confirmed',
          message: 'Your service booking for $plate has been confirmed.',
          type: 'success', targetRole: '', targetUid: customerId,
        );
        await _logSent(db, logKey);
      }
    }

    // ── Booking reminder (1 day before) → customer ──
    if (prefDate.isNotEmpty && prefDate.startsWith(tomorrowStr)) {
      final logKey = 'booking_reminder_${bId}_$dayKey';
      final alreadySent = await _alreadyLogged(db, logKey);
      if (!alreadySent) {
        final targets = await _filterByPref(db, [customerId], 'bookingReminder');
        await _sendAlert(
          db: db, targets: targets,
          title: '🔔 Booking Reminder',
          message: 'Your service for $plate is scheduled for tomorrow.',
          type: 'info', targetRole: '', targetUid: customerId,
        );
        await _logSent(db, logKey);
      }
    }

    // ── Booking status change → customer (any status update except pending) ──
    if (status != 'pending' && status != 'cancelled') {
      final logKey = 'booking_status_${bId}_$status';
      final alreadySent = await _alreadyLogged(db, logKey);
      if (!alreadySent) {
        final displayStatus = status[0].toUpperCase() + status.substring(1);
        final targets = await _filterByPref(db, [customerId], 'bookingStatusChange');
        await _sendAlert(
          db: db, targets: targets,
          title: '🔄 Booking Status Updated',
          message: 'Your booking for $plate is now: $displayStatus.',
          type: 'info', targetRole: '', targetUid: customerId,
        );
        await _logSent(db, logKey);
      }
    }
  }
}

// ── Deduplication helpers ────────────────────────────────────────────────────

Future<bool> _alreadyLogged(FirebaseFirestore db, String key) async {
  try {
    final doc = await db.collection('dss_alert_log').doc(key).get();
    return doc.exists;
  } catch (_) {
    return false;
  }
}

Future<void> _logSent(FirebaseFirestore db, String key) async {
  try {
    await db.collection('dss_alert_log').doc(key)
        .set({'sentAt': FieldValue.serverTimestamp()});
  } catch (_) {}
}

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Filters UIDs into two lists:
///  - pushTargets : users with inAppEnabled = true AND the specific alert pref
///  - emailTargets: users with emailEnabled = true AND the specific alert pref
/// Defaults to true (included) if the pref doc doesn't exist.
Future<({List<String> push, List<String> email})> _filterByPref(
  FirebaseFirestore db,
  List<String> uids,
  String prefKey,
) async {
  if (uids.isEmpty) return (push: [], email: []);
  final pushList  = <String>[];
  final emailList = <String>[];
  for (final uid in uids) {
    try {
      final doc = await db
          .collection('users').doc(uid)
          .collection('settings').doc('alerts')
          .get();
      final prefs        = doc.data() ?? {};
      final alertEnabled = prefs[prefKey]        as bool? ?? true;
      final inApp        = prefs['inAppEnabled']  as bool? ?? true;
      final email        = prefs['emailEnabled']  as bool? ?? true;
      if (alertEnabled && inApp)  pushList.add(uid);
      if (alertEnabled && email)  emailList.add(uid);
    } catch (_) {
      // include on error — don't silently drop
      pushList.add(uid);
      emailList.add(uid);
    }
  }
  return (push: pushList, email: emailList);
}

/// Writes to Firestore (in-app display) AND pushes via OneSignal.
/// Only targets users who passed _filterByPref (inAppEnabled + alert pref).
Future<void> _sendAlert({
  required FirebaseFirestore db,
  required ({List<String> push, List<String> email}) targets,
  required String title,
  required String message,
  required String type,
  String targetRole = '',
  String targetUid  = '',
}) async {
  final allUids = {...targets.push, ...targets.email};
  if (allUids.isEmpty) return;

  // ── 1. Write to Firestore (in-app notification list) ──
  await db.collection('notifications').add({
    'title':      title,
    'message':    message,
    'type':       type,
    'targetRole': targetRole,
    'targetUid':  targetUid,
    'readBy':     [],
    'createdAt':  FieldValue.serverTimestamp(),
  });

  // ── 2. Push notification via OneSignal ──
  if (targets.push.isNotEmpty) {
    try {
      final res = await http.post(
        Uri.parse('https://api.onesignal.com/notifications'),
        headers: {
          'Authorization': 'Basic $_kOneSignalApiKey',
          'Content-Type': 'application/json; charset=utf-8',
        },
        body: jsonEncode({
          'app_id': _kOneSignalAppId,
          'include_aliases': {'external_id': targets.push},
          'target_channel': 'push',
          'headings': {'en': title},
          'contents': {'en': message},
          'data':     {'type': type},
          'android_channel_id': 'autopro_alerts',
          'ios_sound': 'default',
        }),
      );
      debugPrint('📤 OneSignal push → ${res.statusCode}: ${res.body}');
    } catch (e) {
      debugPrint('❌ OneSignal push error: $e');
    }
  }

  // ── 3. Email notification via Flask SMTP relay ──
  if (targets.email.isNotEmpty) {
    for (final uid in targets.email) {
      try {
        // Look up user's email address from Firestore
        final userDoc = await db.collection('users').doc(uid).get();
        final userEmail = userDoc.data()?['email'] as String? ?? '';
        final userName  = userDoc.data()?['name']  as String? ?? '';
        if (userEmail.isEmpty) continue;

        final emailRes = await http.post(
          Uri.parse('$_kFlaskBaseUrl/api/send-alert-email'),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
          body: jsonEncode({
            'to_email': userEmail,
            'to_name':  userName,
            'title':    title,
            'message':  message,
            'type':     type,
          }),
        );
        debugPrint('📧 Alert email → $userEmail: ${emailRes.statusCode}');
      } catch (e) {
        debugPrint('❌ Alert email error for $uid: $e');
      }
    }
  }
}

DateTime? _parseDate(String s) {
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
