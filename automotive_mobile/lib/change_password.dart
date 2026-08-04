import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_dashboard.dart';
import 'staff_dashboard.dart';
import 'customer_dashboard.dart';

/// Shown on first login when admin-created accounts must change their
/// temporary password before accessing the app.
/// Also used from the Profile screen to update an existing password.
class ChangePasswordScreen extends StatefulWidget {
  final String role;
  /// true  → first-login flow (logo header, no back button, redirects to dashboard)
  /// false → profile flow (standard AppBar with back button, pops on success)
  final bool firstLogin;
  /// Optional: pre-fill the "current password" field (passed from login screen)
  final String? tempPassword;
  const ChangePasswordScreen({super.key, required this.role, this.firstLogin = false, this.tempPassword});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  static const _red  = Color(0xFFE8001C);
  static const _blue = Color(0xFF003087);

  final _currentCtrl  = TextEditingController();
  final _newCtrl      = TextEditingController();
  final _confirmCtrl  = TextEditingController();

  bool _showCurrent = false;
  bool _showNew     = false;
  bool _showConfirm = false;
  bool _loading     = false;

  double _strength     = 0;
  String _strengthText = '';
  Color  _strengthColor = Colors.transparent;

  @override
  void initState() {
    super.initState();
    if (widget.tempPassword != null && widget.tempPassword!.isNotEmpty) {
      _currentCtrl.text = widget.tempPassword!;
    }
  }

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _checkStrength(String val) {
    int score = 0;
    if (val.length >= 6)  score++;
    if (val.length >= 10) score++;
    if (RegExp(r'[A-Z]').hasMatch(val) && RegExp(r'[a-z]').hasMatch(val)) score++;
    if (RegExp(r'\d').hasMatch(val))          score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(val)) score++;

    setState(() {
      _strength = val.isEmpty ? 0 : score / 4;
      if (val.isEmpty)   { _strengthText = '';       _strengthColor = Colors.transparent; }
      else if (score <= 1) { _strengthText = 'Weak';   _strengthColor = _red; }
      else if (score == 2) { _strengthText = 'Fair';   _strengthColor = Colors.orange; }
      else if (score == 3) { _strengthText = 'Good';   _strengthColor = Colors.amber; }
      else                 { _strengthText = 'Strong'; _strengthColor = Colors.green; }
    });
  }

  Future<void> _submit() async {
    final current = _currentCtrl.text.trim();
    final newPass = _newCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();

    if (current.isEmpty) { _toast('Enter your current (temporary) password.'); return; }
    if (newPass.isEmpty)  { _toast('Enter a new password.'); return; }
    if (newPass.length < 6) { _toast('Password must be at least 6 characters.'); return; }
    if (newPass != confirm) { _toast('Passwords do not match.'); return; }

    setState(() => _loading = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final cred = EmailAuthProvider.credential(
          email: user.email!, password: current);

      await user.reauthenticateWithCredential(cred);
      await user.updatePassword(newPass);

      // Clear the flag in Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'mustChangePassword': false});

      if (!mounted) return;
      _toast('Password updated successfully!', success: true);

      await Future.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return;

      if (widget.firstLogin) {
        _navigateToDashboard();
      } else {
        Navigator.pop(context);
      }
    } on FirebaseAuthException catch (e) {
      final msg = (e.code == 'wrong-password' || e.code == 'invalid-credential')
          ? 'Current password is incorrect.'
          : e.message ?? 'Error updating password.';
      _toast(msg);
    } catch (e) {
      _toast('Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _navigateToDashboard() {
    Widget dest;
    switch (widget.role) {
      case 'admin':    dest = const AdminDashboard();    break;
      case 'staff':    dest = const StaffDashboard();    break;
      default:         dest = const CustomerDashboard(); break;
    }
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => dest));
  }

  void _toast(String msg, {bool success = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: success ? Colors.green : Colors.redAccent,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    // ── Profile flow: standard AppBar, no logo header ──
    if (!widget.firstLogin) {
      return Scaffold(
        backgroundColor: const Color(0xFFF7F8FA),
        appBar: AppBar(
          backgroundColor: _red,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('Change Password',
              style: TextStyle(color: Colors.white, fontSize: 16,
                  fontWeight: FontWeight.bold)),
        ),
        body: SafeArea(child: _buildForm(showBanner: false)),
      );
    }

    // ── First-login flow: no logo, no AppBar ──
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: SafeArea(child: _buildForm(showBanner: true)),
    );
  }

  Widget _buildForm({required bool showBanner}) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Title + subtitle (first-login only) ──
        if (showBanner) ...[
          const Center(
            child: Text('Set New Password',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
                    color: Color(0xFF1a202c))),
          ),
          const SizedBox(height: 6),
          const Center(
            child: Text(
              'You must change your temporary password\nbefore continuing.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Color(0xFF718096), height: 1.5)),
          ),
          const SizedBox(height: 20),
        ],

        // ── Warning banner (first-login only) ──
        if (showBanner) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              border: Border.all(color: const Color(0xFFF6AD55)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(children: [
              Text('🔐', style: TextStyle(fontSize: 18)),
              SizedBox(width: 10),
              Expanded(child: Text(
                'Action required: This is your first login. Please set a personal password to continue.',
                style: TextStyle(fontSize: 12, color: Color(0xFF744210), height: 1.5),
              )),
            ]),
          ),
          const SizedBox(height: 24),
        ],

        // ── Form card ──
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10, offset: const Offset(0, 2))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Current Password',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                    color: Color(0xFF4a5568))),
            const SizedBox(height: 6),
            _passwordField(
              controller: _currentCtrl,
              hint: showBanner ? 'Enter temporary password' : 'Enter current password',
              visible: _showCurrent,
              onToggle: () => setState(() => _showCurrent = !_showCurrent),
            ),
            const SizedBox(height: 16),
            const Divider(color: Color(0xFFe2e8f0)),
            const SizedBox(height: 16),

            const Text('New Password',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                    color: Color(0xFF4a5568))),
            const SizedBox(height: 6),
            _passwordField(
              controller: _newCtrl,
              hint: 'Enter new password',
              visible: _showNew,
              onToggle: () => setState(() => _showNew = !_showNew),
              onChanged: _checkStrength,
            ),
            if (_newCtrl.text.isNotEmpty) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _strength.clamp(0.0, 1.0),
                  backgroundColor: const Color(0xFFe2e8f0),
                  valueColor: AlwaysStoppedAnimation(_strengthColor),
                  minHeight: 5,
                ),
              ),
              const SizedBox(height: 4),
              Text(_strengthText,
                  style: TextStyle(fontSize: 11, color: _strengthColor,
                      fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 16),

            const Text('Confirm New Password',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                    color: Color(0xFF4a5568))),
            const SizedBox(height: 6),
            _passwordField(
              controller: _confirmCtrl,
              hint: 'Confirm new password',
              visible: _showConfirm,
              onToggle: () => setState(() => _showConfirm = !_showConfirm),
            ),
            const SizedBox(height: 8),
            const Text('Must be at least 6 characters.',
                style: TextStyle(fontSize: 11, color: Color(0xFF718096))),
          ]),
        ),
        const SizedBox(height: 24),

        // ── Submit button ──
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _loading ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: _red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30)),
              elevation: 4,
            ),
            child: _loading
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.lock_outline, size: 18),
                    SizedBox(width: 8),
                    Text('Save',
                        style: TextStyle(fontSize: 15,
                            fontWeight: FontWeight.w700)),
                  ]),
          ),
        ),
      ]),
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String hint,
    required bool visible,
    required VoidCallback onToggle,
    void Function(String)? onChanged,
  }) {
    return TextField(
      controller: controller,
      obscureText: !visible,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 14, color: Color(0xFF1a202c)),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFFa0aec0), fontSize: 13),
        prefixIcon: const Icon(Icons.lock_outline,
            color: Color(0xFF718096), size: 20),
        suffixIcon: IconButton(
          icon: Icon(visible ? Icons.visibility : Icons.visibility_off,
              color: const Color(0xFF718096), size: 20),
          onPressed: onToggle,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFe2e8f0))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFe2e8f0))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _red, width: 1.5)),
        filled: true,
        fillColor: const Color(0xFFF7F8FA),
      ),
    );
  }
}
