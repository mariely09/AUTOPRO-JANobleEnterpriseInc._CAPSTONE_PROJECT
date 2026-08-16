import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

const _emailjsServiceId  = 'service_i906b4o';
const _emailjsTemplateId = 'template_6kkir1s';
const _emailjsPublicKey  = 'DqRrjCkUnf9w2L_sv';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

enum _Step { email, otp, success }

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  static const _red = Color(0xFFE8001C);

  _Step _step = _Step.email;

  final _emailCtrl = TextEditingController();
  final List<TextEditingController> _otpCtrls =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocus =
      List.generate(6, (_) => FocusNode());

  bool _loading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    for (final c in _otpCtrls) c.dispose();
    for (final f in _otpFocus) f.dispose();
    super.dispose();
  }

  // ── Step 1: Send OTP ──────────────────────────────────────────────────────

  Future<void> _sendOtp() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      _snack('Please enter your email address.', isError: true);
      return;
    }

    setState(() => _loading = true);
    try {
      final otp    = (100000 + Random.secure().nextInt(900000)).toString();
      final expiry = DateTime.now().add(const Duration(minutes: 5));

      await FirebaseFirestore.instance
          .collection('otp_requests')
          .doc(email)
          .set({
        'otp':       otp,
        'expiry':    expiry.toIso8601String(),
        'email':     email,
        'createdAt': FieldValue.serverTimestamp(),
      });

      final sent = await _sendEmailJS(email: email, otp: otp);
      if (!sent) return;

      if (!mounted) return;
      setState(() => _step = _Step.otp);
    } on FirebaseException catch (e) {
      _snack(e.code == 'permission-denied'
          ? 'Firestore permission denied. Update rules for otp_requests.'
          : 'Error: ${e.message}', isError: true);
    } catch (e) {
      _snack('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _sendEmailJS({required String email, required String otp}) async {
    try {
      final res = await http.post(
        Uri.parse('https://api.emailjs.com/api/v1.0/email/send'),
        headers: {
          'Content-Type': 'application/json',
          'origin': 'https://dashboard.emailjs.com',
        },
        body: jsonEncode({
          'service_id':  _emailjsServiceId,
          'template_id': _emailjsTemplateId,
          'user_id':     _emailjsPublicKey,
          'template_params': {
            'to_email':       email,
            'to_name':        email,
            'email':          email,
            'otp_code':       otp,
            'otp':            otp,
            'expiry_minutes': '5',
            // Purpose: Password Reset
            'email_title':   'Password Reset OTP — Caltex AutoPro',
            'email_heading': 'Password Reset OTP',
            'email_intro':   'You requested to reset your Caltex AutoPro account password.\nUse the code below to verify your identity.',
            'steps_heading': 'How to reset your password:',
            'step1_icon':  '📲', 'step1_title': 'Enter the OTP',      'step1_desc': 'Open the AutoPro app and enter the code above in the OTP field.',
            'step2_icon':  '🔑', 'step2_title': 'Set a new password',  'step2_desc': 'Enter and confirm your new password when prompted.',
            'step3_icon':  '✅', 'step3_title': 'Sign in',             'step3_desc': 'Log in with your new password and you\'re all set.',
            'footer_note': 'If you did not request a password reset, ignore this email. Your account remains secure.',
          },
        }),
      );
      debugPrint('EmailJS ${res.statusCode}: ${res.body}');
      if (res.statusCode != 200) {
        _snack('EmailJS error (${res.statusCode}): ${res.body}', isError: true);
        return false;
      }
      return true;
    } catch (e) {
      _snack('Network error: $e', isError: true);
      return false;
    }
  }

  Future<void> _sendResetNotificationEmail({required String email}) async {
    // Skipped — Firebase already sends the password reset link directly.
    // Using template_reset_link removed to stay within the free EmailJS 2-template limit.
    debugPrint('Reset link sent by Firebase to $email');
  }

  // ── Step 2: Verify OTP → send Firebase reset email ───────────────────────

  Future<void> _verifyOtp() async {
    if (_loading) return;
    final entered = _otpCtrls.map((c) => c.text).join();
    if (entered.length < 6) {
      _snack('Please enter the 6-digit OTP.', isError: true);
      return;
    }

    setState(() => _loading = true);
    try {
      final email = _emailCtrl.text.trim();
      final doc = await FirebaseFirestore.instance
          .collection('otp_requests')
          .doc(email)
          .get();

      if (!doc.exists) {
        _snack('OTP not found. Please request a new one.', isError: true);
        return;
      }

      final data      = doc.data()!;
      final storedOtp = data['otp']    as String? ?? '';
      final expiryStr = data['expiry'] as String? ?? '';
      final expiry    = DateTime.tryParse(expiryStr);

      if (expiry == null || DateTime.now().isAfter(expiry)) {
        _snack('OTP has expired. Please request a new one.', isError: true);
        await doc.reference.delete();
        if (mounted) setState(() { _step = _Step.email; for (final c in _otpCtrls) c.clear(); });
        return;
      }

      if (entered != storedOtp) {
        _snack('Incorrect OTP. Please try again.', isError: true);
        for (final c in _otpCtrls) c.clear();
        if (mounted) _otpFocus[0].requestFocus();
        return;
      }

      // ✅ OTP valid — delete doc, send Firebase reset email + branded notification
      await doc.reference.delete();

      // Firebase sends the actual reset link to the user's email
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      // Also send a branded EmailJS notification so the user knows what to expect
      await _sendResetNotificationEmail(email: email);

      if (!mounted) return;
      setState(() => _step = _Step.success);
    } on FirebaseException catch (e) {
      _snack(e.code == 'permission-denied'
          ? 'Permission denied. Update Firestore rules for otp_requests.'
          : 'Error: ${e.message}', isError: true);
    } on FirebaseAuthException catch (e) {
      _snack(e.message ?? 'Failed to send reset email.', isError: true);
    } catch (e) {
      _snack('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.redAccent : Colors.green,
      duration: const Duration(seconds: 4),
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(children: [
            _buildHeader(),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
              child: _step == _Step.email
                  ? _buildEmailStep()
                  : _step == _Step.otp
                      ? _buildOtpStep()
                      : _buildSuccessStep(),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return const SizedBox(height: 40);
  }

  // ── Step 1 ────────────────────────────────────────────────────────────────

  Widget _buildEmailStep() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _backBtn(),
      const SizedBox(height: 24),
      const Center(child: Text('Forgot Password',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1a202c)))),
      const SizedBox(height: 6),
      const Center(child: Text(
          'Enter your registered email and we\'ll send a 6-digit OTP.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Color(0xFF718096), height: 1.5))),
      const SizedBox(height: 32),
      const Text('Email Address',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF4a5568))),
      const SizedBox(height: 6),
      TextField(
        controller: _emailCtrl,
        keyboardType: TextInputType.emailAddress,
        autofocus: true,
        onSubmitted: (_) => _sendOtp(),
        style: const TextStyle(fontSize: 14, color: Color(0xFF1a202c)),
        decoration: _inputDeco('Enter your email', Icons.email_outlined),
      ),
      const SizedBox(height: 28),
      _btn(label: 'Send OTP', icon: Icons.send_outlined, onTap: _loading ? null : _sendOtp),
    ]);
  }

  // ── Step 2 ────────────────────────────────────────────────────────────────

  Widget _buildOtpStep() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _backBtn(onTap: () => setState(() {
        _step = _Step.email;
        for (final c in _otpCtrls) c.clear();
      })),
      const SizedBox(height: 24),
      const Center(child: Text('Enter OTP',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1a202c)))),
      const SizedBox(height: 6),
      Center(child: Text(
          'A 6-digit code was sent to\n${_emailCtrl.text.trim()}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: Color(0xFF718096), height: 1.5))),
      const SizedBox(height: 4),
      const Center(child: Text('Expires in 5 minutes.',
          style: TextStyle(fontSize: 11, color: Color(0xFF718096)))),
      const SizedBox(height: 32),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(6, (i) => SizedBox(
          width: 46, height: 56,
          child: TextField(
            controller: _otpCtrls[i],
            focusNode: _otpFocus[i],
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            maxLength: 1,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1a202c)),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              counterText: '',
              contentPadding: EdgeInsets.zero,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFe2e8f0))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFe2e8f0))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _red, width: 2)),
              filled: true, fillColor: const Color(0xFFF7F8FA),
            ),
            onChanged: (val) {
              if (val.isNotEmpty && i < 5) _otpFocus[i + 1].requestFocus();
              if (val.isEmpty && i > 0)    _otpFocus[i - 1].requestFocus();
              if (_otpCtrls.every((c) => c.text.isNotEmpty)) _verifyOtp();
            },
          ),
        )),
      ),
      const SizedBox(height: 28),
      _btn(label: 'Verify OTP', icon: Icons.verified_outlined, onTap: _loading ? null : _verifyOtp),
      const SizedBox(height: 14),
      Center(child: TextButton(
        onPressed: _loading ? null : () {
          for (final c in _otpCtrls) c.clear();
          _otpFocus[0].requestFocus();
          _sendOtp();
        },
        child: const Text('Didn\'t receive the code? Resend',
            style: TextStyle(fontSize: 13, color: Color(0xFF718096))),
      )),
    ]);
  }

  // ── Step 3: Success ───────────────────────────────────────────────────────

  Widget _buildSuccessStep() {
    return Column(children: [
      const SizedBox(height: 16),
      const Text('Check Your Email',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1a202c))),
      const SizedBox(height: 10),
      Text(
        'A password reset link was sent to\n${_emailCtrl.text.trim()}',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13, color: Color(0xFF718096), height: 1.6)),
      const SizedBox(height: 24),

      // Steps
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F8FA),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFe2e8f0))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _stepRow('1', 'Open the email in your inbox'),
          const SizedBox(height: 10),
          _stepRow('2', 'Tap the reset link'),
          const SizedBox(height: 10),
          _stepRow('3', 'Set your new password'),
          const SizedBox(height: 10),
          _stepRow('4', 'Come back and sign in ✓'),
        ]),
      ),
      const SizedBox(height: 28),

      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: ElevatedButton.styleFrom(
            backgroundColor: _red, foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            elevation: 4,
          ),
          child: const Text('Go to Login',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ),
      ),
      const SizedBox(height: 12),
      TextButton(
        onPressed: () async {
          setState(() => _loading = true);
          try {
            await FirebaseAuth.instance
                .sendPasswordResetEmail(email: _emailCtrl.text.trim());
            _snack('Reset link resent!', isError: false);
          } catch (_) {
            _snack('Failed to resend.', isError: true);
          } finally {
            if (mounted) setState(() => _loading = false);
          }
        },
        child: const Text('Resend email',
            style: TextStyle(fontSize: 13, color: Color(0xFF718096))),
      ),
    ]);
  }

  Widget _stepRow(String num, String text) {
    return Row(children: [
      Container(
        width: 24, height: 24,
        decoration: BoxDecoration(color: _red, borderRadius: BorderRadius.circular(12)),
        child: Center(child: Text(num,
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
      ),
      const SizedBox(width: 10),
      Expanded(child: Text(text,
          style: const TextStyle(fontSize: 13, color: Color(0xFF4a5568)))),
    ]);
  }

  // ── Shared widgets ────────────────────────────────────────────────────────

  Widget _backBtn({VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap ?? () => Navigator.pop(context),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.arrow_back_ios, size: 14, color: Color(0xFF718096)),
        SizedBox(width: 4),
        Text('Back', style: TextStyle(fontSize: 13, color: Color(0xFF718096))),
      ]),
    );
  }

  InputDecoration _inputDeco(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFFa0aec0), fontSize: 14),
      prefixIcon: Icon(icon, color: const Color(0xFF718096), size: 20),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFe2e8f0))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFe2e8f0))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _red, width: 1.5)),
      filled: true, fillColor: const Color(0xFFF7F8FA),
    );
  }

  Widget _btn({required String label, required IconData icon, VoidCallback? onTap}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: _red, foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          elevation: 4,
        ),
        child: _loading
            ? const SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 18),
                const SizedBox(width: 8),
                Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ]),
      ),
    );
  }
}
