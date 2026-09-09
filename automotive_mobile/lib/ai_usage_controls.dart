import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// AI Usage Controls (Profile → Settings → AI Usage Controls).
///
/// Admin-only screen. Reads/writes runtime AI settings through the website
/// backend's `/api/ai-settings` proxy, which verifies the caller's Firebase
/// ID token server-side (admin only).
///
/// Sections: Customer AI Access · Customer Token Limit · Token Reset ·
/// Usage Overview.
class AiUsageControlsScreen extends StatefulWidget {
  const AiUsageControlsScreen({super.key});

  @override
  State<AiUsageControlsScreen> createState() => _AiUsageControlsScreenState();
}

class _AiUsageControlsScreenState extends State<AiUsageControlsScreen> {
  static const _kFlaskBase = String.fromEnvironment(
    'FLASK_API_URL',
    defaultValue: 'https://caltex-autopro.onrender.com',
  );

  // ── Brand colours ─────────────────────────────────────────────────────────
  static const _red = Color(0xFFE8001C);
  static const _teal = Color(0xFF004B5F);
  static const _green = Color(0xFF16A34A);
  static const _orange = Color(0xFFDD6B20);
  static const _grey = Color(0xFF718096);
  static const _lightGrey = Color(0xFFF7F8FA);

  // ── Preset pause reasons ──────────────────────────────────────────────────
  static const _kPauseReasons = [
    'System maintenance in progress',
    'Temporary service interruption',
    'AI quota exceeded — service will resume shortly',
    'Scheduled downtime',
    'Other (specify below)',
  ];

  // ── Reset-hour label helpers ───────────────────────────────────────────────
  static const _kResetHourLabels = [
    '12:00 AM (Midnight)',
    '1:00 AM',
    '2:00 AM',
    '3:00 AM',
    '4:00 AM',
    '5:00 AM',
    '6:00 AM',
    '7:00 AM',
    '8:00 AM',
    '9:00 AM',
    '10:00 AM',
    '11:00 AM',
    '12:00 PM (Noon)',
    '1:00 PM',
    '2:00 PM',
    '3:00 PM',
    '4:00 PM',
    '5:00 PM',
    '6:00 PM',
    '7:00 PM',
    '8:00 PM',
    '9:00 PM',
    '10:00 PM',
    '11:00 PM',
  ];

  // ── Screen state ──────────────────────────────────────────────────────────
  bool _loading = true;
  String? _error;
  bool _saving = false;

  // Settings
  bool _customerAiEnabled = true;
  String _pauseReason = '';
  bool _limitEnabled = false;
  int _tokenLimit = 30000;
  int _tokenResetHour = 0; // 0–23 (Manila time)

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

  // ── Auth headers ──────────────────────────────────────────────────────────
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
      } catch (_) {}
    }
    return {'Content-Type': 'application/json'};
  }

  // ── Load settings ─────────────────────────────────────────────────────────
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
      if (resp.statusCode == 403) throw Exception('forbidden');
      if (resp.statusCode != 200) throw Exception('unreachable');

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final s = (data['settings'] ?? {}) as Map<String, dynamic>;
      final o = (data['overview'] ?? {}) as Map<String, dynamic>;

      if (!mounted) return;
      setState(() {
        _customerAiEnabled = (s['customer_ai_enabled'] as bool?) ?? true;
        _pauseReason = (s['pause_reason'] as String?) ?? '';
        _limitEnabled = ((s['customer_token_limit'] as num?) ?? 0) > 0;
        _tokenLimit = _limitEnabled
            ? (s['customer_token_limit'] as num).toInt()
            : 30000;
        _limitCtrl.text = '$_tokenLimit';

        // token_reset_hour may come from settings or overview
        final rawHour =
            s['token_reset_hour'] ?? o['token_reset_hour'] ?? 0;
        _tokenResetHour =
            ((rawHour as num?)?.toInt() ?? 0).clamp(0, 23);

        _tokensUsed =
            ((o['customer_tokens_used'] as num?) ?? 0).toInt();
        _effLimit =
            ((o['customer_token_limit'] as num?) ?? 0).toInt();
        _customersAtLimit =
            ((o['customers_at_limit'] as num?) ?? 0).toInt();
        _aiStatus =
            (o['customer_ai_status'] as String?) ?? 'Active';
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

  // ── Save settings ─────────────────────────────────────────────────────────
  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    final payload = {
      'customer_ai_enabled': _customerAiEnabled,
      'pause_reason': _customerAiEnabled ? '' : _pauseReason,
      'customer_token_limit': _limitEnabled ? _tokenLimit : 0,
      'token_reset_hour': _tokenResetHour,
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
          const SnackBar(
            content: Text('AI usage settings saved.'),
            backgroundColor: Color(0xFF16A34A),
          ),
        );
        await _load();
      } else if (resp.statusCode == 403) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Administrator access required to change AI settings.'),
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not save settings. Please try again.'),
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not save settings. Please try again.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Pause-reason modal ────────────────────────────────────────────────────
  Future<void> _showPauseModal() async {
    String selectedPreset = _kPauseReasons[0];
    final customCtrl = TextEditingController();
    bool isCustom = false;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Dialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          insetPadding: const EdgeInsets.symmetric(
              horizontal: 20, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Header ──────────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.fromLTRB(20, 18, 16, 16),
                  decoration: const BoxDecoration(
                    color: Color(0xFF004B5F),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.pause_circle_outline,
                          color: Colors.white, size: 22),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Pause AI Access',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        icon: const Icon(Icons.close,
                            color: Colors.white70, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                // ── Body ────────────────────────────────────────────
                Flexible(
                  child: SingleChildScrollView(
                    padding:
                        const EdgeInsets.fromLTRB(20, 16, 20, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Select a reason for pausing AI access. '
                          'This message will be shown to customers in the chat.',
                          style: TextStyle(
                            fontSize: 13,
                            color: _grey,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 14),
                        // Preset reason tiles
                        ...List.generate(_kPauseReasons.length,
                            (i) {
                          final reason = _kPauseReasons[i];
                          final picked = selectedPreset == reason;
                          return GestureDetector(
                            onTap: () => setModal(() {
                              selectedPreset = reason;
                              isCustom =
                                  reason == _kPauseReasons.last;
                            }),
                            child: Container(
                              margin: const EdgeInsets.only(
                                  bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 11),
                              decoration: BoxDecoration(
                                color: picked
                                    ? const Color(0xFFEFF6FF)
                                    : Colors.white,
                                borderRadius:
                                    BorderRadius.circular(12),
                                border: Border.all(
                                  color: picked
                                      ? const Color(0xFF3B82F6)
                                      : const Color(0xFFE2E8F0),
                                  width: picked ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    picked
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_off,
                                    size: 18,
                                    color: picked
                                        ? const Color(0xFF3B82F6)
                                        : _grey,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      reason,
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: picked
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                        color: const Color(
                                            0xFF1a202c),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                        // Custom reason field
                        if (isCustom) ...[
                          const SizedBox(height: 4),
                          TextField(
                            controller: customCtrl,
                            maxLines: 3,
                            maxLength: 200,
                            decoration: InputDecoration(
                              hintText: 'Describe the reason…',
                              hintStyle: const TextStyle(
                                  fontSize: 13, color: _grey),
                              contentPadding:
                                  const EdgeInsets.all(12),
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                    color: Color(0xFFD9E0E8)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                    color: Color(0xFF3B82F6)),
                              ),
                            ),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
                // ── Actions ─────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel',
                            style: TextStyle(
                                color: _grey, fontSize: 14)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () => Navigator.pop(ctx, true),
                        icon: const Icon(Icons.pause_circle,
                            size: 16),
                        label: const Text('Pause AI',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _orange,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 10),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmed == true) {
      final reason =
          isCustom ? customCtrl.text.trim() : selectedPreset;
      setState(() {
        _customerAiEnabled = false;
        _pauseReason = reason.isNotEmpty
            ? reason
            : 'AI access is temporarily paused.';
      });
      await _save();
    }
    customCtrl.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _lightGrey,
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'AI Usage Controls',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
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
              ? _buildError()
              : RefreshIndicator(
                  color: _red,
                  onRefresh: _load,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth > 600;
                      final hPad = wide ? 32.0 : 16.0;
                      final maxContentWidth = wide ? 720.0 : double.infinity;
                      return Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                              maxWidth: maxContentWidth),
                          child: ListView(
                            padding: EdgeInsets.symmetric(
                                horizontal: hPad, vertical: 16),
                            children: [
                              _crumb(),
                              const SizedBox(height: 14),

                              _card(
                                title: 'CUSTOMER AI ACCESS',
                                icon: Icons.smart_toy_outlined,
                                child: _aiAccessSection(),
                              ),

                              _card(
                                title: 'CUSTOMER TOKEN LIMIT',
                                icon: Icons.token_outlined,
                                child: _tokenLimitSection(),
                              ),

                              _card(
                                title: 'TOKEN RESET SCHEDULE',
                                icon: Icons.schedule_outlined,
                                child: _tokenResetSection(),
                              ),

                              _card(
                                title: 'USAGE OVERVIEW',
                                icon: Icons.bar_chart_outlined,
                                child: _overviewGrid(),
                              ),

                              const SizedBox(height: 4),
                              _saveButton(),
                              const SizedBox(height: 32),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  // ── Error state ───────────────────────────────────────────────────────────
  Widget _buildError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  color: Color(0xFFC53030), size: 44),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Color(0xFFC53030), fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      );

  // ── Section: Customer AI Access ───────────────────────────────────────────
  Widget _aiAccessSection() {
    final isPaused = !_customerAiEnabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Status badge + action button row
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Status badge
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isPaused
                    ? const Color(0xFFFFF7ED)
                    : const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isPaused
                      ? const Color(0xFFFB923C)
                      : const Color(0xFF86EFAC),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isPaused
                        ? Icons.pause_circle_filled
                        : Icons.check_circle,
                    size: 14,
                    color: isPaused ? _orange : _green,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    isPaused ? 'Paused' : 'Active',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: isPaused ? _orange : _green,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            // Pause AI / Allow AI button
            if (!isPaused)
              _actionButton(
                label: 'Pause AI',
                icon: Icons.pause_circle_outline,
                color: _orange,
                onTap: _showPauseModal,
              )
            else
              _actionButton(
                label: 'Allow AI',
                icon: Icons.play_circle_outline,
                color: _green,
                onTap: () async {
                  setState(() {
                    _customerAiEnabled = true;
                    _pauseReason = '';
                  });
                  await _save();
                },
              ),
          ],
        ),
        const SizedBox(height: 10),

        // Description
        Text(
          isPaused
              ? 'Customers are currently unable to access the AI Assistant.'
              : 'Customers can currently use the AI Assistant.',
          style: const TextStyle(
              fontSize: 13, color: _grey, height: 1.5),
        ),

        // Pause-reason notice box
        if (isPaused && _pauseReason.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFB923C)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(Icons.info_outline,
                      size: 16, color: _orange),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Notice shown to customers:',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _orange,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _pauseReason,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF92400E),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 4),
      ],
    );
  }

  // ── Section: Token Limit ──────────────────────────────────────────────────
  Widget _tokenLimitSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Toggle row
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Enable Customer Token Limit',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1a202c),
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Controls the maximum number of AI tokens a customer '
                    'can use during each quota period.',
                    style: TextStyle(
                        fontSize: 12, color: _grey, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Switch(
              value: _limitEnabled,
              onChanged: (v) => setState(() => _limitEnabled = v),
              activeColor: _green,
            ),
          ],
        ),

        // Token limit input (always rendered, dims when disabled)
        AnimatedOpacity(
          opacity: _limitEnabled ? 1.0 : 0.45,
          duration: const Duration(milliseconds: 200),
          child: Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Daily Token Limit per Customer',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1a202c),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _limitCtrl,
                  enabled: _limitEnabled,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly
                  ],
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    suffixText: 'tokens',
                    suffixStyle:
                        const TextStyle(fontSize: 12, color: _grey),
                    hintText: '30000',
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 13),
                    filled: true,
                    fillColor: _limitEnabled
                        ? Colors.white
                        : const Color(0xFFF1F4F8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: Color(0xFFD9E0E8)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: Color(0xFFD9E0E8)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: Color(0xFF3B82F6), width: 1.5),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                  onChanged: (v) =>
                      _tokenLimit = int.tryParse(v) ?? _tokenLimit,
                ),
                if (_limitEnabled) ...[
                  const SizedBox(height: 6),
                  const Text(
                    'Customers are blocked from sending messages after '
                    'reaching this limit.',
                    style: TextStyle(
                        fontSize: 11.5, color: _grey, height: 1.4),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  // ── Section: Token Reset Schedule ─────────────────────────────────────────
  Widget _tokenResetSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Frequency — fixed, informational
        _infoRow('Reset Frequency', 'Daily',
            icon: Icons.repeat_outlined),
        _divider(),

        // Reset Hour — editable dropdown
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.access_time_outlined,
                  size: 16, color: _grey),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Reset Time',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF1a202c),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Dropdown wrapped in a constrained box so it doesn't overflow
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 190),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFFD9E0E8)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _tokenResetHour,
                      isExpanded: true,
                      isDense: true,
                      icon: const Icon(Icons.expand_more,
                          size: 18, color: _grey),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1a202c),
                      ),
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _tokenResetHour = v);
                        }
                      },
                      items: List.generate(
                        24,
                        (h) => DropdownMenuItem(
                          value: h,
                          child: Text(
                            _kResetHourLabels[h],
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        _divider(),

        // Timezone — fixed, informational
        _infoRow('Timezone', 'Asia/Manila',
            icon: Icons.public_outlined),
        const SizedBox(height: 10),

        // Next-reset info box
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F9FF),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFBAE6FD)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(Icons.info_outline,
                    size: 15, color: Color(0xFF0369A1)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Next reset: $_nextReset\n'
                  'Select a different time above and tap Save Changes to update the reset schedule.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF0369A1),
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  // ── Overview grid ─────────────────────────────────────────────────────────
  Widget _overviewGrid() {
    final fmtLimit =
        _effLimit > 0 ? '$_effLimit / customer' : 'Default';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                  child: _stat('Customer Tokens Used', '$_tokensUsed',
                      null)),
              const SizedBox(width: 10),
              Expanded(
                  child:
                      _stat('Customer Token Limit', fmtLimit, null)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                  child: _stat(
                      'Customers at Limit',
                      '$_customersAtLimit',
                      _customersAtLimit > 0 ? _orange : null)),
              const SizedBox(width: 10),
              Expanded(
                  child: _stat(
                      'AI Status',
                      _aiStatus,
                      _aiStatus == 'Active' ? _green : _orange)),
            ],
          ),
        ],
      ),
    );
  }

  // ── Save button ───────────────────────────────────────────────────────────
  Widget _saveButton() => SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: _red,
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xFFFCA5A5),
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            elevation: 0,
          ),
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text(
                  'Save Changes',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
        ),
      );

  // ── UI helper widgets ─────────────────────────────────────────────────────

  Widget _crumb() => Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: const [
          Icon(Icons.verified_user_outlined, size: 14, color: _grey),
          SizedBox(width: 5),
          Text('Profile  /  Settings  /  ',
              style: TextStyle(fontSize: 12, color: _grey)),
          Text(
            'AI Usage Controls',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF1a202c),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );

  Widget _card({
    required String title,
    required IconData icon,
    required Widget child,
  }) =>
      Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEDF0F4)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 15, color: _teal),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      color: _teal,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            const Divider(height: 18, thickness: 0.8),
            child,
          ],
        ),
      );

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) =>
      Material(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _infoRow(String label, String value,
          {required IconData icon}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: _grey),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1a202c),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F4F8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF4A5568),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _divider() =>
      const Divider(height: 1, thickness: 0.6, color: Color(0xFFF1F4F8));

  Widget _stat(String label, String value, Color? valueColor) =>
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _lightGrey,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFEDF0F4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
                color: _grey,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: valueColor ?? const Color(0xFF1a202c),
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ],
        ),
      );
}
