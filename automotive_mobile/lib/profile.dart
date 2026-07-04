import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'login.dart';
import 'change_password.dart';
import 'notifs_manageAlerts.dart';
import 'help_support.dart';
import 'privacy_policy.dart';
import 'terms_conditions.dart';

enum UserRole { customer, staff, admin }

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
  String _origName  = '';
  String _origEmail = '';

  final _nameCtrl  = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _roleCtrl  = TextEditingController();

  StreamSubscription<DocumentSnapshot>? _profileSub;

  @override
  void initState() {
    super.initState();
    _subscribeToProfile();
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _roleCtrl.dispose();
    super.dispose();
  }

  void _subscribeToProfile() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _profileSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((doc) {
      if (!mounted) return;
      final data = doc.data() ?? {};
      final role = (data['role'] as String? ?? '');

      // Don't overwrite fields the user is actively editing
      if (!_editingInfo) {
        setState(() {
          _nameCtrl.text  = data['name']  as String? ?? _nameCtrl.text;
          _emailCtrl.text = data['email'] as String? ?? _emailCtrl.text;
          _roleCtrl.text  = role.isEmpty ? _roleCtrl.text
              : role[0].toUpperCase() + role.substring(1);
          _photoUrl       = data['photoUrl'] as String? ?? _photoUrl;
          _loading        = false;
        });
      } else {
        // Still update role and photo even in edit mode (read-only fields)
        setState(() {
          _roleCtrl.text = role.isEmpty ? _roleCtrl.text
              : role[0].toUpperCase() + role.substring(1);
          _photoUrl      = data['photoUrl'] as String? ?? _photoUrl;
          _loading       = false;
        });
      }
    }, onError: (e) {
      if (mounted) setState(() => _loading = false);
    });
  }

  Future<void> _saveUserData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final newName  = _nameCtrl.text.trim();
    final newEmail = _emailCtrl.text.trim();
    final db = FirebaseFirestore.instance;

    await db.collection('users').doc(uid).update({
      'name': newName,
      'email': newEmail,
    });

    // Update owner field on all vehicles belonging to this customer
    if (widget.role == UserRole.customer && _origName.isNotEmpty && _origName.toLowerCase() != newName.toLowerCase()) {
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
    _origName = newName; // keep in sync after save
  }

  String get _initials {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return '?';
    final parts = name.split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name[0].toUpperCase();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;
    final file = File(picked.path);
    setState(() => _avatarImage = file);

    // Upload to Firebase Storage
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final ref = FirebaseStorage.instance.ref().child('avatars/$uid.jpg');
      await ref.putFile(file);
      final url = await ref.getDownloadURL();
      await FirebaseFirestore.instance.collection('users').doc(uid).update({'photoUrl': url});
      if (mounted) setState(() => _photoUrl = url);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isStandalone = widget.role != UserRole.customer;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: _red,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Profile',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        leading: isStandalone
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
        automaticallyImplyLeading: isStandalone,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(children: [
                // ── Hero header ──
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 36, 20, 32),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_red, Color(0xFFC41E3A)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(children: [
                    GestureDetector(
                      onTap: null,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 12)],
                        ),
                        child: CircleAvatar(
                          radius: 44,
                          backgroundColor: Colors.white24,
                          backgroundImage: _photoUrl != null
                              ? NetworkImage(_photoUrl!)
                              : null,
                          child: _photoUrl == null
                              ? Text(_initials, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold))
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(_nameCtrl.text,
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20)),
                      child: Text(_roleCtrl.text, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ),

                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    // ── Account Info ──
                    _sectionLabel('ACCOUNT INFORMATION'),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
                      child: Column(children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            const Text('Info', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF718096))),
                            Row(children: [
                            TextButton.icon(
                              onPressed: () async {
                                if (_editingInfo) {
                                  try {
                                    await _saveUserData();
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                        content: const Row(children: [
                                          Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
                                          SizedBox(width: 8),
                                          Text('Profile updated successfully!'),
                                        ]),
                                        backgroundColor: Colors.green,
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ));
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                        content: Text('Error: $e'),
                                        backgroundColor: Colors.red,
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ));
                                    }
                                  }
                                  setState(() => _editingInfo = false);
                                } else {
                                  // Store originals before entering edit mode
                                  _origName  = _nameCtrl.text.trim();
                                  _origEmail = _emailCtrl.text.trim();
                                  setState(() => _editingInfo = true);
                                }
                              },
                              icon: Icon(_editingInfo ? Icons.check : Icons.edit_outlined, size: 15),
                              label: Text(_editingInfo ? 'Save' : 'Edit', style: const TextStyle(fontSize: 12)),
                              style: TextButton.styleFrom(foregroundColor: _red),
                            ),
                            if (_editingInfo)
                              TextButton.icon(
                                onPressed: () {
                                  // Restore originals
                                  _nameCtrl.text  = _origName;
                                  _emailCtrl.text = _origEmail;
                                  setState(() => _editingInfo = false);
                                },
                                icon: const Icon(Icons.close, size: 15, color: Color(0xFF718096)),
                                label: const Text('Cancel', style: TextStyle(fontSize: 12, color: Color(0xFF718096))),
                                style: TextButton.styleFrom(foregroundColor: const Color(0xFF718096)),
                              ),
                            ]),
                          ]),
                        ),
                        _editableTile(Icons.person_outline, 'Full Name', _nameCtrl),
                        _editableTile(Icons.email_outlined, 'Email', _emailCtrl),
                        _editableTile(Icons.shield_outlined, 'Role', _roleCtrl, isLast: true, readOnly: true),
                      ]),
                    ),
                    const SizedBox(height: 16),

                    // ── Settings ──
                    _sectionLabel('SETTINGS'),
                    const SizedBox(height: 8),
                    _actionCard([
                      _actionTile(Icons.notifications_outlined, 'Notifications', 'Manage alerts', () {
                        final alertRole = switch (widget.role) {
                          UserRole.admin    => ManageAlertsRole.admin,
                          UserRole.staff    => ManageAlertsRole.staff,
                          UserRole.customer => ManageAlertsRole.customer,
                        };
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => ManageAlertsScreen(role: alertRole)));
                      }),
                      _actionTile(Icons.lock_outline, 'Change Password', 'Update credentials', () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => ChangePasswordScreen(
                          role: widget.role.name, // 'admin', 'staff', or 'customer'
                        )));
                      }),
                      _actionTile(Icons.help_outline, 'Help & Support', 'Get assistance', () {
                        final helpRole = switch (widget.role) {
                          UserRole.admin    => HelpSupportRole.admin,
                          UserRole.staff    => HelpSupportRole.staff,
                          UserRole.customer => HelpSupportRole.customer,
                        };
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => HelpSupportScreen(role: helpRole)));
                      }, isLast: true),
                    ]),
                    const SizedBox(height: 20),

                    // ── Logout ──
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _confirmLogout,
                        icon: const Icon(Icons.logout, size: 18),
                        label: const Text('Logout', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _red, foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // ── Policy Links ──
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen())),
                          child: const Text('Privacy Policy',
                            style: TextStyle(fontSize: 12, color: Color(0xFF718096), fontWeight: FontWeight.w600)),
                        ),
                        const Text('  •  ', style: TextStyle(fontSize: 12, color: Color(0xFFa0aec0))),
                        TextButton(
                          onPressed: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const TermsConditionsScreen())),
                          child: const Text('Terms & Conditions',
                            style: TextStyle(fontSize: 12, color: Color(0xFF718096), fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const SizedBox(height: 8),
                  ]),
                ),
              ]),
            ),
    );
  }

  Widget _sectionLabel(String label) => Align(
    alignment: Alignment.centerLeft,
    child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF718096), letterSpacing: 0.8)),
  );

  Widget _editableTile(IconData icon, String label, TextEditingController ctrl, {bool isLast = false, bool readOnly = false}) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Container(width: 36, height: 36,
            decoration: BoxDecoration(color: const Color(0xFFF0F4FF), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: _red)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
            (_editingInfo && !readOnly)
                ? TextField(controller: ctrl,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1a202c)),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 4),
                      border: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFE8001C))),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFE8001C))),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFE8001C), width: 1.5)),
                    ))
                : Text(ctrl.text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1a202c))),
          ])),
        ]),
      ),
      if (!isLast) const Divider(height: 1, indent: 64),
    ]);
  }

  Widget _actionCard(List<Widget> tiles) => Container(
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
    child: Column(children: tiles),
  );

  Widget _actionTile(IconData icon, String label, String sub, VoidCallback onTap, {bool isLast = false}) {
    return Column(children: [
      InkWell(
        onTap: onTap,
        borderRadius: isLast ? const BorderRadius.vertical(bottom: Radius.circular(14)) : BorderRadius.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(children: [
            Container(width: 36, height: 36,
              decoration: BoxDecoration(color: const Color(0xFFF0F4FF), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 18, color: _blue)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1a202c))),
              Text(sub, style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
            ])),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFF718096)),
          ]),
        ),
      ),
      if (!isLast) const Divider(height: 1, indent: 64),
    ]);
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Logout', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (mounted) Navigator.pushAndRemoveUntil(context,
                MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
            },
            child: const Text('Logout', style: TextStyle(color: _red, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
