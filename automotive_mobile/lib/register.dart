import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

// -- OneSignal push (same credentials as notifications.dart) --
const _kOneSignalAppId = 'c4f82ac7-5340-4e7a-877d-1d38a6f6f8ea';
const _kOneSignalApiKey =
    'os_v2_app_yt4cvr2tibhhvb35du4k637i5l5mjeywytben3fd6lmzeiyhnrp6hzfi3uq77vkidwssmkrud4mdada7wp3sg2dpybuk4vrrtc7cs7y';

// Philippine mobile formatter: 09XX-XXX-XXXX
class _PhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final capped = digits.length > 11 ? digits.substring(0, 11) : digits;

    String formatted;
    if (capped.length <= 4) {
      formatted = capped;
    } else if (capped.length <= 7) {
      formatted = '${capped.substring(0, 4)}-${capped.substring(4)}';
    } else {
      formatted = '${capped.substring(0, 4)}-${capped.substring(4, 7)}-${capped.substring(7)}';
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _passVisible = false;
  bool _confirmVisible = false;
  bool _showPassToggle = false;
  bool _showConfirmToggle = false;
  bool _loading = false;

  static const _red = Color(0xFFE8001C);

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    final firstName = _firstNameCtrl.text.trim();
    final lastName = _lastNameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final password = _passwordCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();

    if (firstName.isEmpty ||
        lastName.isEmpty ||
        email.isEmpty ||
        phone.isEmpty ||
        password.isEmpty ||
        confirm.isEmpty) {
      _showError('Please fill in all fields.');
      return;
    }

    final phoneDigits = phone.replaceAll(RegExp(r'\D'), '');
    if (phoneDigits.length != 11 || !phoneDigits.startsWith('09')) {
      _showError('Enter a valid PH mobile number (e.g. 09XX-XXX-XXXX).');
      return;
    }

    if (password != confirm) {
      _showError('Passwords do not match.');
      return;
    }

    if (password.length < 8) {
      _showError('Password must be at least 8 characters.');
      return;
    }

    final _hasSpecial = RegExp(r'[!@#\$%^&*(),.?":{}|<>_\-+=\[\]\\\/~`]');
    if (!_hasSpecial.hasMatch(password)) {
      _showError('Password must contain at least one special character (e.g. @, #, !, \$).');
      return;
    }

    setState(() => _loading = true);
    try {
      // Create Firebase Auth account
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final uid = cred.user!.uid;

      // Update display name
      await cred.user!.updateDisplayName('$firstName $lastName');

      // Save user document to Firestore
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'uid': uid,
        'firstName': firstName,
        'lastName': lastName,
        'name': '$firstName $lastName',
        'email': email,
        'phoneNumber': phoneDigits,
        'role': 'customer',
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Notify admins about new registration
      await FirebaseFirestore.instance.collection('notifications').add({
        'title': '?? New Account Registered',
        'message': '$firstName $lastName ($email) has created a new account.',
        'type': 'info',
        'targetRole': 'admin',
        'targetUid': '',
        'createdAt': FieldValue.serverTimestamp(),
        'readBy': <String, bool>{},
        'isRead': false,
      });

      if (!mounted) return;
      // Sign out � they need to login with their new credentials
      await FirebaseAuth.instance.signOut();

      // Show success and go back to login
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account created successfully! You can now sign in.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
      Navigator.pop(context); // go back to login
    } on FirebaseAuthException catch (e) {
      final msg = switch (e.code) {
        'email-already-in-use' => 'An account with this email already exists.',
        'invalid-email' => 'Please enter a valid email address.',
        'weak-password' => 'Password is too weak. Use at least 8 characters with a special character.',
        _ => e.message ?? 'Registration failed.',
      };
      _showError(msg);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showPendingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3CD),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.hourglass_top_rounded,
                size: 36,
                color: Color(0xFFF6AD55),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Registration Submitted!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1a202c),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Your account is pending admin approval.\n\nYou will receive an email once your account has been approved.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF718096),
                height: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              onPressed: () {
                Navigator.pop(context); // close dialog
                Navigator.pop(context); // go back to login
              },
              child: const Text(
                'Back to Login',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 40),

              // -- Form --
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Center(
                      child: Text(
                        'Create Account',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1a202c),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Center(
                      child: Text(
                        'Sign up to get started',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF718096),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // First Name
                    _label('First Name'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _firstNameCtrl,
                      textCapitalization: TextCapitalization.words,
                      style: _inputTextStyle,
                      decoration: _inputDecoration(
                        'First name',
                        Icons.person_outline,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Last Name
                    _label('Last Name'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _lastNameCtrl,
                      textCapitalization: TextCapitalization.words,
                      style: _inputTextStyle,
                      decoration: _inputDecoration(
                        'Last name',
                        Icons.person_outline,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Email
                    _label('Email Address'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      style: _inputTextStyle,
                      decoration: _inputDecoration(
                        'Enter your email',
                        Icons.email_outlined,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Phone Number
                    _label('Phone Number'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        _PhoneFormatter(),
                      ],
                      style: _inputTextStyle,
                      decoration: _inputDecoration(
                        '09XX-XXX-XXXX',
                        Icons.phone_outlined,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Password
                    _label('Password'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _passwordCtrl,
                      obscureText: !_passVisible,
                      style: _inputTextStyle,
                      onChanged: (_) => setState(
                        () => _showPassToggle = _passwordCtrl.text.isNotEmpty,
                      ),
                      decoration: _inputDecoration(
                        'Create a password',
                        Icons.lock_outline,
                        suffix: _showPassToggle
                            ? IconButton(
                                icon: Icon(
                                  _passVisible
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                  color: const Color(0xFF718096),
                                ),
                                onPressed: () => setState(
                                  () => _passVisible = !_passVisible,
                                ),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Confirm Password
                    _label('Confirm Password'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _confirmCtrl,
                      obscureText: !_confirmVisible,
                      style: _inputTextStyle,
                      onSubmitted: (_) => _handleRegister(),
                      onChanged: (_) => setState(
                        () => _showConfirmToggle = _confirmCtrl.text.isNotEmpty,
                      ),
                      decoration: _inputDecoration(
                        'Confirm your password',
                        Icons.lock_outline,
                        suffix: _showConfirmToggle
                            ? IconButton(
                                icon: Icon(
                                  _confirmVisible
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                  color: const Color(0xFF718096),
                                ),
                                onPressed: () => setState(
                                  () => _confirmVisible = !_confirmVisible,
                                ),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Register button
                    SizedBox(
                      width: double.infinity,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFF004B5F), // Caltex teal
                              // Mid teal
                              Color(0xFFEE152A), // Caltex red
                            ],
                            stops: [0.0, 1.0],
                          ),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: ElevatedButton(
                          onPressed: _loading ? null : _handleRegister,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            elevation: 0,
                          ),
                          child: _loading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Create Account',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Already have an account
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Already have an account? ',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF718096),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: const Text(
                            'Sign In',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _red,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const _inputTextStyle = TextStyle(
    fontSize: 14,
    color: Color(0xFF1a202c),
  );

  Widget _label(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: Color(0xFF4a5568),
    ),
  );

  InputDecoration _inputDecoration(
    String hint,
    IconData icon, {
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFFa0aec0), fontSize: 14),
      prefixIcon: Icon(icon, color: const Color(0xFF718096), size: 20),
      suffixIcon: suffix,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFe2e8f0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFe2e8f0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _red, width: 1.5),
      ),
      filled: true,
      fillColor: const Color(0xFFF7F8FA),
    );
  }
}
