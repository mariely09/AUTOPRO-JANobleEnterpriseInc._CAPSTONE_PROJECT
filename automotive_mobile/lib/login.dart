import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'google_sign_in.dart';
import 'staff_dashboard.dart';
import 'customer_dashboard.dart';
import 'admin_dashboard.dart';
import 'forgot_password.dart';
import 'register.dart';
import 'change_password.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _passVisible = false;
  bool _loading = false;
  bool _googleLoading = false;
  bool _showPasswordToggle = false;
  static const _red = Color(0xFFE8001C);

  // ── Login attempt rate limiting ──
  int _loginAttempts = 0;
  DateTime? _lockoutUntil;
  static const _maxAttempts = 5;
  static const _lockoutDuration = Duration(seconds: 60);

  // ── Remember me ──
  bool _rememberMe = false;

  @override
  void initState() {
    super.initState();
    _loadRememberedEmail();
  }

  Future<void> _loadRememberedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('_rememberedEmail') ?? '';
    if (saved.isNotEmpty && mounted) {
      setState(() {
        _emailCtrl.text = saved;
        _rememberMe = true;
      });
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    // Check lockout
    if (_lockoutUntil != null && DateTime.now().isBefore(_lockoutUntil!)) {
      final remaining = _lockoutUntil!.difference(DateTime.now()).inSeconds;
      _showError('Too many failed attempts. Please try again in $remaining seconds.');
      return;
    }

    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showError('Please enter email and password.');
      return;
    }

    // Validate email format before hitting Firebase
    final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    if (!emailRegex.hasMatch(email)) {
      _showError('Please enter a valid email address.');
      return;
    }

    setState(() => _loading = true);
    try {
      final cred = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);

      final uid = cred.user!.uid;

      // Try UID-keyed doc first (new accounts), fall back to email query (legacy accounts)
      DocumentSnapshot? doc;
      final uidDoc = await FirebaseFirestore.instance
          .collection('users').doc(uid).get();

      if (uidDoc.exists) {
        doc = uidDoc;
      } else {
        // Legacy: doc was created with auto-ID, look up by email
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: email)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) {
          doc = snap.docs.first;
          // Migrate: re-save under the correct UID so future logins are fast
          final data = snap.docs.first.data() as Map<String, dynamic>;
          await FirebaseFirestore.instance
              .collection('users').doc(uid).set(data);
        }
      }

      if (doc == null || !doc.exists) {
        await FirebaseAuth.instance.signOut();
        _showError('Account not found. Please contact the administrator.');
        return;
      }

      final data = doc.data() as Map<String, dynamic>;
      final role = data['role'] as String? ?? '';
      final status = ((data['status'] as String?) ?? 'active').toLowerCase();

      // Block inactive users
      if (status == 'inactive') {
        await FirebaseAuth.instance.signOut();
        _showError('Your account has been deactivated. Please contact the administrator.');
        return;
      }

      // Block pending users
      if (status == 'pending') {
        await FirebaseAuth.instance.signOut();
        _showError('Your account is pending admin approval. You will be notified by email once approved.');
        return;
      }

      if (!mounted) return;
      // Register this device with OneSignal using Firebase UID
      if (!kIsWeb) {
        OneSignal.login(uid);
        debugPrint('✅ OneSignal login: $uid');
        _saveOneSignalId(uid);
      }

      // Check first-login flag — force password change before entering app
      if (data['mustChangePassword'] == true) {
        _loginAttempts = 0;
        await _saveRememberMe();
        Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => ChangePasswordScreen(role: role, firstLogin: true, tempPassword: _passwordCtrl.text)));
        return;
      }

      _loginAttempts = 0;
      await _saveRememberMe();
      switch (role) {
        case 'admin':
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AdminDashboard()));
          break;
        case 'staff':
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const StaffDashboard()));
          break;
        case 'customer':
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const CustomerDashboard()));
          break;
        default:
          await FirebaseAuth.instance.signOut();
          _showError('Unknown account role.');
      }
    } on FirebaseAuthException catch (e) {
      _loginAttempts++;
      if (_loginAttempts >= _maxAttempts) {
        _lockoutUntil = DateTime.now().add(_lockoutDuration);
        _showError('Account locked for ${_lockoutDuration.inSeconds} seconds due to too many failed attempts.');
      } else {
        final msg = (e.code == 'user-not-found' ||
                e.code == 'wrong-password' ||
                e.code == 'invalid-credential')
            ? 'Invalid email or password.'
            : e.code == 'invalid-email'
                ? 'Please enter a valid email address.'
                : e.message ?? 'Login failed.';
        _showError(msg);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _googleLoading = true);
    try {
      final role = await GoogleSignInHelper.signInWithGoogle(context);
      
      if (role == null) {
        // User cancelled the sign-in
        if (mounted) setState(() => _googleLoading = false);
        return;
      }

      if (!mounted) return;

      // Register this device with OneSignal using Firebase UID
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && !kIsWeb) {
        OneSignal.login(uid);
        debugPrint('✅ OneSignal login (Google): $uid');
        _saveOneSignalId(uid);
      }

      // Check first-login flag for Google sign-in users too
      if (uid != null) {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        if (userDoc.exists && userDoc.data()?['mustChangePassword'] == true) {
          if (!mounted) return;
          Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => ChangePasswordScreen(role: role.toLowerCase(), firstLogin: true)));
          return;
        }
      }

      // Navigate based on role
      if (!mounted) return;
      switch (role.toLowerCase()) {
        case 'admin':
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AdminDashboard()));
          break;
        case 'staff':
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const StaffDashboard()));
          break;
        default:
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const CustomerDashboard()));
      }
    } catch (e) {
      debugPrint('Google Sign-In error: $e');
      
      String errorMsg;
      final errStr = e.toString();
      
      if (errStr.contains('inactive')) {
        errorMsg = 'Your account has been deactivated. Please contact the administrator.';
      } else if (errStr.contains('pending')) {
        errorMsg = 'Your account is pending admin approval. You will be notified by email once approved.';
      } else if (errStr.contains('not found') || errStr.contains('not found')) {
        errorMsg = 'User account not found. Please contact the administrator to register your account.';
      } else if (errStr.contains('network_error') || errStr.contains('NetworkError')) {
        errorMsg = 'Network error. Please check your internet connection.';
      } else if (errStr.contains('sign_in_canceled') || errStr.contains('canceled')) {
        // User cancelled — don't show error
        if (mounted) setState(() => _googleLoading = false);
        return;
      } else if (errStr.contains('PlatformException')) {
        // Show actual platform error for debugging
        errorMsg = 'Google Sign-In configuration error. Please ensure SHA-1 is configured in Firebase.';
        debugPrint('⚠️ PLATFORM ERROR DETAIL: $errStr');
      } else {
        // Show actual error message for debugging
        errorMsg = errStr.contains('Exception:')
            ? errStr.split('Exception:').last.trim()
            : 'Sign-in failed: $errStr';
      }
      
      _showError(errorMsg);
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent));
  }

  /// Saves the OneSignal subscription (player) ID to Firestore under users/{uid}.
  /// This lets us target this specific device by subscription ID instead of
  /// external user ID (which requires a paid OneSignal plan).
  Future<void> _saveOneSignalId(String uid) async {
    try {
      // Give OneSignal a moment to register the subscription after login()
      await Future.delayed(const Duration(seconds: 2));
      final subId = OneSignal.User.pushSubscription.id;
      if (subId == null || subId.isEmpty) {
        debugPrint('⚠️ OneSignal subscription ID not available yet');
        return;
      }
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'oneSignalId': subId,
      });
      debugPrint('✅ OneSignal subscription ID saved: $subId');
    } catch (e) {
      debugPrint('⚠️ Could not save OneSignal ID: $e');
    }
  }

  void _showForgotPassword() {
    Navigator.push(context,
      MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()));
  }

  Future<void> _saveRememberMe() async {
    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setString('_rememberedEmail', _emailCtrl.text.trim());
    } else {
      await prefs.remove('_rememberedEmail');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(children: [
            const SizedBox(height: 40),
            // ── Login form ──
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Center(child: Text('Login',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1a202c)))),
                const SizedBox(height: 4),
                const Center(child: Text('Sign in to your account',
                  style: TextStyle(fontSize: 13, color: Color(0xFF718096)))),
                const SizedBox(height: 28),
                // Email
                const Text('Email Address', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF4a5568))),
                const SizedBox(height: 6),
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(fontSize: 14, color: Color(0xFF1a202c)),
                  decoration: _inputDecoration('Enter your email', Icons.person_outline),
                ),
                const SizedBox(height: 16),
                // Password
                const Text('Password', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF4a5568))),
                const SizedBox(height: 6),
                TextField(
                  controller: _passwordCtrl,
                  obscureText: !_passVisible,
                  style: const TextStyle(fontSize: 14, color: Color(0xFF1a202c)),
                  onSubmitted: (_) => _handleLogin(),
                  onChanged: (_) => setState(() => _showPasswordToggle = _passwordCtrl.text.isNotEmpty),
                  decoration: _inputDecoration('Enter your password', Icons.lock_outline,
                    suffix: _showPasswordToggle
                        ? IconButton(
                            icon: Icon(_passVisible ? Icons.visibility : Icons.visibility_off, color: const Color(0xFF718096)),
                            onPressed: () => setState(() => _passVisible = !_passVisible),
                          )
                        : null),
                ),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  GestureDetector(
                    onTap: () => setState(() => _rememberMe = !_rememberMe),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(
                        width: 18, height: 18,
                        child: Checkbox(
                          value: _rememberMe,
                          onChanged: (v) => setState(() => _rememberMe = v ?? false),
                          activeColor: _red,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text('Remember me', style: TextStyle(fontSize: 12, color: Color(0xFF4a5568))),
                    ]),
                  ),
                  TextButton(
                    onPressed: _loading ? null : _showForgotPassword,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Forgot Password?',
                      style: TextStyle(fontSize: 12, color: Color(0xFF718096))),
                  ),
                ]),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _handleLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      elevation: 4,
                    ),
                    child: _loading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Sign In', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  const Expanded(child: Divider(color: Color(0xFFe2e8f0))),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('or', style: TextStyle(fontSize: 13, color: Color(0xFF718096))),
                  ),
                  const Expanded(child: Divider(color: Color(0xFFe2e8f0))),
                ]),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _googleLoading ? null : _handleGoogleSignIn,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      side: const BorderSide(color: Color(0xFFe2e8f0)),
                      backgroundColor: Colors.white,
                    ),
                    child: _googleLoading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Color(0xFF1a202c), strokeWidth: 2))
                        : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            _GoogleLogo(size: 20),
                            const SizedBox(width: 10),
                            const Text('Continue with Google',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1a202c))),
                          ]),
                  ),
                ),
                const SizedBox(height: 20),
                // ── Sign Up link ──
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text("Don't have an account? ",
                    style: TextStyle(fontSize: 13, color: Color(0xFF718096))),
                  GestureDetector(
                    onTap: _loading ? null : () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const RegisterScreen()),
                    ),
                    child: const Text('Sign Up',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _red,
                      )),
                  ),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, IconData icon, {Widget? suffix}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFFa0aec0), fontSize: 14),
      prefixIcon: Icon(icon, color: const Color(0xFF718096), size: 20),
      suffixIcon: suffix,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFe2e8f0))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFe2e8f0))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _red, width: 1.5)),
      filled: true,
      fillColor: const Color(0xFFF7F8FA),
    );
  }
}

class _GoogleLogo extends StatelessWidget {
  final double size;
  const _GoogleLogo({this.size = 20});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size, height: size,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;

    // Draw colored arcs (blue, red, yellow, green)
    final segments = [
      // [startAngle, sweepAngle, color]
      [-0.52, 1.57, const Color(0xFF4285F4)],  // blue (top-right)
      [1.05,  1.57, const Color(0xFF34A853)],  // green (bottom-right)
      [2.62,  0.79, const Color(0xFFFBBC05)],  // yellow (bottom-left)
      [3.41,  1.57, const Color(0xFFEA4335)],  // red (top-left)
    ];

    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.22
      ..strokeCap = StrokeCap.butt;

    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.72);

    for (final seg in segments) {
      strokePaint.color = seg[2] as Color;
      canvas.drawArc(rect, seg[0] as double, seg[1] as double, false, strokePaint);
    }

    // White cutout for the "G" bar (right side horizontal bar)
    final barPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTWH(cx, cy - size.height * 0.11, r * 0.72, size.height * 0.22),
      barPaint,
    );

    // Blue fill for the bar
    final bluePaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTWH(cx, cy - size.height * 0.11, r * 0.68, size.height * 0.22),
      bluePaint,
    );
  }

  @override
  bool shouldRepaint(_) => false;
}
