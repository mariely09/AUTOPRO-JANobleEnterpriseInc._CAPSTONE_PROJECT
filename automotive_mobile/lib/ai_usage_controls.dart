import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// AI Usage Controls (Profile → Settings → AI Usage Controls).
///
/// Admin-only screen mirroring the web page of the same name. Reads/writes the
/// runtime AI settings through the website backend's `/api/ai-settings` proxy,
/// which verifies the caller's Firebase ID token server-side (admin only).
///
/// Sections: Customer AI Access · Customer Token Limit · Token Reset ·
/// Developer/Test Access · Usage Overview.
class AiUsageControlsScreen extends StatefulWidget {
  const AiUsageControlsScreen({super.key});

  @override
  State<AiUsageControlsScreen> createState() => _AiUsageControlsScreenState();
}

class _AiUsageControlsScreenState extends State<AiUsageControlsScreen> {
  // Website backend (Flask) that proxies to the AI service with admin checks.
  // Android emulator uses 10.0.2.2 to reach the host machine's Flask server.
  static const _kFlaskBase = String.fromEnvironment(
    'FLASK_API_URL',
    defaultValue: 'https://caltex-autopro.onrender.com',
  );

  static const _red = Color(0xFFE8001C);
  static const _teal = Color(0xFF004B5F);
  static const _green = Color(0xFF38a169);
  static const _orange = Color(0xFFdd6b20);
  static const _grey = Color(0xFF718096);

  bool _loading = true;
  String? _error;
  bool _saving = false;

  // Settings
  bool _customerAiEnabled = true;
  bool _limitEnabled = false;
  int _tokenLimit = 30000;
  bool _devAccessEnabled = false;
  bool _devBypassTokenLimit = false;
  bool _devAccessWhilePaused = false;

  // Usage overview
  int _tokensUsed = 0;
  int _effLimit = 0;
  int _customersAtLimit = 0;
  String _aiStatus = 'Active';
  String _nextReset = '—';

  final _limitCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _limitCtrl.dispose();
    super.dispose();
  }

  Future<Map<String, String>> _authHeaders() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final token = await user.getIdToken(true);
        if (token != null) {
          return {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          };
        }
      } catch (_) {/* fall through to unauthenticated headers */}
    }
    return {'Content-Type': 'application/json'};
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await http
          .get(
            Uri.parse('$_kFlaskBase/api/ai-settings'),
            headers: await _authHeaders(),
          )
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode == 403) {
        throw Exception('forbidden');
      }
      if (resp.statusCode != 200) {
        throw Exception('unreachable');
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final s = (data['settings'] ?? {}) as Map<String, dynamic>;
      final o = (data['overview'] ?? {}) as Map<String, dynamic>;

      if (!mounted) return;
      setState(() {
        _customerAiEnabled = (s['customer_ai_enabled'] as bool?) ?? true;
        _limitEnabled = ((s['customer_token_limit'] as num?) ?? 0) > 0;
        _tokenLimit = _limitEnabled
            ? (s['customer_token_limit'] as num).toInt()
            : 30000;
        _devAccessEnabled = (s['dev_access_enabled'] as bool?) ?? false;
        _devBypassTokenLimit =
            (s['dev_bypass_token_limit'] as bool?) ?? false;
        _devAccessWhilePaused =
            (s['dev_access_while_paused'] as bool?) ?? false;
        _limitCtrl.text = '$_tokenLimit';

        _tokensUsed = ((o['customer_tokens_used'] as num?) ?? 0).toInt();
        _effLimit = ((o['customer_token_limit'] as num?) ?? 0).toInt();
        _customersAtLimit =
            ((o['customers_at_limit'] as num?) ?? 0).toInt();
        _aiStatus = (o['customer_ai_status'] as String?) ?? 'Active';
        _nextReset = (o['next_reset'] as String?) ?? '—';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().contains('forbidden')
            ? 'You need administrator access to view AI Usage Controls.'
            : 'The AI service is unreachable right now. Please try again.';
      });
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    final payload = {
      'customer_ai_enabled': _customerAiEnabled,
      'customer_token_limit': _limitEnabled ? _tokenLimit : 0,
      'dev_access_enabled': _devAccessEnabled,
      'dev_bypass_token_limit': _devBypassTokenLimit,
      'dev_access_while_paused': _devAccessWhilePaused,
    };
    try {
      final resp = await http
          .put(
            Uri.parse('$_kFlaskBase/api/ai-settings'),
            headers: await _authHeaders(),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 30));
      if (!mounted) return;
      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI usage settings saved.')),
        );
        await _load(); // refresh overview with the new effective limit
      } else if (resp.statusCode == 403) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('You need administrator access to change AI settings.')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not save settings. Please try again.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not save settings. Please try again.')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('AI Usage Controls',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: _red),
                  SizedBox(height: 12),
                  Text('Loading AI settings…',
                      style: TextStyle(color: _grey)),
                ],
              ),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFFC53030)),
                    ),
                  ),
                )
              : RefreshIndicator(
                  color: _red,
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _crumb(),
                      const SizedBox(height: 12),
                      _card('CUSTOMER AI ACCESS', [
                        _toggleRow(
                          'Customer AI Status',
                          'Temporarily prevents customers from using the AI Assistant.',
                          value: _customerAiEnabled,
                          onChanged: (v) => setState(() => _customerAiEnabled = v),
                        ),
                      ]),
                      _card('CUSTOMER TOKEN LIMIT', [
                        _toggleRow(
                          'Enable Customer Token Limit',
                          'Controls the maximum number of AI tokens a customer can use during each quota period.',
                          value: _limitEnabled,
                          onChanged: (v) => setState(() => _limitEnabled = v),
                        ),
                        _limitFieldRow(),
                      ]),
                      _card('TOKEN RESET', [
                        _pickerRow('Reset Frequency', 'Daily', enabled: false),
                        _pickerRow('Reset Time', '12:00 AM', enabled: false),
                        _pickerRow('Timezone', 'Asia/Manila', enabled: false),
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Next reset: $_nextReset — reset schedule is fixed to midnight Philippine time.',
                            style: const TextStyle(
                                fontSize: 12, color: _grey, height: 1.4),
                          ),
                        ),
                      ]),
                      _card('DEVELOPER / TEST ACCESS', [
                        _toggleRow(
                          'Developer/Test Access',
                          'Allows authorized developer/test accounts to test the Customer AI without consuming the customer quota.',
                          value: _devAccessEnabled,
                          onChanged: (v) => setState(() => _devAccessEnabled = v),
                        ),
                        _toggleRow(
                          'Allow Developer/Test users to bypass customer token limit',
                          null,
                          value: _devBypassTokenLimit,
                          enabled: _devAccessEnabled,
                          onChanged: (v) =>
                              setState(() => _devBypassTokenLimit = v),
                        ),
                        _toggleRow(
                          'Allow Developer/Test users while Customer AI is paused',
                          null,
                          value: _devAccessWhilePaused,
                          enabled: _devAccessEnabled,
                          onChanged: (v) =>
                              setState(() => _devAccessWhilePaused = v),
                        ),
                      ]),
                      _card('USAGE OVERVIEW', [
                        _overviewGrid(),
                      ]),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _saving ? null : _save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          child: _saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Text('Save Changes',
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700)),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }

  // ── UI helpers ────────────────────────────────────────────────────────────

  Widget _crumb() => Row(
        children: const [
          Icon(Icons.verified_user_outlined, size: 16, color: _grey),
          SizedBox(width: 6),
          Text('Profile  /  Settings  /  ',
              style: TextStyle(fontSize: 12, color: _grey)),
          Text('AI Usage Controls',
              style: TextStyle(
                  fontSize: 12, color: Color(0xFF1a202c), fontWeight: FontWeight.w700)),
        ],
      );

  Widget _card(String title, List<Widget> rows) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEDF0F4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 2),
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.08,
                      color: _grey)),
            ),
            ...rows,
          ],
        ),
      );

  Widget _toggleRow(String label, String? sub,
      {required bool value,
      required ValueChanged<bool> onChanged,
      bool enabled = true}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1a202c))),
                if (sub != null) ...[
                  const SizedBox(height: 3),
                  Text(sub,
                      style: const TextStyle(
                          fontSize: 12, color: _grey, height: 1.4)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Transform.scale(
            scale: 0.9,
            child: Switch(
              value: value,
              onChanged: enabled ? onChanged : null,
              activeThumbColor: _green,
            ),
          ),
        ],
      ),
    );
  }

  Widget _limitFieldRow() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            const Expanded(
              child: Text('Daily Customer Token Limit',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1a202c))),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 130,
              child: TextField(
                controller: _limitCtrl,
                enabled: _limitEnabled,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600),
                decoration: const InputDecoration(
                  suffixText: 'tokens',
                  suffixStyle: TextStyle(fontSize: 11, color: _grey),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFFD9E0E8))),
                ),
                onChanged: (v) =>
                    _tokenLimit = int.tryParse(v) ?? _tokenLimit,
              ),
            ),
          ],
        ),
      );

  Widget _pickerRow(String label, String value, {required bool enabled}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1a202c))),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: enabled ? Colors.white : const Color(0xFFF1F4F8),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFD9E0E8)),
              ),
              child: Text(value,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: enabled
                          ? const Color(0xFF1a202c)
                          : const Color(0xFFA0AEC0))),
            ),
          ],
        ),
      );

  Widget _overviewGrid() {
    String fmtLimit = _effLimit > 0 ? '$_effLimit / customer' : 'Default';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _stat('Customer Tokens Used', '$_tokensUsed', null)),
              const SizedBox(width: 10),
              Expanded(child: _stat('Customer Token Limit', fmtLimit, null)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                  child: _stat('Customers at Limit', '$_customersAtLimit',
                      _customersAtLimit > 0 ? _orange : null)),
              const SizedBox(width: 10),
              Expanded(
                  child: _stat('Customer AI Status', _aiStatus,
                      _aiStatus == 'Active' ? _green : _orange)),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Next reset: $_nextReset',
                style: const TextStyle(fontSize: 12, color: _grey)),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color? valueColor) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F8FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFEDF0F4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(),
                style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.05,
                    color: _grey)),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: valueColor ?? const Color(0xFF1a202c))),
          ],
        ),
      );
}
