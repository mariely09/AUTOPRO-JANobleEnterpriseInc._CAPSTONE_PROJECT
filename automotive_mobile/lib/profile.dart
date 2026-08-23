import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'login.dart';
import 'change_password.dart';
import 'notifs_manageAlerts.dart';
import 'help_support.dart';
import 'privacy_policy.dart';
import 'admin_rag_ai.dart';
import 'customer_smart_ai.dart';
import 'terms_conditions.dart';
import 'onesignal_debug.dart';

enum UserRole { customer, staff, admin }

/// Philippine phone number formatter: +63 (max 10 digits after)
class PhilippinePhoneFormatter extends TextInputFormatter {
  static const _prefix = '+63';

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Always ensure prefix is present
    String text = newValue.text;
    if (!text.startsWith(_prefix)) {
      // strip any non-digit after prefix was deleted, keep only digits and re-add prefix
      final digits = text.replaceAll(RegExp(r'\D'), '');
      text = _prefix + digits;
    }
    // Keep only digits after the prefix, max 10
    final after = text.substring(_prefix.length).replaceAll(RegExp(r'\D'), '');
    final clamped = after.length > 10 ? after.substring(0, 10) : after;
    final result = _prefix + clamped;
    final offset = result.length.clamp(_prefix.length, result.length);
    return TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

class UserProfile extends StatefulWidget {
  final UserRole role;
  const UserProfile({super.key, required this.role});

  @override
  State<UserProfile> createState() => _UserProfileState();
}

class _UserProfileState extends State<UserProfile> {
  static const _red = Color(0xFFE8001C);
  static const _blue = Color(0xFF003087);

  File? _avatarImage;
  bool _editingInfo = false;
  bool _loading = true;
  String? _photoUrl;
  String _origName = '';
  String _origEmail = '';
  String _origPhone = '';
  String _origCompany = '';

  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _roleCtrl = TextEditingController();
  final _companyCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  StreamSubscription<DocumentSnapshot>? _profileSub;

  @override
  void initState() {
    super.initState();
    _subscribeToProfile();
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _roleCtrl.dispose();
    _companyCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _subscribeToProfile() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _profileSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen(
          (doc) {
            if (!mounted) return;
            final data = doc.data() ?? {};
            final role = (data['role'] as String? ?? '');

            // Don't overwrite fields the user is actively editing
            if (!_editingInfo) {
              setState(() {
                _firstNameCtrl.text =
                    data['firstName'] as String? ??
                    (_firstNameCtrl.text.isNotEmpty
                        ? _firstNameCtrl.text
                        : (data['name'] as String? ?? '').split(' ').first);
                _lastNameCtrl.text =
                    data['lastName'] as String? ??
                    (_lastNameCtrl.text.isNotEmpty
                        ? _lastNameCtrl.text
                        : (data['name'] as String? ?? '')
                              .split(' ')
                              .skip(1)
                              .join(' '));
                _emailCtrl.text = data['email'] as String? ?? _emailCtrl.text;
                _companyCtrl.text =
                    data['companyName'] as String? ?? _companyCtrl.text;
                _phoneCtrl.text =
                    data['phoneNumber'] as String? ?? _phoneCtrl.text;
                _roleCtrl.text = role.isEmpty
                    ? _roleCtrl.text
                    : role[0].toUpperCase() + role.substring(1);
                _photoUrl = data['photoUrl'] as String? ?? _photoUrl;
                _loading = false;
              });
            } else {
              // Still update role and photo even in edit mode (read-only fields)
              setState(() {
                _roleCtrl.text = role.isEmpty
                    ? _roleCtrl.text
                    : role[0].toUpperCase() + role.substring(1);
                _photoUrl = data['photoUrl'] as String? ?? _photoUrl;
                _loading = false;
              });
            }
          },
          onError: (e) {
            if (mounted) setState(() => _loading = false);
          },
        );
  }

  Future<void> _saveUserData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final firstName = _firstNameCtrl.text.trim();
    final lastName = _lastNameCtrl.text.trim();
    final newName = '$firstName $lastName'.trim();
    final newEmail = _emailCtrl.text.trim();
    final db = FirebaseFirestore.instance;

    await db.collection('users').doc(uid).update({
      'firstName': firstName,
      'lastName': lastName,
      'name': newName,
      'email': newEmail,
      if (_phoneCtrl.text.trim().isNotEmpty)
        'phoneNumber': _phoneCtrl.text.trim(),
      if (widget.role == UserRole.customer)
        'companyName': _companyCtrl.text.trim(),
    });

    // Update owner field on all vehicles belonging to this customer
    if (widget.role == UserRole.customer &&
        _origName.isNotEmpty &&
        _origName.toLowerCase() != newName.toLowerCase()) {
      final snap = await db.collection('vehicles').get();
      final batch = db.batch();
      for (final doc in snap.docs) {
        final owner = (doc.data()['owner'] as String? ?? '').toLowerCase();
        if (owner == _origName.toLowerCase()) {
          batch.update(doc.reference, {'owner': newName});
        }
      }
      await batch.commit();
    }
    _origName = newName;
  }

  /// Returns the correct ImageProvider for both base64 data URIs and https URLs.
  ImageProvider _photoImageProvider(String url) {
    if (url.startsWith('data:image')) {
      // Strip the data URI prefix and decode Base64
      final comma = url.indexOf(',');
      if (comma != -1) {
        final b64 = url.substring(comma + 1);
        return MemoryImage(base64Decode(b64));
      }
    }
    return NetworkImage(url);
  }

  String get _initials {
    final first = _firstNameCtrl.text.trim();
    final last = _lastNameCtrl.text.trim();
    if (first.isEmpty && last.isEmpty) return '?';
    if (last.isEmpty) return first[0].toUpperCase();
    return '${first[0]}${last[0]}'.toUpperCase();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    // Pick at low quality ??further compression applied below
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 50,
      maxWidth: 400,
      maxHeight: 400,
    );
    if (picked == null) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // Show uploading indicator
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 10),
              Text('Saving photo...'),
            ],
          ),
          backgroundColor: Color(0xFF2d3748),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 60),
        ),
      );
    }

    try {
      // Read and encode to Base64
      final file = File(picked.path);
      final bytes = await file.readAsBytes();

      // Firestore document limit is 1 MB ??enforce max size
      if (bytes.length > 900 * 1024) {
        throw Exception(
          'Image is too large (${(bytes.length / 1024).toStringAsFixed(0)} KB). '
          'Please choose a smaller image or crop it first.',
        );
      }

      final base64String = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      debugPrint('???Base64 size: ${base64String.length} chars');

      // Show instant local preview
      if (mounted) setState(() => _avatarImage = file);

      // Save directly to Firestore ??no Storage needed
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'photoUrl': base64String,
      });
      debugPrint('???Saved photoUrl (base64) to Firestore');

      if (mounted) {
        setState(() => _photoUrl = base64String);
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('Profile photo updated successfully!'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('??Photo save error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isStandalone = widget.role != UserRole.customer;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                // ── SliverAppBar with hero header inside ──
                SliverAppBar(
                  expandedHeight: 260,
                  pinned: true,
                  backgroundColor: const Color(0xFF004B5F),
                  automaticallyImplyLeading: false,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  title: const Text(
                    'Profile',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  flexibleSpace: FlexibleSpaceBar(
                    background: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Color(0xFF004B5F),
                            Color(0xFF006B7D),
                            Color(0xFFEE152A),
                          ],
                          stops: [0.0, 0.35, 1.0],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: SafeArea(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(height: 44),
                            GestureDetector(
                              onTap: _pickImage,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 3,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.2),
                                          blurRadius: 12,
                                        ),
                                      ],
                                    ),
                                    child: CircleAvatar(
                                      radius: 44,
                                      backgroundColor: Colors.white24,
                                      backgroundImage: _avatarImage != null
                                          ? FileImage(_avatarImage!)
                                                as ImageProvider
                                          : _photoUrl != null
                                          ? _photoImageProvider(_photoUrl!)
                                          : null,
                                      child:
                                          (_avatarImage == null &&
                                              _photoUrl == null)
                                          ? Text(
                                              _initials,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 28,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            )
                                          : null,
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 2,
                                    right: 2,
                                    child: Container(
                                      width: 26,
                                      height: 26,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 1.5,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(
                                              0.18,
                                            ),
                                            blurRadius: 4,
                                          ),
                                        ],
                                      ),
                                      child: const Icon(
                                        Icons.camera_alt,
                                        size: 14,
                                        color: Color(0xFFE8001C),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '${_firstNameCtrl.text} ${_lastNameCtrl.text}'
                                  .trim(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                _roleCtrl.text,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Body content as sliver ──
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        // ???? Account Info ????
                        _sectionLabel('ACCOUNT INFORMATION'),
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.04),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  8,
                                  4,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Info',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF718096),
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        TextButton.icon(
                                          onPressed: () async {
                                            if (_editingInfo) {
                                              // Validate phone number if not empty
                                              final phone = _phoneCtrl.text
                                                  .trim();
                                              if (phone.isNotEmpty) {
                                                // Phone must be +63 followed by exactly 10 digits
                                                final digitsOnly = phone
                                                    .replaceAll(
                                                      RegExp(r'\D'),
                                                      '',
                                                    );
                                                if (digitsOnly.length < 10) {
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    SnackBar(
                                                      content: const Row(
                                                        children: [
                                                          Icon(
                                                            Icons.error_outline,
                                                            color: Colors.white,
                                                            size: 18,
                                                          ),
                                                          SizedBox(width: 8),
                                                          Text(
                                                            'Phone number must be 10 digits',
                                                          ),
                                                        ],
                                                      ),
                                                      backgroundColor:
                                                          Colors.red,
                                                      behavior: SnackBarBehavior
                                                          .floating,
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              10,
                                                            ),
                                                      ),
                                                    ),
                                                  );
                                                  return;
                                                }
                                              }

                                              try {
                                                await _saveUserData();

                                                // Notify admins on profile update (customer only)
                                                if (widget.role ==
                                                    UserRole.customer) {
                                                  final fullName =
                                                      '${_firstNameCtrl.text.trim()} ${_lastNameCtrl.text.trim()}'
                                                          .trim();
                                                  final phone = _phoneCtrl.text
                                                      .trim();
                                                  final notifMsg =
                                                      '$fullName updated their profile.'
                                                      ' Email: ${_emailCtrl.text.trim()}'
                                                      '${phone.isNotEmpty ? ' | Phone: $phone' : ''}';
                                                  await FirebaseFirestore
                                                      .instance
                                                      .collection(
                                                        'notifications',
                                                      )
                                                      .add({
                                                        'title':
                                                            'Profile Updated',
                                                        'message': notifMsg,
                                                        'type': 'info',
                                                        'targetRole': 'admin',
                                                        'targetUid': '',
                                                        'readBy': {},
                                                        'isRead': false,
                                                        'createdAt':
                                                            FieldValue.serverTimestamp(),
                                                      });
                                                }

                                                if (mounted) {
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    SnackBar(
                                                      content: const Row(
                                                        children: [
                                                          Icon(
                                                            Icons
                                                                .check_circle_outline,
                                                            color: Colors.white,
                                                            size: 18,
                                                          ),
                                                          SizedBox(width: 8),
                                                          Text(
                                                            'Profile updated successfully!',
                                                          ),
                                                        ],
                                                      ),
                                                      backgroundColor:
                                                          Colors.green,
                                                      behavior: SnackBarBehavior
                                                          .floating,
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              10,
                                                            ),
                                                      ),
                                                    ),
                                                  );
                                                }
                                              } catch (e) {
                                                if (mounted) {
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        'Error: $e',
                                                      ),
                                                      backgroundColor:
                                                          Colors.red,
                                                      behavior: SnackBarBehavior
                                                          .floating,
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              10,
                                                            ),
                                                      ),
                                                    ),
                                                  );
                                                }
                                              }
                                              setState(
                                                () => _editingInfo = false,
                                              );
                                            } else {
                                              // Store originals before entering edit mode
                                              _origName =
                                                  '${_firstNameCtrl.text} ${_lastNameCtrl.text}'
                                                      .trim();
                                              _origEmail = _emailCtrl.text
                                                  .trim();
                                              _origPhone = _phoneCtrl.text
                                                  .trim();
                                              _origCompany = _companyCtrl.text
                                                  .trim();
                                              setState(
                                                () => _editingInfo = true,
                                              );
                                            }
                                          },
                                          icon: Icon(
                                            _editingInfo
                                                ? Icons.check
                                                : Icons.edit_outlined,
                                            size: 15,
                                          ),
                                          label: Text(
                                            _editingInfo ? 'Save' : 'Edit',
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                          style: TextButton.styleFrom(
                                            foregroundColor: _red,
                                          ),
                                        ),
                                        if (_editingInfo)
                                          TextButton.icon(
                                            onPressed: () {
                                              // Restore originals
                                              final parts = _origName.split(
                                                ' ',
                                              );
                                              _firstNameCtrl.text =
                                                  parts.isNotEmpty
                                                  ? parts.first
                                                  : '';
                                              _lastNameCtrl.text =
                                                  parts.length > 1
                                                  ? parts.skip(1).join(' ')
                                                  : '';
                                              _emailCtrl.text = _origEmail;
                                              _phoneCtrl.text = _origPhone;
                                              _companyCtrl.text = _origCompany;
                                              setState(
                                                () => _editingInfo = false,
                                              );
                                            },
                                            icon: const Icon(
                                              Icons.close,
                                              size: 15,
                                              color: Color(0xFF718096),
                                            ),
                                            label: const Text(
                                              'Cancel',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Color(0xFF718096),
                                              ),
                                            ),
                                            style: TextButton.styleFrom(
                                              foregroundColor: const Color(
                                                0xFF718096,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              _editableTile(
                                Icons.person_outline,
                                'First Name',
                                _firstNameCtrl,
                              ),
                              _editableTile(
                                Icons.person_outline,
                                'Last Name',
                                _lastNameCtrl,
                              ),
                              _editableTile(
                                Icons.email_outlined,
                                'Email',
                                _emailCtrl,
                              ),
                              _editableTile(
                                Icons.phone_outlined,
                                'Phone Number',
                                _phoneCtrl,
                                keyboardType: TextInputType.phone,
                                inputFormatters: [PhilippinePhoneFormatter()],
                              ),
                              if (widget.role == UserRole.customer &&
                                  _companyCtrl.text.isNotEmpty)
                                _editableTile(
                                  Icons.business_outlined,
                                  'Company Name',
                                  _companyCtrl,
                                ),
                              _editableTile(
                                Icons.shield_outlined,
                                'Role',
                                _roleCtrl,
                                isLast: true,
                                readOnly: true,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ???? Settings ????
                        _sectionLabel('SETTINGS'),
                        const SizedBox(height: 8),
                        _actionCard([
                          _actionTile(
                            Icons.notifications_outlined,
                            'Notifications',
                            'Manage alerts',
                            () {
                              final alertRole = switch (widget.role) {
                                UserRole.admin => ManageAlertsRole.admin,
                                UserRole.staff => ManageAlertsRole.staff,
                                UserRole.customer => ManageAlertsRole.customer,
                              };
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      ManageAlertsScreen(role: alertRole),
                                ),
                              );
                            },
                          ),
                          _actionTile(
                            Icons.lock_outline,
                            'Change Password',
                            'Update credentials',
                            () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChangePasswordScreen(
                                    role: widget
                                        .role
                                        .name, // 'admin', 'staff', or 'customer'
                                  ),
                                ),
                              );
                            },
                          ),
                          if (widget.role == UserRole.admin)
                            _actionTile(
                              Icons.bug_report_outlined,
                              'Push Notification Status',
                              'Check OneSignal setup',
                              () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const OneSignalDebugScreen(),
                                  ),
                                );
                              },
                            ),
                          _actionTile(
                            Icons.help_outline,
                            'Help & Support',
                            'Get assistance',
                            () {
                              final helpRole = switch (widget.role) {
                                UserRole.admin => HelpSupportRole.admin,
                                UserRole.staff => HelpSupportRole.staff,
                                UserRole.customer => HelpSupportRole.customer,
                              };
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      HelpSupportScreen(role: helpRole),
                                ),
                              );
                            },
                            isLast: true,
                          ),
                        ]),
                        const SizedBox(height: 20),

                        // ???? Logout ????
                        SizedBox(
                          width: double.infinity,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFF004B5F),
                                  Color(0xFF006B7D),
                                  Color(0xFFEE152A),
                                ],
                                stops: [0.0, 0.35, 1.0],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: ElevatedButton.icon(
                              onPressed: _confirmLogout,
                              icon: const Icon(Icons.logout, size: 18),
                              label: const Text(
                                'Logout',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 15,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 0,
                                shadowColor: Colors.transparent,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ???? Policy Links ????
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const PrivacyPolicyScreen(),
                                ),
                              ),
                              child: const Text(
                                'Privacy Policy',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF718096),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const Text(
                              '  •  ',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFFa0aec0),
                              ),
                            ),
                            TextButton(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const TermsConditionsScreen(),
                                ),
                              ),
                              child: const Text(
                                'Terms & Conditions',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF718096),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ), // SliverToBoxAdapter
              ], // slivers
            ), // CustomScrollView
    );
  }

  Widget _sectionLabel(String label) => Align(
    alignment: Alignment.centerLeft,
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: Color(0xFF718096),
        letterSpacing: 0.8,
      ),
    ),
  );

  Widget _editableTile(
    IconData icon,
    String label,
    TextEditingController ctrl, {
    bool isLast = false,
    bool readOnly = false,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F4FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: const Color(0xFF004B5F)),
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
                    (_editingInfo && !readOnly)
                        ? TextField(
                            controller: ctrl,
                            keyboardType: keyboardType,
                            inputFormatters: inputFormatters,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1a202c),
                            ),
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 4),
                              border: UnderlineInputBorder(
                                borderSide: BorderSide(
                                  color: Color(0xFFE8001C),
                                ),
                              ),
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                  color: Color(0xFFE8001C),
                                ),
                              ),
                              focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                  color: Color(0xFFE8001C),
                                  width: 1.5,
                                ),
                              ),
                            ),
                          )
                        : Text(
                            ctrl.text,
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
        ),
        if (!isLast) const Divider(height: 1, indent: 64),
      ],
    );
  }

  Widget _actionCard(List<Widget> tiles) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8),
      ],
    ),
    child: Column(children: tiles),
  );

  Widget _actionTile(
    IconData icon,
    String label,
    String sub,
    VoidCallback onTap, {
    bool isLast = false,
  }) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: isLast
              ? const BorderRadius.vertical(bottom: Radius.circular(14))
              : BorderRadius.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F4FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: const Color(0xFF004B5F)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1a202c),
                        ),
                      ),
                      Text(
                        sub,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF718096),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: Color(0xFF718096),
                ),
              ],
            ),
          ),
        ),
        if (!isLast) const Divider(height: 1, indent: 64),
      ],
    );
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Logout',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              AdminChatStore.clear();
              CustomerChatStore.clear();
              await FirebaseAuth.instance.signOut();
              if (mounted)
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (_) => false,
                );
            },
            child: const Text(
              'Yes',
              style: TextStyle(color: _red, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
