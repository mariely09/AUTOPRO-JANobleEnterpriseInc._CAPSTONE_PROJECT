import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:workmanager/workmanager.dart';
import 'firebase_options.dart';
import 'login.dart';
import 'welcome_screen.dart';
import 'staff_dashboard.dart';
import 'background_dss.dart';

// ── Workmanager task name ──
const _kDSSTaskName   = 'dss_background_check';
const _kDSSTaskUnique = 'dss_periodic';

/// Top-level callback required by workmanager.
/// Runs in a separate isolate — must be a top-level function.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName == _kDSSTaskName) {
      return runBackgroundDSSCheck();
    }
    return true;
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // ── Firestore offline persistence ──
  // Writes made while offline are queued locally and automatically synced
  // to Firestore once internet is restored. Works across app restarts.
  if (!kIsWeb) {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED, // no size limit on local cache
    );
    debugPrint('✅ Firestore offline persistence enabled');
  }

  // ── OneSignal: initialize and request permission (skip on web for now) ──
  if (!kIsWeb) {
    OneSignal.initialize('c4f82ac7-5340-4e7a-877d-1d38a6f6f8ea');
    await OneSignal.Notifications.requestPermission(true);

    // If user is already logged in (app restart), re-link UID with OneSignal
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      OneSignal.login(user.uid);
      debugPrint('✅ OneSignal auto-login with UID: ${user.uid}');

      // Ensure push is opted in (re-request permission if previously denied)
      final isOptedIn = OneSignal.User.pushSubscription.optedIn ?? false;
      if (!isOptedIn) {
        final granted = await OneSignal.Notifications.requestPermission(true);
        if (granted) await OneSignal.User.pushSubscription.optIn();
        debugPrint(granted ? '✅ Push re-opted in on restart' : '❌ Push permission denied on restart');
      }

      // Save/refresh subscription ID — use observer as primary, immediate check as fast path
      Future(() async {
        Future<void> persistSubId(String subId) async {
          try {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .update({'oneSignalId': subId});
            debugPrint('✅ OneSignal subscription ID saved on restart: $subId');
          } catch (e) {
            debugPrint('⚠️ Could not save OneSignal ID on restart: $e');
          }
        }

        // Immediate check — ID already assigned (returning user)
        final existing = OneSignal.User.pushSubscription.id;
        if (existing != null && existing.isNotEmpty) {
          await persistSubId(existing);
          return;
        }

        // Wait for OneSignal to assign it (first install or token expired)
        debugPrint('⏳ Waiting for OneSignal to assign subscription ID on restart...');
        OneSignal.User.pushSubscription.addObserver((state) {
          final newId = state.current.id;
          if (newId == null || newId.isEmpty) return;
          persistSubId(newId);
        });
      });

      // Watch for subscription ID changes (e.g. after token rotation)
      OneSignal.User.pushSubscription.addObserver((state) {
        final newId = state.current.id;
        if (newId == null || newId.isEmpty) return;
        FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({'oneSignalId': newId})
            .then((_) => debugPrint('🔄 OneSignal sub ID updated: $newId'))
            .catchError((e) => debugPrint('⚠️ Sub ID update failed: $e'));
      });
    }

    // ── Workmanager: register background DSS check (mobile only) ──
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );
    await Workmanager().registerPeriodicTask(
      _kDSSTaskUnique,
      _kDSSTaskName,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
    debugPrint('✅ Background DSS task registered (every 15 min)');
  } else {
    debugPrint('ℹ️ Running on web — OneSignal and Workmanager disabled');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AutoPro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE8001C)),
        fontFamily: 'Roboto',
      ),
      home: const WelcomeScreen(),
      routes: {
        '/welcome': (_) => const WelcomeScreen(),
        '/login': (_) => const LoginScreen(),
        '/staff': (_) => const StaffDashboard(),
      },
    );
  }
}
