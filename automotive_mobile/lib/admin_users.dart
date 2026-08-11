import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;
import 'firebase_options.dart';

// ── EmailJS config (welcome + approval emails) ───────────────────────────
const _ejsServiceId         = 'service_i906b4o';
const _ejsPublicKey         = 'DqRrjCkUnf9w2L_sv';
const _ejsWelcomeTemplateId = 'template_ovrow3w';

// ── OneSignal credentials ──
const _kOneSignalAppId  = 'c4f82ac7-5340-4e7a-877d-1d38a6f6f8ea';
const _kOneSignalApiKey = 'os_v7_app_yt4cvr2f1hkhvh5ldu4k637i51snjeyuythen3fd61ae1yhnprpy6kbxvn9kjd1pqdhygsqmlrouas4kfuydft32nkgj5flbra3oo5q';

class AdminUsers extends StatefulWidget {
  const AdminUsers({super.key});

  @override
  State<AdminUsers> createState() => _AdminUsersState();
}

class _AdminUsersState extends State<AdminUsers> {
  static const _red = Color(0xFFE8001C);
  final _searchCtrl = TextEditingController();
  bool _searching = false;
  String _searchQuery = '';

  String _roleFilter = 'all'; // 'all', 'admin', 'staff', 'customer'
  String _statusFilter = 'all'; // 'all', 'Active', 'Inactive', 'Pending'
  String _sortBy = 'name-asc'; // 'name-asc', 'name-desc', 'email-asc'

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Color _roleColor(String role) {
    if (role == 'admin') return _red;
    if (role == 'staff') return const Color(0xFF003087);
    return Colors.green;
  }

  String _roleLabel(String role) =>
      role[0].toUpperCase() + role.substring(1);

  PopupMenuItem<String> _sortItem(String val, String label, IconData icon) {
    final active = _sortBy == val;
    return PopupMenuItem(
      value: val,
      child: Row(children: [
        Icon(icon, size: 16, color: active ? _red : const Color(0xFF718096)),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(fontWeight: active ? FontWeight.w700 : FontWeight.normal, color: active ? _red : const Color(0xFF1a202c))),
        if (active) ...[const Spacer(), const Icon(Icons.check, size: 14, color: _red)],
      ]),
    );
  }

  String _generateTempPassword() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
    final rand = Random.secure();
    final base = List.generate(8, (_) => chars[rand.nextInt(chars.length)]).join();
    return '${base}@1'; // ensures uppercase, lowercase, digit, special char
  }

  // ── HTML blocks injected via {{{dynamic_block}}} (triple-brace raw HTML) ──

  static String _welcomeBlock({
    required String toName,
    required String toEmail,
    required String tempPassword,
    required String roleLabel,
  }) => '''
<h1 style="margin:0 0 8px;text-align:center;font-size:22px;font-weight:800;color:#1a202c;">Welcome to AutoPro!</h1>
<p style="margin:0 0 26px;text-align:center;font-size:13px;color:#718096;line-height:1.6;">Hi <strong>$toName</strong>, your account has been created.<br/>Here are your login credentials:</p>
<div style="background:#f7f8fa;border:1px solid #e2e8f0;border-radius:12px;padding:20px 24px;margin-bottom:26px;"><table cellpadding="0" cellspacing="0" width="100%"><tr><td style="padding:8px 0;font-size:12px;color:#718096;font-weight:700;text-transform:uppercase;width:130px;">Email</td><td style="padding:8px 0;font-size:13px;font-weight:600;color:#1a202c;">$toEmail</td></tr><tr style="border-top:1px solid #e2e8f0;"><td style="padding:8px 0;font-size:12px;color:#718096;font-weight:700;text-transform:uppercase;">Temp Password</td><td style="padding:8px 0;"><span style="background:#E8001C;color:#fff;font-size:14px;font-weight:700;padding:5px 14px;border-radius:6px;letter-spacing:2px;">$tempPassword</span></td></tr><tr style="border-top:1px solid #e2e8f0;"><td style="padding:8px 0;font-size:12px;color:#718096;font-weight:700;text-transform:uppercase;">Role</td><td style="padding:8px 0;font-size:13px;font-weight:600;color:#1a202c;">$roleLabel</td></tr></table></div>
<table cellpadding="0" cellspacing="0" width="100%" style="margin-bottom:26px;"><tr><td style="padding:0 0 12px;"><div style="font-size:13px;font-weight:700;color:#1a202c;">What happens next?</div></td></tr><tr><td><table cellpadding="0" cellspacing="0" width="100%"><tr><td style="width:40px;vertical-align:top;padding:0 12px 14px 0;"><div style="width:36px;height:36px;background:#fff0f0;border-radius:10px;text-align:center;line-height:36px;font-size:18px;">&#x1F4F1;</div></td><td style="vertical-align:top;padding-bottom:14px;"><div style="font-size:13px;font-weight:700;color:#1a202c;margin-bottom:2px;">Open the app</div><div style="font-size:12px;color:#718096;line-height:1.5;">Download or open the <strong>AutoPro</strong> mobile app on your device.</div></td></tr><tr><td style="width:40px;vertical-align:top;padding:0 12px 14px 0;"><div style="width:36px;height:36px;background:#fff0f0;border-radius:10px;text-align:center;line-height:36px;font-size:18px;">&#x1F511;</div></td><td style="vertical-align:top;padding-bottom:14px;"><div style="font-size:13px;font-weight:700;color:#1a202c;margin-bottom:2px;">Sign in with your credentials</div><div style="font-size:12px;color:#718096;line-height:1.5;">Use the email and temporary password above to log in for the first time.</div></td></tr><tr><td style="width:40px;vertical-align:top;padding:0 12px 0 0;"><div style="width:36px;height:36px;background:#fff0f0;border-radius:10px;text-align:center;line-height:36px;font-size:18px;">&#x1F512;</div></td><td style="vertical-align:top;"><div style="font-size:13px;font-weight:700;color:#1a202c;margin-bottom:2px;">Set your own password</div><div style="font-size:12px;color:#718096;line-height:1.5;">You'll be prompted to change your password immediately after your first login.</div></td></tr></table></td></tr></table>''';

  static String _approvalBlock({
    required String toName,
    required String toEmail,
  }) => '''
<h1 style="margin:0 0 8px;text-align:center;font-size:22px;font-weight:800;color:#1a202c;">Account Approved!</h1>
<p style="margin:0 0 26px;text-align:center;font-size:13px;color:#718096;line-height:1.6;">Hi <strong>$toName</strong>, great news!<br/>Your AutoPro account has been approved by the administrator.</p>
<div style="background:#f0fff4;border:1px solid #9ae6b4;border-radius:12px;padding:24px;margin-bottom:26px;text-align:center;"><div style="font-size:28px;margin-bottom:10px;">&#x1F389;</div><p style="margin:0;font-size:15px;font-weight:700;color:#276749;">You\'re all set!</p><p style="margin:8px 0 0;font-size:13px;color:#2f855a;">Your account <strong>$toEmail</strong> is now active.<br/>You can sign in to the AutoPro app right now.</p></div>
<p style="margin:0 0 10px;font-size:13px;font-weight:700;color:#4a5568;">Getting started:</p>
<table cellpadding="0" cellspacing="0" width="100%"><tr><td style="padding:5px 0;"><span style="display:inline-block;width:22px;height:22px;background:#E8001C;border-radius:50%;color:#fff;font-size:11px;font-weight:700;text-align:center;line-height:22px;margin-right:10px;">1</span><span style="font-size:13px;color:#4a5568;">Open the <strong>AutoPro</strong> mobile app</span></td></tr><tr><td style="padding:5px 0;"><span style="display:inline-block;width:22px;height:22px;background:#E8001C;border-radius:50%;color:#fff;font-size:11px;font-weight:700;text-align:center;line-height:22px;margin-right:10px;">2</span><span style="font-size:13px;color:#4a5568;">Sign in with your registered email and password</span></td></tr><tr><td style="padding:5px 0;"><span style="display:inline-block;width:22px;height:22px;background:#E8001C;border-radius:50%;color:#fff;font-size:11px;font-weight:700;text-align:center;line-height:22px;margin-right:10px;">3</span><span style="font-size:13px;color:#4a5568;">Explore your dashboard and manage your vehicles &#x2713;</span></td></tr></table>''';

  Future<bool> _sendWelcomeEmail({
    required String toEmail,
    required String toName,
    required String tempPassword,
    required String role,
  }) async {
    final roleLabel = role[0].toUpperCase() + role.substring(1);
    try {
      final res = await http.post(
        Uri.parse('https://api.emailjs.com/api/v1.0/email/send'),
        headers: {
          'Content-Type': 'application/json',
          'origin': 'https://dashboard.emailjs.com',
        },
        body: jsonEncode({
          'service_id':  _ejsServiceId,
          'template_id': _ejsWelcomeTemplateId,
          'user_id':     _ejsPublicKey,
          'template_params': {
            'email':         toEmail,
            'name':          toName,
            'subject':       'Welcome to AutoPro',
            'dynamic_block': _welcomeBlock(
              toName:       toName,
              toEmail:      toEmail,
              tempPassword: tempPassword,
              roleLabel:    roleLabel,
            ),
          },
        }),
      );
      debugPrint('EmailJS welcome ${res.statusCode}: ${res.body}');
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('Welcome email error: $e');
      return false;
    }
  }

  Future<bool> _sendApprovalEmail({
    required String toEmail,
    required String toName,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('https://api.emailjs.com/api/v1.0/email/send'),
        headers: {
          'Content-Type': 'application/json',
          'origin': 'https://dashboard.emailjs.com',
        },
        body: jsonEncode({
          'service_id':  _ejsServiceId,
          'template_id': _ejsWelcomeTemplateId,
          'user_id':     _ejsPublicKey,
          'template_params': {
            'email':         toEmail,
            'name':          'Account Approved — $toName',
            'subject':       'Your AutoPro Account Has Been Approved',
            'dynamic_block': _approvalBlock(
              toName:  toName,
              toEmail: toEmail,
            ),
          },
        }),
      );
      debugPrint('EmailJS approval ${res.statusCode}: ${res.body}');
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('Approval email error: $e');
      return false;
    }
  }
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddUserModal(),
        backgroundColor: _red,
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
      appBar: AppBar(
        backgroundColor: _red,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: _searching
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Search users...',
                  hintStyle: TextStyle(color: Colors.white54),
                  border: InputBorder.none,
                ),
              )
            : const Text('User Management',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close : Icons.search, color: Colors.white),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) { _searchCtrl.clear(); _searchQuery = ''; }
            }),
          ),
          if (!_searching)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onSelected: (val) => setState(() => _sortBy = val),
              itemBuilder: (_) => [
                const PopupMenuItem(enabled: false, child: Text('Sort By', style: TextStyle(fontSize: 11, color: Color(0xFF718096), fontWeight: FontWeight.w700))),
                _sortItem('name-asc',  'Name A→Z',    Icons.sort_by_alpha),
                _sortItem('name-desc', 'Name Z→A',    Icons.sort_by_alpha),
                _sortItem('email-asc', 'Email A→Z',   Icons.email_outlined),
              ],
            ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final docs = snapshot.data?.docs ?? [];
          final users = docs.map((d) {
            final data = d.data() as Map<String, dynamic>;
            return {
              'uid': d.id,
              'name': data['name'] as String? ?? '—',
              'username': data['username'] as String? ?? '—',
              'email': data['email'] as String? ?? '—',
              'role': data['role'] as String? ?? '—',
              'status': data['status'] as String? ?? 'Active',
              'companyName': data['companyName'] as String? ?? '',
            };
          }).toList();

          final filtered = _searchQuery.isEmpty
              ? users
              : users.where((u) =>
                  u['name']!.toLowerCase().contains(_searchQuery) ||
                  u['username']!.toLowerCase().contains(_searchQuery) ||
                  u['role']!.toLowerCase().contains(_searchQuery) ||
                  u['companyName']!.toLowerCase().contains(_searchQuery)).toList();

          final total = users.length;
          final customers = users.where((u) => u['role'] == 'customer').length;
          final staff = users.where((u) => u['role'] == 'staff').length;
          final admins = users.where((u) => u['role'] == 'admin').length;

          // Apply role filter
          final afterRoleFilter = _roleFilter == 'all'
              ? filtered
              : filtered.where((u) => u['role'] == _roleFilter).toList();

          // Apply status filter
          final afterStatusFilter = _statusFilter == 'all'
              ? afterRoleFilter
              : afterRoleFilter.where((u) => (u['status'] as String? ?? '').toLowerCase() == _statusFilter.toLowerCase()).toList();

          return Column(children: [
              // ── Stat chips ──
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(children: [
                  _statChip('Total', '$total', Colors.blue, 'all'),
                  const SizedBox(width: 8),
                  _statChip('Admin', '$admins', _red, 'admin'),
                  const SizedBox(width: 8),
                  _statChip('Customer', '$customers', Colors.green, 'customer'),
                  const SizedBox(width: 8),
                  _statChip('Staff', '$staff', const Color(0xFF003087), 'staff'),
                ]),
              ),
              const SizedBox(height: 4),
              // ── Status filter chips ──
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Row(children: [
                  _statusChip('All', Colors.blue, 'all'),
                  const SizedBox(width: 8),
                  _statusChip('Active', Colors.green, 'Active'),
                  const SizedBox(width: 8),
                  _statusChip('Inactive', Colors.grey, 'Inactive'),
                ]),
              ),
              const SizedBox(height: 8),
              // ── Sort ──
              Builder(builder: (_) {
                afterStatusFilter.sort((a, b) {
                  switch (_sortBy) {
                    case 'name-desc': return (b['name'] ?? '').compareTo(a['name'] ?? '');
                    case 'email-asc': return (a['email'] ?? '').compareTo(b['email'] ?? '');
                    default: return (a['name'] ?? '').compareTo(b['name'] ?? '');
                  }
                });
                return const SizedBox.shrink();
              }),
              // ── User list ──
              Expanded(
                child: afterStatusFilter.isEmpty
                    ? const Center(child: Text('No users found.', style: TextStyle(color: Color(0xFF718096))))
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: afterStatusFilter.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _userCard(afterStatusFilter[i]),
                      ),
              ),
            ]);
        },
      ),
    );
  }

  Widget _statChip(String label, String value, Color color, String filter) {
    final isActive = _roleFilter == filter;
    final icon = label == 'Total'
        ? Icons.people_outline
        : Icons.person_outline;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _roleFilter = _roleFilter == filter ? 'all' : filter),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: isActive ? color.withOpacity(0.08) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isActive ? color : Colors.transparent, width: 1.5),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)]),
          child: Column(children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(height: 6),
            Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: const TextStyle(fontSize: 9, color: Color(0xFF718096))),
          ]),
        ),
      ),
    );
  }

  Widget _statusChip(String label, Color color, String filter) {
    final isActive = _statusFilter == filter;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _statusFilter = _statusFilter == filter ? 'all' : filter),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          decoration: BoxDecoration(
            color: isActive ? color.withOpacity(0.08) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isActive ? color : Colors.transparent, width: 1.5),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)]),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? color : const Color(0xFF718096),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _userCard(Map<String, String> u) {    final rc = _roleColor(u['role']!);
    return GestureDetector(
      onTap: () => _showUserDetails(u),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)]),
        child: Row(children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: rc.withOpacity(0.15),
            child: Text(u['name']![0].toUpperCase(),
              style: TextStyle(color: rc, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(u['name']!, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            Text(u['email']!, style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: rc.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
              child: Text(_roleLabel(u['role']!), style: TextStyle(fontSize: 10, color: rc, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 4),
            Text(u['status']!,
              style: TextStyle(fontSize: 10,
                color: u['status']?.toLowerCase() == 'active'
                    ? Colors.green
                    : u['status']?.toLowerCase() == 'pending'
                        ? Colors.orange
                        : const Color(0xFF718096),
                fontWeight: FontWeight.w500)),
          ]),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 18, color: Color(0xFF718096)),
            onSelected: (val) {
              if (val == 'edit') _showAddUserModal(user: u);
              if (val == 'toggle') _confirmDelete(u);
              if (val == 'archive') _archiveUser(u);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined, size: 16), SizedBox(width: 8), Text('Edit')])),
              // Only show Activate/Deactivate for non-pending users
              if ((u['status']?.toLowerCase() ?? '') != 'pending')
                PopupMenuItem(
                  value: 'toggle',
                  child: Row(children: [
                    Icon(
                      u['status']?.toLowerCase() == 'active'
                          ? Icons.block_outlined
                          : Icons.check_circle_outline,
                      size: 16,
                      color: u['status']?.toLowerCase() == 'active' ? Colors.orange : Colors.green,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      u['status']?.toLowerCase() == 'active' ? 'Deactivate' : 'Activate',
                      style: TextStyle(
                        color: u['status']?.toLowerCase() == 'active' ? Colors.orange : Colors.green,
                      ),
                    ),
                  ]),
                ),
              const PopupMenuItem(
                value: 'archive',
                child: Row(children: [
                  Icon(Icons.archive_outlined, size: 16, color: Colors.orange),
                  SizedBox(width: 8),
                  Text('Archive', style: TextStyle(color: Colors.orange)),
                ]),
              ),
            ],
          ),
        ]),
      ),
    );
  }

  Future<void> _approveUser(Map<String, String> u) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.check_circle_outline, color: Colors.green, size: 22),
          SizedBox(width: 8),
          Text('Approve Account'),
        ]),
        content: Text('Approve "${u['name']}"?\n\nThey will receive an email notification and can sign in immediately.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(u['uid'])
          .update({'status': 'Active'});

      // Send approval email — fire and forget, don't block the UI
      if (u['email']!.isNotEmpty) {
        _sendApprovalEmail(toEmail: u['email']!, toName: u['name']!).then((sent) {
          debugPrint(sent
              ? '✅ Approval email sent to ${u['email']}'
              : '⚠️ Approval email failed for ${u['email']}');
        });
      }

      // Push OneSignal notification to the user's device if they have one
      final userDoc = await FirebaseFirestore.instance
          .collection('users').doc(u['uid']).get();
      final subId = userDoc.data()?['oneSignalId'] as String?;
      if (subId != null && subId.isNotEmpty) {
        try {
          await http.post(
            Uri.parse('https://onesignal.com/api/v1/notifications'),
            headers: {
              'Authorization': 'Basic $_kOneSignalApiKey',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode({
              'app_id': _kOneSignalAppId,
              'include_subscription_ids': [subId],
              'headings': {'en': '✅ Account Approved!'},
              'contents': {'en': 'Your AutoPro account has been approved. You can now sign in.'},
              'data': {'type': 'account_approved'},
            }),
          );
        } catch (_) {}
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('${u['name']} approved! Notification sent.')),
          ]),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _rejectUser(Map<String, String> u) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.delete_outline, color: Colors.red, size: 22),
          SizedBox(width: 8),
          Text('Reject & Delete'),
        ]),
        content: Text('Reject "${u['name']}"?\n\nThis will permanently delete their account.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete Account'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final uid = u['uid']!;

      // 1. Delete Firestore document
      await FirebaseFirestore.instance.collection('users').doc(uid).delete();

      // 2. Delete Firebase Auth account via Flask Admin SDK endpoint
      try {
        await http.post(
          Uri.parse('http://10.0.2.2:5000/api/delete-user'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'uid': uid}),
        );
      } catch (authErr) {
        debugPrint('⚠️ Auth deletion failed (Firestore already deleted): $authErr');
      }

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Account rejected and deleted.'),
        backgroundColor: Colors.red,
      ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  Widget _pendingCard(Map<String, String> u) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: Colors.orange.withOpacity(0.15),
            child: Text(u['name']![0].toUpperCase(),
              style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(u['name']!, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            Text(u['email']!, style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text('Pending',
              style: TextStyle(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _rejectUser(u),
              icon: const Icon(Icons.close, size: 15, color: Colors.red),
              label: const Text('Reject', style: TextStyle(color: Colors.red, fontSize: 13)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _approveUser(u),
              icon: const Icon(Icons.check, size: 15),
              label: const Text('Approve', style: TextStyle(fontSize: 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ]),
      ]),
    );
  }

  void _showUserDetails(Map<String, String> u) {
    final rc = _roleColor(u['role']!);
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => DraggableScrollableSheet(
        expand: false, initialChildSize: 0.55, maxChildSize: 0.8,
        builder: (_, ctrl) => SingleChildScrollView(
          controller: ctrl,
          child: Column(children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              decoration: BoxDecoration(color: rc, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
              child: Row(children: [
                CircleAvatar(radius: 26, backgroundColor: Colors.white24,
                  child: Text(u['name']![0].toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold))),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(u['name']!, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ])),
                GestureDetector(onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close, color: Colors.white)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _detailRow('Full Name', u['name']!),
                _detailRow('Email', u['email']!),
                if ((u['companyName'] ?? '').isNotEmpty)
                  _detailRow('Company Name', u['companyName']!),
                _detailRow('Role', _roleLabel(u['role']!)),
                _detailRow('Status', u['status']!),
                const SizedBox(height: 16),
                SizedBox(width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () { Navigator.pop(context); _showAddUserModal(user: u); },
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Edit'),
                  )),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 110, child: Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF718096), fontWeight: FontWeight.w500))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1a202c)))),
      ]),
    );
  }

  void _showAddUserModal({Map<String, String>? user}) {
    final isEdit = user != null;
    // Split existing name into first/last for edit mode
    final existingName  = user?['name'] ?? '';
    final nameParts     = existingName.split(' ');
    final firstNameCtrl = TextEditingController(text: nameParts.isNotEmpty ? nameParts.first : '');
    final lastNameCtrl  = TextEditingController(text: nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '');
    final emailCtrl     = TextEditingController(text: user?['email'] ?? '');
    final companyNameCtrl = TextEditingController(text: user?['companyName'] ?? '');
    String selectedRole   = isEdit
        ? (user!['role']![0].toUpperCase() + user['role']!.substring(1))
        : 'Staff';
    String selectedStatus = user?['status'] ?? 'Active';
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          maxChildSize: 0.97,
          builder: (_, ctrl) => SingleChildScrollView(
            controller: ctrl,
            child: Column(children: [
              // ── Header ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                decoration: const BoxDecoration(
                    color: _red,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                child: Row(children: [
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(isEdit ? 'Edit User' : 'Add User',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                      if (!isEdit)
                        const Text(
                            'Login credentials will be sent to the user\'s email.',
                            style: TextStyle(color: Colors.white70, fontSize: 11)),
                    ],
                  )),
                  GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: const Icon(Icons.close, color: Colors.white)),
                ]),
              ),

              // ── Form ──
              Padding(
                padding: EdgeInsets.only(
                    left: 20, right: 20, top: 20,
                    bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
                child: Column(children: [
                  // First Name & Last Name side by side
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: firstNameCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                            labelText: 'First Name *',
                            border: OutlineInputBorder())),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: lastNameCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                            labelText: 'Last Name *',
                            border: OutlineInputBorder())),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                        labelText: 'Email *',
                        border: OutlineInputBorder())),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: selectedRole,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Role *',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14)),
                    items: const [
                      DropdownMenuItem(value: 'Admin',    child: Text('Admin')),
                      DropdownMenuItem(value: 'Staff',    child: Text('Staff')),
                      DropdownMenuItem(value: 'Customer', child: Text('Customer')),
                    ],
                    onChanged: (v) => setModal(() => selectedRole = v!),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  if (selectedRole.toLowerCase() == 'customer') ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: companyNameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                          labelText: 'Company Name',
                          border: OutlineInputBorder())),
                  ],
                  if (!isEdit) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FFF4),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: const Row(children: [
                        Icon(Icons.email_outlined, size: 16, color: Colors.green),
                        SizedBox(width: 8),
                        Expanded(child: Text(
                          'A temporary password will be auto-generated and sent to the user\'s email.',
                          style: TextStyle(fontSize: 11, color: Colors.green),
                        )),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 20),

                  // ── Buttons ──
                  Row(children: [
                    Expanded(child: OutlinedButton(
                      onPressed: saving ? null : () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _red,
                          foregroundColor: Colors.white),
                      onPressed: saving ? null : () async {
                        // Validate
                        final firstName = firstNameCtrl.text.trim();
                        final lastName  = lastNameCtrl.text.trim();
                        final fullName  = '$firstName $lastName'.trim();
                        if (firstName.isEmpty || lastName.isEmpty || emailCtrl.text.trim().isEmpty) {
                          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                            content: Text('Please fill in all required fields.'),
                            backgroundColor: Colors.orange));
                          return;
                        }

                        setModal(() => saving = true);

                        try {
                          if (isEdit) {
                            // ── Edit existing user ──
                            final newEmail = emailCtrl.text.trim();
                            final oldEmail = user!['email'] ?? '';
                            final emailChanged = newEmail != oldEmail;

                            await FirebaseFirestore.instance
                                .collection('users')
                                .doc(user['uid'])
                                .update({
                              'firstName': firstName,
                              'lastName':  lastName,
                              'name':      fullName,
                              'email':     newEmail,
                              'role':      selectedRole.toLowerCase(),
                              'status':    selectedStatus,
                              'companyName': selectedRole.toLowerCase() == 'customer' ? companyNameCtrl.text.trim() : '',
                            });

                            // If email changed and user hasn't logged in yet, resend credentials
                            if (emailChanged) {
                              final userDoc = await FirebaseFirestore.instance
                                  .collection('users').doc(user['uid']).get();
                              final mustChange = userDoc.data()?['mustChangePassword'] as bool? ?? false;
                              if (mustChange) {
                                final newTempPass = _generateTempPassword();
                                // Update Auth email + password via Flask
                                try {
                                  await http.post(
                                    Uri.parse('http://10.0.2.2:5000/api/update-user-email-password'),
                                    headers: {'Content-Type': 'application/json'},
                                    body: jsonEncode({
                                      'uid': user['uid'],
                                      'new_email': newEmail,
                                      'new_password': newTempPass,
                                    }),
                                  );
                                } catch (authErr) {
                                  debugPrint('⚠️ Auth update failed: $authErr');
                                }
                                // Send welcome email to new address
                                final sent = await _sendWelcomeEmail(
                                  toEmail:      newEmail,
                                  toName:       fullName,
                                  tempPassword: newTempPass,
                                  role:         selectedRole,
                                );
                                if (ctx.mounted) {
                                  Navigator.pop(ctx);
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                    content: Row(children: [
                                      const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
                                      const SizedBox(width: 8),
                                      Expanded(child: Text(sent
                                          ? 'User updated! New credentials sent to $newEmail.'
                                          : 'User updated! (Email failed — check server.)')),
                                    ]),
                                    backgroundColor: Colors.green,
                                    behavior: SnackBarBehavior.floating,
                                    duration: const Duration(seconds: 5),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ));
                                }
                                return;
                              }
                            }

                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: const Row(children: [
                                  Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
                                  SizedBox(width: 8),
                                  Text('User updated successfully!'),
                                ]),
                                backgroundColor: Colors.green,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ));
                            }
                          } else {
                            // ── Add new user ──
                            final tempPass = _generateTempPassword();

                            // Check if user already exists by email
                            final existingSnap = await FirebaseFirestore.instance
                                .collection('users')
                                .where('email', isEqualTo: emailCtrl.text.trim())
                                .limit(1)
                                .get();
                            
                            if (existingSnap.docs.isNotEmpty) {
                              if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text('A user with this email already exists.'),
                                  backgroundColor: Colors.orange));
                              setModal(() => saving = false);
                              return;
                            }

                            // Use a secondary Firebase app so the admin
                            // session is NOT replaced by the new user's session
                            FirebaseApp? secondaryApp;
                            try {
                              secondaryApp = await Firebase.initializeApp(
                                name: 'secondary_${DateTime.now().millisecondsSinceEpoch}',
                                options: DefaultFirebaseOptions.currentPlatform,
                              );
                              final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);

                              // 1. Create account in secondary app (doesn't touch admin session)
                              final cred = await secondaryAuth.createUserWithEmailAndPassword(
                                email: emailCtrl.text.trim(),
                                password: tempPass,
                              );

                              // 2. Save to Firestore using the new UID
                              await FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(cred.user!.uid)
                                  .set({
                                'uid':                cred.user!.uid,
                                'firstName':          firstName,
                                'lastName':           lastName,
                                'name':               fullName,
                                'email':              emailCtrl.text.trim(),
                                'role':               selectedRole.toLowerCase(),
                                'status':             selectedStatus,
                                'companyName':        selectedRole.toLowerCase() == 'customer' ? companyNameCtrl.text.trim() : '',
                                'mustChangePassword': true,
                                'createdAt':          FieldValue.serverTimestamp(),
                              });

                              // 3. Sign out from secondary app
                              await secondaryAuth.signOut();
                            } finally {
                              // Always delete the secondary app to free resources
                              await secondaryApp?.delete();
                            }

                            // 4. Send welcome email
                            bool sent = false;
                            String emailError = '';
                            try {
                              sent = await _sendWelcomeEmail(
                                toEmail:      emailCtrl.text.trim(),
                                toName:       fullName,
                                tempPassword: tempPass,
                                role:         selectedRole,
                              );
                            } catch (e) {
                              emailError = e.toString();
                              debugPrint('Email send caught: $e');
                            }

                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                              // Always show green success — user was created regardless of email
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Row(children: [
                                  const Icon(Icons.check_circle_outline,
                                      color: Colors.white, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(
                                      sent
                                        ? 'User added! Credentials sent to ${emailCtrl.text.trim()}.'
                                        : 'User added! Email failed: ${emailError.isNotEmpty ? emailError.substring(0, emailError.length.clamp(0, 120)) : "unknown error"}')),
                                ]),
                                backgroundColor: Colors.green,
                                behavior: SnackBarBehavior.floating,
                                duration: const Duration(seconds: 5),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ));
                            }
                          }
                        } on FirebaseAuthException catch (e) {
                          if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                                content: Text(e.code == 'email-already-in-use'
                                    ? 'This email is already registered. Use a different email.'
                                    : e.code == 'invalid-email'
                                        ? 'Invalid email address format.'
                                        : e.code == 'weak-password'
                                            ? 'Password is too weak.'
                                            : e.message ?? 'Firebase error'),
                                backgroundColor: Colors.red,
                                behavior: SnackBarBehavior.floating,
                                duration: const Duration(seconds: 4),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
                        } catch (e) {
                          if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                                content: Text('Error: $e'),
                                backgroundColor: Colors.red));
                        } finally {
                          if (ctx.mounted) setModal(() => saving = false);
                        }
                      },
                      child: saving
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(isEdit ? Icons.save_outlined : Icons.send_outlined, size: 16),
                              const SizedBox(width: 6),
                              Text(isEdit ? 'Update' : 'Add & Send'),
                            ]),
                    )),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _archiveUser(Map<String, String> u) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.archive_outlined, color: Colors.orange, size: 22),
          SizedBox(width: 8),
          Text('Archive User', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
        content: Text(
          'Are you sure you want to archive "${u['name']}"?\n\nThis will move the user to the archive.',
          style: const TextStyle(fontSize: 14, color: Color(0xFF4a5568)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF718096))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final uid = u['uid']!;
      final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!snap.exists) throw Exception('User not found.');
      final data = Map<String, dynamic>.from(snap.data()!);
      data['archivedAt'] = FieldValue.serverTimestamp();
      await FirebaseFirestore.instance
          .collection('archive')
          .doc('users')
          .collection('users')
          .doc(uid)
          .set(data);
      await FirebaseFirestore.instance.collection('users').doc(uid).delete();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.archive_outlined, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text('"${u['name']}" archived successfully.'),
        ]),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  void _confirmDelete(Map<String, String> u) {
    final isActive = (u['status'] ?? '').toLowerCase() == 'active';
    bool loading = false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(children: [
              Icon(isActive ? Icons.block_outlined : Icons.check_circle_outline,
                  color: isActive ? Colors.orange : Colors.green, size: 22),
              const SizedBox(width: 8),
              Text(isActive ? 'Deactivate User' : 'Activate User'),
            ]),
            content: Text(
              isActive
                ? 'Are you sure you want to deactivate "${u['name']}"?'
                : 'Are you sure you want to activate "${u['name']}"?',
            ),
            actions: [
              TextButton(
                onPressed: loading ? null : () => Navigator.pop(dialogCtx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isActive ? Colors.orange : Colors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: loading ? null : () async {
                  setDialogState(() => loading = true);
                  try {
                    final newStatus = isActive ? 'Inactive' : 'Active';
                    await FirebaseFirestore.instance
                        .collection('users')
                        .doc(u['uid'])
                        .update({'status': newStatus});

                    if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Row(children: [
                        Icon(
                          isActive ? Icons.block_outlined : Icons.check_circle_outline,
                          color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        Text('User ${isActive ? 'deactivated' : 'activated'} successfully.'),
                      ]),
                      backgroundColor: isActive ? Colors.orange : Colors.green,
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 3),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ));
                  } catch (e) {
                    setDialogState(() => loading = false);
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                  }
                },
                child: loading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(isActive ? 'Deactivate' : 'Activate'),
              ),
            ],
          );
        },
      ),
    );
  }
}
