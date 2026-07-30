import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Debug screen to verify OneSignal integration status.
/// Shows: UID, subscription ID, opt-in status, Firestore sync status.
class OneSignalDebugScreen extends StatefulWidget {
  const OneSignalDebugScreen({super.key});

  @override
  State<OneSignalDebugScreen> createState() => _OneSignalDebugScreenState();
}

class _OneSignalDebugScreenState extends State<OneSignalDebugScreen> {
  static const _red = Color(0xFFE8001C);
  String _uid = '';
  String _subId = '';
  bool _optedIn = false;
  String _firestoreSubId = '';
  String _externalId = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    setState(() => _loading = true);
    
    // Get Firebase UID
    final user = FirebaseAuth.instance.currentUser;
    _uid = user?.uid ?? '(Not logged in)';

    if (kIsWeb) {
      setState(() {
        _loading = false;
        _subId = '(Web not supported)';
      });
      return;
    }

    // Get OneSignal subscription ID and opt-in status
    _subId = OneSignal.User.pushSubscription.id ?? '(Not assigned yet)';
    _optedIn = OneSignal.User.pushSubscription.optedIn ?? false;

    // Get external ID (should match Firebase UID) — API varies by SDK version
    try {
      // onesignal_flutter >= 5.x stores external_id via login(), readable from aliases
      _externalId = _uid; // After OneSignal.login(uid), external_id == uid
    } catch (_) {
      _externalId = '(Not available)';
    }

    // Get what's saved in Firestore
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        _firestoreSubId = doc.data()?['oneSignalId'] as String? ?? '(Not saved)';
      } catch (e) {
        _firestoreSubId = 'Error: $e';
      }
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _requestPermission() async {
    if (kIsWeb) return;
    final granted = await OneSignal.Notifications.requestPermission(true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(granted ? 'Permission granted' : 'Permission denied')),
    );
    await Future.delayed(const Duration(seconds: 2));
    _loadStatus();
  }

  Future<void> _optIn() async {
    if (kIsWeb) return;
    await OneSignal.User.pushSubscription.optIn();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Opted in — waiting for subscription ID...')),
    );
    await Future.delayed(const Duration(seconds: 3));
    _loadStatus();
  }

  Future<void> _forceLogin() async {
    if (kIsWeb) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not logged in')),
      );
      return;
    }
    OneSignal.login(user.uid);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('OneSignal.login(${user.uid})')),
    );
    await Future.delayed(const Duration(seconds: 2));
    _loadStatus();
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: _red,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('OneSignal Debug',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadStatus,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Status overview card
                  _buildStatusCard(),
                  const SizedBox(height: 16),
                  // Details
                  _buildDetailCard('Firebase UID', _uid),
                  const SizedBox(height: 12),
                  _buildDetailCard('OneSignal Subscription ID', _subId),
                  const SizedBox(height: 12),
                  _buildDetailCard('OneSignal External ID', _externalId),
                  const SizedBox(height: 12),
                  _buildDetailCard('Firestore oneSignalId', _firestoreSubId),
                  const SizedBox(height: 12),
                  _buildDetailCard('Opt-in Status', _optedIn ? '✅ Opted In' : '❌ Not Opted In'),
                  const SizedBox(height: 24),
                  // Action buttons
                  ElevatedButton.icon(
                    onPressed: _requestPermission,
                    icon: const Icon(Icons.notifications_active),
                    label: const Text('Request Permission'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: _optIn,
                    icon: const Icon(Icons.check_circle),
                    label: const Text('Opt In to Push'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: _forceLogin,
                    icon: const Icon(Icons.login),
                    label: const Text('Force OneSignal.login()'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF003087),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildStatusCard() {
    final allGood = _uid != '(Not logged in)' &&
        _subId != '(Not assigned yet)' &&
        _subId != '(Web not supported)' &&
        _optedIn &&
        _firestoreSubId != '(Not saved)' &&
        _externalId == _uid;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: allGood ? const Color(0xFFf0fdf4) : const Color(0xFFfef2f2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: allGood ? const Color(0xFF86efac) : const Color(0xFFfca5a5),
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Icon(
            allGood ? Icons.check_circle_rounded : Icons.error_rounded,
            color: allGood ? const Color(0xFF16a34a) : _red,
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            allGood ? 'OneSignal is Configured' : 'Setup Incomplete',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: allGood ? const Color(0xFF16a34a) : _red,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            allGood
                ? 'Push notifications should work'
                : 'Check the fields below for issues',
            style: const TextStyle(fontSize: 12, color: Color(0xFF718096)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildDetailCard(String label, String value) {
    final isError = value.startsWith('(') || value.startsWith('Error:') || value == '❌ Not Opted In';
    return GestureDetector(
      onTap: () => _copyToClipboard(value),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFe2e8f0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF718096),
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                Icon(Icons.copy, size: 14, color: const Color(0xFFa0aec0)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isError ? _red : const Color(0xFF1a202c),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
