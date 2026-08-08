import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'admin_rag_ai.dart';
import 'customer_smart_ai.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

// ── EmailJS config (same as forgot_password.dart) ─────────────────────────
const _kEmailjsServiceId  = 'service_i906b4o';
const _kEmailjsTemplateId = 'template_6kkir1s';
const _kEmailjsPublicKey  = 'DqRrjCkUnf9w2L_sv';

class GoogleSignInHelper {
  static final _googleSignIn = GoogleSignIn();
  static final _auth         = FirebaseAuth.instance;
  static final _firestore    = FirebaseFirestore.instance;

  // ── Public entry point ────────────────────────────────────────────────────
  /// Signs in with Google, sends OTP to user's email, shows OTP dialog,
  /// verifies, then returns the user's role from Firestore.
  static Future<String?> signInWithGoogle(BuildContext context) async {
    // Always show account picker
    await _googleSignIn.signOut();

    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return null; // cancelled

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken:     googleAuth.idToken,
    );

    final cred = await _auth.signInWithCredential(credential);
    final uid   = cred.user!.uid;
    final email = cred.user!.email ?? '';
    final name  = cred.user!.displayName ?? '';

    // Lookup user in Firestore
    final userData = await _getUser(uid: uid, email: email);

    // Status checks
    final status = ((userData['status'] as String?) ?? 'active').toLowerCase();
    if (status == 'inactive') {
      await _auth.signOut();
      throw Exception('Your account has been deactivated. Please contact the administrator.');
    }
    if (status == 'pending') {
      await _auth.signOut();
      throw Exception('Your account is pending admin approval. You will be notified by email once approved.');
    }

    // ── Send OTP via server (dedicated endpoint — not the reset-password template) ──
    await _sendOtp(email: email, name: (userData['name'] as String?) ?? name);

    // ── Show OTP dialog ────────────────────────────────────────────────────
    if (!context.mounted) return null;
    final verified = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _OtpDialog(email: email),
    );

    if (verified != true) {
      await _auth.signOut();
      return null;
    }

    // Return role using Firestore name (not Google display name)
    return (userData['role'] as String?) ?? 'customer';
  }

  // ── Send OTP via EmailJS (no server needed — works on physical devices) ────
  static Future<void> _sendOtp({required String email, required String name}) async {
    final otp    = (100000 + Random.secure().nextInt(900000)).toString();
    final expiry = DateTime.now().toUtc().add(const Duration(minutes: 5)).toIso8601String();

    // Store OTP in Firestore for verification
    await FirebaseFirestore.instance
        .collection('otp_requests')
        .doc(email)
        .set({
      'otp':       otp,
      'expiry':    expiry,
      'email':     email,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Send via EmailJS (instant, no server needed)
    final res = await http.post(
      Uri.parse('https://api.emailjs.com/api/v1.0/email/send'),
      headers: {
        'Content-Type': 'application/json',
        'origin': 'https://dashboard.emailjs.com',
      },
      body: jsonEncode({
        'service_id':  _kEmailjsServiceId,
        'template_id': _kEmailjsTemplateId,
        'user_id':     _kEmailjsPublicKey,
        'template_params': {
          'to_email':      email,
          'to_name':       name.isNotEmpty ? name : email,
          'email':         email,
          'otp_code':      otp,
          'otp':           otp,
          'expiry_minutes': '5',
          // Purpose: Sign-In Verification
          'email_title':   'Sign-In Verification — Caltex AutoPro',
          'email_heading': 'Sign-In Verification',
          'email_intro':   'Someone is signing in to your Caltex AutoPro account using Google.\nUse the code below to verify your identity.',
          'steps_heading': 'Verify your sign-in:',
          'step1_icon':  '📲', 'step1_title': 'Enter the code',      'step1_desc': 'Enter the 6-digit code in the verification screen.',
          'step2_icon':  '✅', 'step2_title': 'Access your account',  'step2_desc': 'Once verified, you will be signed in to your dashboard.',
          'step3_icon':  '🔒', 'step3_title': 'Stay secure',          'step3_desc': 'Never share this code. We will never ask for it.',
          'footer_note': 'If you did not attempt to sign in, please secure your account immediately.',
        },
      }),
    ).timeout(const Duration(seconds: 15));

    if (res.statusCode != 200) {
      throw Exception('Failed to send OTP (EmailJS ${res.statusCode})');
    }
  }

  // ── Firestore user lookup ─────────────────────────────────────────────────
  static Future<Map<String, dynamic>> _getUser({
    required String uid,
    required String email,
  }) async {
    // Try by UID first
    final uidDoc = await _firestore.collection('users').doc(uid).get();
    if (uidDoc.exists) return uidDoc.data() ?? {};

    // Fallback: by email
    final snap = await _firestore
        .collection('users')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();
    if (snap.docs.isNotEmpty) {
      final data = snap.docs.first.data();
      // Migrate to UID-keyed doc
      await _firestore.collection('users').doc(uid).set(data);
      return data;
    }

    throw Exception('User account not found. Please contact the administrator to register your account.');
  }

  // ── Sign out ──────────────────────────────────────────────────────────────
  static Future<void> signOut() async {
    AdminChatStore.clear();
    CustomerChatStore.clear();
    await _auth.signOut();
    await _googleSignIn.signOut();
  }

  static bool isSignedIn() => _auth.currentUser != null;
  static String? getCurrentUserEmail() => _auth.currentUser?.email;

  static Future<Map<String, dynamic>?> getCurrentUserData() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    final doc = await _firestore.collection('users').doc(user.uid).get();
    return doc.data();
  }

  static Future<String?> getCurrentUserRole() async {
    final data = await getCurrentUserData();
    return data?['role'] as String?;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// OTP Verification Dialog
// ═══════════════════════════════════════════════════════════════════════════
class _OtpDialog extends StatefulWidget {
  final String email;
  const _OtpDialog({required this.email});

  @override
  State<_OtpDialog> createState() => _OtpDialogState();
}

class _OtpDialogState extends State<_OtpDialog> {
  static const _red = Color(0xFFE8001C);

  final List<TextEditingController> _ctrls =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _foci =
      List.generate(6, (_) => FocusNode());

  bool _loading  = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _ctrls) c.dispose();
    for (final f in _foci) f.dispose();
    super.dispose();
  }

  String get _entered => _ctrls.map((c) => c.text).join();

  // ── Verify OTP against Firestore ──────────────────────────────────────────
  Future<void> _verify() async {
    final entered = _entered;
    if (entered.length < 6) {
      setState(() => _error = 'Please enter the 6-digit code.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final snap = await FirebaseFirestore.instance
          .collection('otp_requests')
          .doc(widget.email)
          .get();

      if (!snap.exists) {
        setState(() { _loading = false; _error = 'OTP not found. Please request a new one.'; });
        return;
      }

      final data      = snap.data()!;
      final stored    = data['otp'] as String? ?? '';
      final expiryStr = data['expiry'] as String? ?? '';
      // Ensure expiry treated as UTC
      final expiry = DateTime.tryParse(
          expiryStr.endsWith('Z') ? expiryStr : '${expiryStr}Z');

      if (expiry == null || DateTime.now().toUtc().isAfter(expiry)) {
        await snap.reference.delete();
        setState(() { _loading = false; _error = 'OTP has expired. Please resend.'; });
        for (final c in _ctrls) c.clear();
        return;
      }

      if (entered != stored) {
        setState(() { _loading = false; _error = 'Incorrect OTP. Please try again.'; });
        for (final c in _ctrls) c.clear();
        _foci[0].requestFocus();
        return;
      }

      await snap.reference.delete();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() { _loading = false; _error = 'Verification failed: $e'; });
    }
  }

  // ── Resend OTP ─────────────────────────────────────────────────────────────
  Future<void> _resend() async {
    setState(() { _loading = true; _error = null; });
    try {
      final otp    = (100000 + Random.secure().nextInt(900000)).toString();
      final expiry = DateTime.now().toUtc().add(const Duration(minutes: 5)).toIso8601String();

      await FirebaseFirestore.instance
          .collection('otp_requests')
          .doc(widget.email)
          .set({
        'otp':       otp,
        'expiry':    expiry,
        'email':     widget.email,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await http.post(
        Uri.parse('https://api.emailjs.com/api/v1.0/email/send'),
        headers: {
          'Content-Type': 'application/json',
          'origin': 'https://dashboard.emailjs.com',
        },
        body: jsonEncode({
          'service_id':  _kEmailjsServiceId,
          'template_id': _kEmailjsTemplateId,
          'user_id':     _kEmailjsPublicKey,
          'template_params': {
            'to_email':       widget.email,
            'to_name':        widget.email,
            'email':          widget.email,
            'otp_code':       otp,
            'otp':            otp,
            'expiry_minutes': '5',
            // Purpose: Sign-In Verification
            'email_title':   'Sign-In Verification — Caltex AutoPro',
            'email_heading': 'Sign-In Verification',
            'email_intro':   'Someone is signing in to your Caltex AutoPro account using Google.\nUse the code below to verify your identity.',
            'steps_heading': 'Verify your sign-in:',
            'step1_icon':  '📲', 'step1_title': 'Enter the code',      'step1_desc': 'Enter the 6-digit code in the verification screen.',
            'step2_icon':  '✅', 'step2_title': 'Access your account',  'step2_desc': 'Once verified, you will be signed in to your dashboard.',
            'step3_icon':  '🔒', 'step3_title': 'Stay secure',          'step3_desc': 'Never share this code. We will never ask for it.',
            'footer_note': 'If you did not attempt to sign in, please secure your account immediately.',
          },
        }),
      ).timeout(const Duration(seconds: 15));

      for (final c in _ctrls) c.clear();
      _foci[0].requestFocus();
      setState(() { _loading = false; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('New code sent!'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      setState(() { _loading = false; _error = 'Failed to resend. Please try again.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFFE8001C), Color(0xFF9B0013)]),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                  color: Colors.white24, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.verified_user_outlined, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            const Text('Verify Your Identity',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
          ]),
        ),

        // Body
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            Text('A 6-digit verification code was sent to your email.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.5)),
            const SizedBox(height: 4),
            Text('Expires in 5 minutes.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
            const SizedBox(height: 20),

            // OTP boxes
            Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(6, (i) =>
              SizedBox(
                width: 42, height: 50,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: TextField(
                    controller: _ctrls[i],
                    focusNode: _foci[i],
                    maxLength: 1,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    decoration: InputDecoration(
                      counterText: '',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFFe2e8f0))),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: _red, width: 2)),
                      filled: true,
                      fillColor: const Color(0xFFF7F8FA),
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (val) {
                      if (val.isNotEmpty && i < 5) _foci[i + 1].requestFocus();
                      if (val.isEmpty && i > 0)    _foci[i - 1].requestFocus();
                      if (_ctrls.every((c) => c.text.isNotEmpty)) _verify();
                    },
                  ),
                ),
              )
            )),

            // Error
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                    color: const Color(0xFFFFF5F5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFECACA))),
                child: Text(_error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Color(0xFFC53030))),
              ),
            ],

            const SizedBox(height: 20),

            // Verify button
            SizedBox(width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _verify,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _red, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                  disabledBackgroundColor: _red.withOpacity(0.5)),
                child: _loading
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Verify & Continue',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              )),
            const SizedBox(height: 12),

            // Resend
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text("Didn't receive the code? ",
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              GestureDetector(
                onTap: _loading ? null : _resend,
                child: const Text('Resend',
                    style: TextStyle(fontSize: 12, color: _red, fontWeight: FontWeight.w700))),
            ]),
          ]),
        ),
      ]),
    );
  }
}
