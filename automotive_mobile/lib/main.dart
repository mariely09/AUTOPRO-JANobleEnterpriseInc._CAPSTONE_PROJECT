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
import 'admin_dashboard.dart';
import 'customer_dashboard.dart';
import 'background_dss.dart';
import 'sync_indicator.dart';

// ── Workmanager task name ──
const _kDSSTaskName = 'dss_background_check';
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
      cacheSizeBytes:
          Settings.CACHE_SIZE_UNLIMITED, // no size limit on local cache
    );
    debugPrint('✅ Firestore offline persistence enabled');
  }

  // ── OneSignal: initialize ONLY (skip on web for now) ──
  // Permission request happens AFTER login in login.dart
  if (!kIsWeb) {
    debugPrint('🔵 Initializing OneSignal...');
    OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
    OneSignal.initialize('48dcf379-b5b7-4692-b15c-f72779e8614d');
    debugPrint('✅ OneSignal initialized');

    // If user is already logged in (app restart), re-link UID with OneSignal
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      OneSignal.login(user.uid);
      debugPrint('✅ OneSignal auto-login with UID: ${user.uid}');

      // Request permission on app restart if already logged in
      final isOptedIn = OneSignal.User.pushSubscription.optedIn ?? false;
      if (!isOptedIn) {
        final granted = await OneSignal.Notifications.requestPermission(true);
        if (granted) {
          await OneSignal.User.pushSubscription.optIn();
          await Future.delayed(const Duration(seconds: 2));
        }
        debugPrint(
          granted
              ? '✅ Push re-opted in on restart'
              : '❌ Push permission denied on restart',
        );
      }

      // Save/refresh subscription ID — use observer as primary, immediate check as fast path
      Future(() async {
        Future<void> persistSubId(String subId) async {
          try {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .set({'oneSignalId': subId}, SetOptions(merge: true));
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
        debugPrint(
          '⏳ Waiting for OneSignal to assign subscription ID on restart...',
        );
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
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
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
  // Start the connectivity ping loop
  SyncStatusNotifier.instance.init();
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
      home: const _AuthGate(),
      routes: {
        '/welcome': (_) => const WelcomeScreen(),
        '/login': (_) => const LoginScreen(),
        '/staff': (_) => const StaffDashboard(),
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Auth Gate — checks Firebase Auth state on app start.
// • Logged in  → fetch role from Firestore → go directly to dashboard.
// • Not logged in → show WelcomeScreen (normal login flow).
// ═══════════════════════════════════════════════════════════════════════════
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  @override
  void initState() {
    super.initState();
    // Wait for the first frame so Navigator context is fully ready before
    // any pushReplacement call — avoids the black screen on cold start.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAuth());
  }

  Future<void> _navigate(Widget screen) async {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => screen,
        // Instant transition — no fade/slide so it feels like a native splash.
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  Future<void> _checkAuth() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      // Not logged in — show welcome screen.
      await _navigate(const WelcomeScreen());
      return;
    }

    // Already authenticated — fetch role from Firestore (uses cache when offline).
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!doc.exists) {
        await FirebaseAuth.instance.signOut();
        await _navigate(const WelcomeScreen());
        return;
      }

      final data = doc.data()!;
      final role = (data['role'] as String?) ?? '';
      final status = ((data['status'] as String?) ?? 'active').toLowerCase();

      // Block inactive/pending accounts from auto-login.
      if (status == 'inactive' || status == 'pending') {
        await FirebaseAuth.instance.signOut();
        await _navigate(const WelcomeScreen());
        return;
      }

      // Navigate directly to the correct dashboard — no login screen needed.
      switch (role) {
        case 'admin':
          await _navigate(const AdminDashboard());
          break;
        case 'staff':
          await _navigate(const StaffDashboard());
          break;
        case 'customer':
          await _navigate(const CustomerDashboard());
          break;
        default:
          await FirebaseAuth.instance.signOut();
          await _navigate(const WelcomeScreen());
      }
    } catch (e) {
      // Firestore unavailable (offline + no cache yet) — fall back to welcome.
      debugPrint('⚠️ AuthGate error: $e');
      await _navigate(const WelcomeScreen());
    }
  }

  @override
  Widget build(BuildContext context) {
    // Splash that matches the WelcomeScreen gradient so the transition is seamless.
    return const Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF004B5F), Color(0xFFEE152A)],
            stops: [0.0, 1.0],
          ),
        ),
        child: Center(
          child: CircularProgressIndicator(
            color: Colors.white,
            strokeWidth: 2.5,
          ),
        ),
      ),
    );
  }
}
