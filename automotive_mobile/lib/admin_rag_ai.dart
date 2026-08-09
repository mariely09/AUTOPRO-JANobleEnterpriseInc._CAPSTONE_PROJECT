import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_firestore/cloud_firestore.dart' as cloud_firestore;

// ─────────────────────────────────────────────────────────────────────────────
//  Base URL of the ai_assistant FastAPI service.
//
//  Default is the deployed Render backend.
//
//  Override at build time if needed:
//    flutter run --dart-define=AI_BACKEND_URL=https://your-render-url.onrender.com
// ─────────────────────────────────────────────────────────────────────────────
const _kAiBaseUrl = String.fromEnvironment(
  'AI_BACKEND_URL',
  defaultValue: 'https://caltex-autopro-capstone-project.onrender.com',
);

// ── Report types supported by the backend ────────────────────────────────────
const _kReportTypes = {
  'inventory':   'Inventory Report',
  'issuance':    'Issuance Report',
  'maintenance': 'Maintenance Report',
  'vehicles':    'Vehicle Fleet Report',
  'bookings':    'Service Bookings Report',
};

// ── Report intent keywords (mirrors Flask proxy logic) ───────────────────────
const _kReportTypeKeywords = {
  'inventory':   ['inventory', 'stock'],
  'issuance':    ['issuance', 'issued'],
  'maintenance': ['maintenance', 'service', 'repair'],
  'vehicles':    ['vehicle', 'fleet'],
  'bookings':    ['booking', 'appointment'],
};

String? _detectReportIntent(String message) {
  final lower = message.toLowerCase();
  final isReportRequest = RegExp(
    r'\b(generate|create|make|export|download|print)\b.*\b(report|pdf|excel)\b'
    r'|\b(pdf|excel)\s+report\b'
    r'|\breport\s+(pdf|excel)\b',
  ).hasMatch(lower);
  if (!isReportRequest) return null;

  for (final entry in _kReportTypeKeywords.entries) {
    for (final kw in entry.value) {
      if (lower.contains(kw)) return entry.key;
    }
  }
  return 'inventory'; // default
}

bool _isExcelRequest(String message) {
  final l = message.toLowerCase();
  return l.contains('excel') || l.contains('xlsx') || l.contains('spreadsheet');
}

/// Extract a month+year string from a user message.
/// Returns e.g. "March 2026", "June 2025", or null if not found.
String? _extractMonthFromMessage(String message) {
  final lower = message.toLowerCase();
  const monthNames = [
    'january','february','march','april','may','june',
    'july','august','september','october','november','december',
  ];
  const monthAbbrs = [
    'jan','feb','mar','apr','may','jun',
    'jul','aug','sep','oct','nov','dec',
  ];

  // "this month" / "current month"
  if (RegExp(r'\b(this month|current month)\b', caseSensitive: false)
      .hasMatch(lower)) {
    final now = DateTime.now();
    return '${monthNames[now.month - 1][0].toUpperCase()}'
        '${monthNames[now.month - 1].substring(1)} ${now.year}';
  }
  // "last month"
  if (RegExp(r'\blast month\b', caseSensitive: false).hasMatch(lower)) {
    final now = DateTime.now();
    final prev = DateTime(now.year, now.month - 1);
    final name = monthNames[prev.month - 1];
    return '${name[0].toUpperCase()}${name.substring(1)} ${prev.year}';
  }
  // Full month name + year: "March 2026"
  final full = RegExp(
    r'\b(january|february|march|april|may|june|july|august|september|october|november|december)\s+(\d{4})\b',
    caseSensitive: false,
  ).firstMatch(lower);
  if (full != null) {
    final name = full.group(1)!;
    return '${name[0].toUpperCase()}${name.substring(1)} ${full.group(2)}';
  }
  // Abbreviated month + year: "Mar 2026"
  final abbr = RegExp(
    r'\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\s+(\d{4})\b',
    caseSensitive: false,
  ).firstMatch(lower);
  if (abbr != null) {
    final idx = monthAbbrs.indexOf(abbr.group(1)!.toLowerCase());
    if (idx >= 0) {
      final name = monthNames[idx];
      return '${name[0].toUpperCase()}${name.substring(1)} ${abbr.group(2)}';
    }
  }
  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
// Static chat store — survives page navigation (cleared on logout/refresh/delete)
// ─────────────────────────────────────────────────────────────────────────────
class AdminChatStore {
  static final List<_ChatMessage> messages = [];
  static String? sessionId;
  static bool rateLimited = false;
  static String resetIn = '';

  static void clear() {
    messages.clear();
    sessionId = null;
    rateLimited = false;
    resetIn = '';
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class AdminSmartReports extends StatefulWidget {
  const AdminSmartReports({super.key});

  @override
  // ignore: library_private_types_in_public_api
  State<AdminSmartReports> createState() => _AdminSmartReportsState();
}

class _AdminSmartReportsState extends State<AdminSmartReports> {
  static const _red  = Color(0xFFE8001C);
  static const _blue = Color(0xFF003087);

  final _inputCtrl  = TextEditingController();
  final _scrollCtrl = ScrollController();

  // Messages and session live in the static store — widget rebuild-safe
  List<_ChatMessage> get _messages => AdminChatStore.messages;
  String? get _sessionId => AdminChatStore.sessionId;
  set _sessionId(String? v) => AdminChatStore.sessionId = v;

  final List<Map<String, String>> _history = []; // legacy — kept for fallback only
  String _initials = 'AD';  // admin initials shown on user bubble

  bool _loading       = false;
  bool get _rateLimited => AdminChatStore.rateLimited;
  set _rateLimited(bool v) => AdminChatStore.rateLimited = v;
  String get _resetIn => AdminChatStore.resetIn;
  set _resetIn(String v) => AdminChatStore.resetIn = v;
  bool _backendOnline = true;

  @override
  void initState() {
    super.initState();
    _checkBackend(silent: true);
    _checkAiStatus();
    _loadInitials();
  }

  /// Checks the backend AI key status on startup.
  /// If at least one key is active (not rate-limited), clears any stale
  /// _rateLimited flag left over from a previous session.
  Future<void> _checkAiStatus() async {
    try {
      final r = await http
          .get(Uri.parse('$_kAiBaseUrl/ai-settings/status'))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body) as Map<String, dynamic>;
        final activeKeys = (data['active_keys'] as num?)?.toInt() ?? 0;
        if (activeKeys > 0 && mounted) {
          setState(() {
            _rateLimited = false;
            _resetIn = '';
          });
        }
      }
    } catch (_) {
      // Silently ignore — status check is best-effort
    }
  }

  Future<void> _loadInitials() async {
    try {
      final user = firebase_auth.FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final doc = await cloud_firestore.FirebaseFirestore.instance
          .collection('users').doc(user.uid).get();
      final name = (doc.data()?['name'] as String? ?? '').trim();
      if (name.isNotEmpty) {
        final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
        final ini = parts.length >= 2
            ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
            : parts[0][0].toUpperCase();
        if (mounted) setState(() => _initials = ini);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Backend health check ───────────────────────────────────────────────────
  // The backend is always deployed on Render. We do a silent health probe on
  // startup — if it responds, we mark online; if all attempts fail we show the
  // offline banner so the user can manually retry.

  Future<void> _checkBackend({bool silent = false}) async {
    // Only reset to offline if the caller explicitly requests it (manual retry)
    if (!silent && mounted) setState(() => _backendOnline = false);
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        final r = await http
            .get(Uri.parse('$_kAiBaseUrl/health'))
            .timeout(const Duration(seconds: 20));
        if (r.statusCode == 200) {
          if (mounted) setState(() => _backendOnline = true);
          return;
        }
      } catch (_) {
        // wait before retry (skip delay on last attempt)
        if (attempt < 3) await Future.delayed(const Duration(seconds: 5));
      }
    }
    // All attempts failed — only mark offline if this was a manual (non-silent) retry
    if (!silent && mounted) setState(() => _backendOnline = false);
  }

  // ── Scroll ─────────────────────────────────────────────────────────────────

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Chat send ──────────────────────────────────────────────────────────────

  Future<void> _sendQuery([String? preset]) async {
    final text = (preset ?? _inputCtrl.text).trim();
    if (text.isEmpty || _loading || _rateLimited) return;

    // ── Report intent? Handle separately ──────────────────────────────────
    final reportType = _detectReportIntent(text);
    if (reportType != null) {
      setState(() {
        _messages.add(_ChatMessage(role: 'user', text: text));
        _inputCtrl.clear();
      });
      _scrollToBottom();
      final isExcel = _isExcelRequest(text);
      final extractedMonth = _extractMonthFromMessage(text);
      _showReportConfirm(reportType, isExcel ? 'excel' : 'pdf',
          preselectedMonth: extractedMonth);
      return;
    }

    setState(() {
      _messages.add(_ChatMessage(role: 'user', text: text));
      _inputCtrl.clear();
      _loading = true;
    });
    _scrollToBottom();

    // session memory is handled server-side via _sessionId

    try {
      final resp = await http
          .post(
            Uri.parse('$_kAiBaseUrl/admin/chat'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'message':    text,
              'session_id': _sessionId,  // server-side memory key
            }),
          )
          .timeout(const Duration(seconds: 120));

      if (resp.statusCode == 200) {
        final data   = jsonDecode(resp.body) as Map<String, dynamic>;
        final reply  = (data['reply'] as String? ?? '').trim();
        final answer = reply.isNotEmpty ? reply : 'No response generated.';

        // Persist session_id for continuity across turns
        if (data['session_id'] != null) {
          _sessionId = data['session_id'] as String;
        }

        // Handle rate limit
        if (data['rate_limited'] == true) {
          final resetIn = data['reset_in'] as String? ?? 'some time';
          setState(() {
            _loading = false;
            _rateLimited = true;
            _resetIn = resetIn;
            _messages.add(_ChatMessage(
              role: 'ai',
              text: 'AI Unavailable\n\n'
                  'The AI service has reached its daily token limit (Groq free tier).\n\n'
                  'The limit resets in $resetIn.\n\n'
                  'You cannot send new messages until the quota resets automatically.',
              isRateLimit: true,
            ));
          });
          return;
        }

        setState(() {
          _loading = false;
          _messages.add(_ChatMessage(role: 'ai', text: answer));
        });
      } else {
        setState(() {
          _loading = false;
          _messages.add(_ChatMessage(
            role: 'ai',
            text: 'AI service error (${resp.statusCode}): ${_parseError(resp.body)}',
          ));
        });
      }
    } on http.ClientException catch (e) {
      setState(() {
        _loading = false;
        _messages.add(_ChatMessage(
          role: 'ai',
          text: 'Cannot reach the AI service.\n\n'
              'Please check your internet connection and try again.\n\n'
              'Error: $e',
        ));
      });
    } on Exception catch (e) {
      // Covers TimeoutException and other network errors
      if (e.toString().contains('TimeoutException') ||
          e.toString().contains('timed out')) {
        setState(() {
          _loading = false;
          _messages.add(_ChatMessage(
            role: 'ai',
            text: 'Request timed out.\n\nThe AI service did not respond in time. Please check your connection and try again.',
          ));
        });
      } else {
        setState(() {
          _loading = false;
          _messages.add(_ChatMessage(role: 'ai', text: 'Unexpected error: $e'));
        });
      }
    }
    _scrollToBottom();
  }

  String _parseError(String body) {
    try {
      final d = jsonDecode(body) as Map<String, dynamic>;
      return d['detail']?.toString() ?? d['error']?.toString() ?? body;
    } catch (_) {
      return body.length > 120 ? '${body.substring(0, 120)}…' : body;
    }
  }

  // ── Report generation ──────────────────────────────────────────────────────

  /// Shows a bottom sheet to confirm the report type/format then downloads it.
  /// For issuance reports, also shows an optional month picker.
  void _showReportConfirm(String reportType, String format,
      {String? preselectedMonth}) {
    final title = _kReportTypes[reportType] ?? 'Report';

    // Month filter applies to date-based reports
    const monthSupported = {'issuance', 'maintenance', 'bookings'};
    final supportsMonth = monthSupported.contains(reportType);

    // Month names / options
    const monthNames = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    final currentYear = DateTime.now().year;
    final monthOptions = <String>['All Months'];
    for (int y = currentYear; y >= currentYear - 1; y--) {
      for (int m = 12; m >= 1; m--) {
        monthOptions.add('${monthNames[m - 1]} $y');
      }
    }

    // Pre-select month extracted from the user message (if valid)
    String? selectedMonth = (preselectedMonth != null &&
            monthOptions.contains(preselectedMonth))
        ? preselectedMonth
        : null;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              24, 20, 24, 32 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            const Text('Download Report',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
                    color: Color(0xFF1a202c))),
            const SizedBox(height: 6),
            Text(title,
                style: const TextStyle(fontSize: 13, color: Color(0xFF718096))),

            // Month filter — for issuance, maintenance, and bookings
            if (supportsMonth) ...[
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Filter by Month (optional)',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFe2e8f0)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: selectedMonth ?? 'All Months',
                    items: monthOptions.map((m) => DropdownMenuItem(
                      value: m,
                      child: Text(m, style: const TextStyle(fontSize: 13)),
                    )).toList(),
                    onChanged: (v) => setSheet(() {
                      selectedMonth = (v == 'All Months') ? null : v;
                    }),
                  ),
                ),
              ),
              if (selectedMonth != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(children: [
                    const Icon(Icons.filter_alt_outlined,
                        size: 13, color: Color(0xFFE8001C)),
                    const SizedBox(width: 4),
                    Text(
                      'Showing records for $selectedMonth only',
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFFE8001C),
                          fontWeight: FontWeight.w500),
                    ),
                  ]),
                ),
            ],

            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: _reportFormatBtn(
                  icon: Icons.picture_as_pdf_outlined,
                  label: 'PDF',
                  subtitle: 'Branded report',
                  selected: format == 'pdf',
                  onTap: () {
                    Navigator.pop(ctx);
                    _downloadReport(reportType, 'pdf', month: selectedMonth);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _reportFormatBtn(
                  icon: Icons.table_chart_outlined,
                  label: 'Excel',
                  subtitle: 'Spreadsheet',
                  selected: format == 'excel',
                  onTap: () {
                    Navigator.pop(ctx);
                    _downloadReport(reportType, 'excel', month: selectedMonth);
                  },
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _reportFormatBtn({
    required IconData icon,
    required String label,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? _red.withValues(alpha: 0.06) : const Color(0xFFF7F8FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? _red : const Color(0xFFe2e8f0),
              width: selected ? 1.5 : 1),
        ),
        child: Column(children: [
          Icon(icon, size: 22, color: selected ? _red : const Color(0xFF4a5568)),
          const SizedBox(height: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: selected ? _red : const Color(0xFF1a202c))),
          const SizedBox(height: 2),
          Text(subtitle,
              style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
        ]),
      ),
    );
  }

  Future<void> _downloadReport(String reportType, String format,
      {String? month}) async {
    final typeName  = _kReportTypes[reportType] ?? reportType;
    final fmtLabel  = format.toUpperCase();
    final monthLabel = month != null ? ' ($month)' : '';

    // Show progress in chat
    setState(() {
      _messages.add(_ChatMessage(
          role: 'ai',
          text: 'Generating $typeName$monthLabel ($fmtLabel)…'));
      _loading = true;
    });
    _scrollToBottom();

    try {
      // Build URL — append month param when provided
      final uri = Uri.parse(
        '$_kAiBaseUrl/admin/report'
        '?report_type=$reportType'
        '&format=$format'
        '${month != null ? '&month=${Uri.encodeComponent(month)}' : ''}',
      );

      final resp = await http
          .post(uri, headers: {'Content-Type': 'application/json'})
          .timeout(const Duration(seconds: 120));

      if (resp.statusCode == 200) {
        final ext      = format == 'pdf' ? 'pdf' : 'xlsx';
        final safeName = '$reportType'
            '${month != null ? '_${month.replaceAll(' ', '_')}' : ''}'
            '_report.$ext';

        // Save to temp dir and open with system viewer
        final dir  = await getTemporaryDirectory();
        final file = File('${dir.path}/$safeName');
        await file.writeAsBytes(resp.bodyBytes);

        setState(() {
          _loading = false;
          _messages.removeLast(); // remove the "Generating…" message
          _messages.add(_ChatMessage(
            role: 'ai',
            text: '$typeName$monthLabel downloaded successfully.',
            reportFile: file,
            reportFormat: format,
            reportLabel: typeName,
          ));
        });
        _scrollToBottom();

        // Auto-open the file
        await OpenFile.open(file.path);
      } else {
        throw Exception(
            'Server error ${resp.statusCode}: ${_parseError(resp.body)}');
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _messages.removeLast();
        _messages.add(_ChatMessage(
          role: 'ai',
          text: 'Failed to generate $typeName$monthLabel: $e',
        ));
      });
      _scrollToBottom();
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: _red,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Smart Reports AI',
            style: TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          // Online indicator dot
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Tooltip(
              message: _backendOnline ? 'AI Online' : 'AI Offline',
              child: Icon(Icons.circle,
                  size: 10,
                  color: _backendOnline ? Colors.greenAccent : Colors.orange),
            ),
          ),
          if (_messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.white),
              tooltip: 'Clear chat',
              onPressed: () {
                // Clear server-side session memory
                if (_sessionId != null) {
                  http.delete(Uri.parse('$_kAiBaseUrl/session/$_sessionId'))
                      .catchError((_) => http.Response('', 200));
                }
                setState(() {
                  AdminChatStore.clear();
                  _history.clear();
                });
              },
            ),
        ],
      ),
      body: Column(children: [
        // Offline banner
        if (!_backendOnline)
          Container(
            width: double.infinity,
            color: const Color(0xFFFFFBEB),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 16, color: Color(0xFF975A16)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Cannot reach AI backend. Check your connection or tap Retry.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF975A16)),
                ),
              ),
              GestureDetector(
                onTap: () => _checkBackend(),
                child: const Text('Retry',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF975A16))),
              ),
            ]),
          ),

        // Rate-limit banner
        if (_rateLimited)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFFFF7ED),
              border: Border(
                bottom: BorderSide(color: Color(0xFFFB923C), width: 2),
              ),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.block, size: 18, color: Color(0xFF9A3412)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AI unavailable — daily token limit reached',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF9A3412)),
                    ),
                    const SizedBox(height: 3),
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF9A3412), height: 1.5),
                        children: [
                          const TextSpan(text: 'Groq free-tier quota is exhausted. Resets in '),
                          TextSpan(
                            text: _resetIn,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const TextSpan(text: '. Chat is disabled until then.'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: _checkAiStatus,
                child: const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Text('Retry',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF9A3412))),
                ),
              ),
            ]),
          ),

        // Chat
        Expanded(
          child: _messages.isEmpty
              ? _buildWelcome()
              : ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(16),
                  itemCount: _messages.length + (_loading ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (_loading && i == _messages.length) {
                      return _buildTypingIndicator();
                    }
                    return _buildBubble(_messages[i]);
                  },
                ),
        ),

        // Input bar
        SafeArea(
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _inputCtrl,
                  maxLines: null,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendQuery(),
                  enabled: !_loading && !_rateLimited,
                  decoration: InputDecoration(
                    hintText: _rateLimited
                        ? 'AI unavailable — daily limit reached'
                        : 'Ask about fleet, inventory, reports…',
                    hintStyle: const TextStyle(
                        fontSize: 13, color: Color(0xFF718096)),
                    filled: true,
                    fillColor: const Color(0xFFF7F8FA),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _loading || _rateLimited ? null : _sendQuery,
                child: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: _loading || _rateLimited ? Colors.grey : _red,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.send, color: Colors.white, size: 18),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  // ── Welcome screen ─────────────────────────────────────────────────────────

  Widget _buildWelcome() {
    final suggestions = [
      'Show me the fleet summary',
      'Which vehicles have PMS overdue?',
      'What items are low in stock?',
      'What is the total repair cost this month?',
      'How many services are currently pending?',
      'List all registered vehicles',
      'Show all service bookings',
      'Generate inventory report as PDF',
      'Generate issuance report as Excel',
      'Generate maintenance report as PDF',
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Container(
          width: 60, height: 60,
          decoration: BoxDecoration(
              color: _blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(18)),
          child: const Icon(Icons.support_agent_rounded, color: _blue, size: 30),
        ),
        const SizedBox(height: 14),
        const Text(
          'Admin AI Assistant',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1a202c)),
        ),
        const SizedBox(height: 6),
        const Text(
          'Ask me anything about fleet, inventory, maintenance costs, or generate PDF/Excel reports.',
          style: TextStyle(fontSize: 13, color: Color(0xFF718096), height: 1.5),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        ...suggestions.map((s) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GestureDetector(
            onTap: () => _sendQuery(s),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: const Color(0xFFe2e8f0), width: 1.2),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4)],
              ),
              child: Text(
                s,
                style: const TextStyle(fontSize: 13, color: Color(0xFF9AA5B4)),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        )),
      ]),
    );
  }

  // ── Typing indicator ───────────────────────────────────────────────────────

  // ── Typing indicator — 3 bouncing dots (matches web design) ──────────────

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        _aiAvatar(),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: _aiBubbleDecoration(),
          child: const _BouncingDots(),
        ),
      ]),
    );
  }

  // ── Chat bubble ────────────────────────────────────────────────────────────

  Widget _buildBubble(_ChatMessage msg) {
    // ── User bubble ──────────────────────────────────────────
    if (msg.role == 'user') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: Container(
                constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.72),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE8001C), Color(0xFFC41E3A)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: const BorderRadius.only(
                    topLeft:     Radius.circular(14),
                    topRight:    Radius.circular(4),
                    bottomLeft:  Radius.circular(14),
                    bottomRight: Radius.circular(14),
                  ),
                  boxShadow: [BoxShadow(
                    color: const Color(0xFFE8001C).withValues(alpha: 0.22),
                    blurRadius: 6)],
                ),
                child: Text(msg.text ?? '',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 13, height: 1.6)),
              ),
            ),
            const SizedBox(width: 8),
            _userAvatar(),
          ],
        ),
      );
    }

    // ── Rate-limit card ──────────────────────────────────────
    if (msg.isRateLimit) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _aiAvatar(),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.80),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: const BorderRadius.only(
                  topLeft:     Radius.circular(4),
                  topRight:    Radius.circular(14),
                  bottomLeft:  Radius.circular(14),
                  bottomRight: Radius.circular(14),
                ),
                border: Border.all(color: const Color(0xFFFB923C), width: 1.5),
                boxShadow: [BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 9),
                  decoration: const BoxDecoration(
                    color: Color(0xFFEA580C),
                    borderRadius: BorderRadius.only(
                      topLeft:  Radius.circular(2),
                      topRight: Radius.circular(13)),
                  ),
                  child: const Row(children: [
                    Icon(Icons.block, color: Colors.white, size: 14),
                    SizedBox(width: 8),
                    Text('AI Service Unavailable',
                        style: TextStyle(color: Colors.white,
                            fontWeight: FontWeight.bold, fontSize: 12)),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: RichText(text: TextSpan(
                    style: const TextStyle(fontSize: 12.5,
                        color: Color(0xFF9A3412), height: 1.55),
                    children: [
                      const TextSpan(
                          text: 'Daily token limit reached.\n\n',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const TextSpan(text: 'Resets in '),
                      TextSpan(
                        text: _resetIn.isNotEmpty ? _resetIn : 'some time',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                      const TextSpan(
                          text: '. You cannot send messages until then.'),
                    ],
                  )),
                ),
              ]),
            ),
          ),
        ]),
      );
    }

    // ── Normal AI bubble ─────────────────────────────────────
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        _aiAvatar(),
        const SizedBox(width: 8),
        Flexible(
          child: Container(
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.76),
            padding: const EdgeInsets.symmetric(
                horizontal: 13, vertical: 10),
            decoration: _aiBubbleDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  msg.text ?? '',
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF1a202c), height: 1.6),
                ),
                if (msg.reportFile != null) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    _actionBtn(Icons.folder_open_outlined, 'Open', const Color(0xFFE8001C), () async {
                      await OpenFile.open(msg.reportFile!.path);
                    }),
                    const SizedBox(width: 8),
                    _actionBtn(Icons.share_outlined, 'Share', const Color(0xFF003087), () async {
                      await Printing.sharePdf(
                        bytes: await msg.reportFile!.readAsBytes(),
                        filename: msg.reportFile!.path.split('/').last,
                      );
                    }),
                  ]),
                ],
                if (msg.reportFile == null &&
                    (msg.text ?? '').length > 80) ...[
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 6,
                      children: [
                    for (final entry in _kReportTypes.entries)
                      _tinyChip(
                        '${entry.value.replaceAll(' Report', '')} PDF',
                        () => _downloadReport(entry.key, 'pdf', month: null),
                      ),
                  ]),
                ],
              ],
            ),
          ),
        ),
      ]),
    );
  }

  // ── Avatar helpers ─────────────────────────────────────────────────────────

  Widget _aiAvatar() => Container(
    width: 30, height: 30,
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [Color(0xFFE8001C), Color(0xFFC41E3A)],
        begin: Alignment.topLeft, end: Alignment.bottomRight),
      shape: BoxShape.circle),
    child: const Center(
      child: Icon(Icons.support_agent_rounded, color: Colors.white, size: 16)));

  Widget _userAvatar() => Container(
    width: 30, height: 30,
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [Color(0xFFE8001C), Color(0xFFC41E3A)],
        begin: Alignment.topLeft, end: Alignment.bottomRight),
      shape: BoxShape.circle),
    child: Center(
      child: Text(
        _initials,
        style: const TextStyle(
            color: Colors.white, fontSize: 10,
            fontWeight: FontWeight.w700))));

  BoxDecoration _aiBubbleDecoration() => BoxDecoration(
    color: Colors.white,
    borderRadius: const BorderRadius.only(
      topLeft:     Radius.circular(4),
      topRight:    Radius.circular(16),
      bottomLeft:  Radius.circular(16),
      bottomRight: Radius.circular(16),
    ),
    boxShadow: [BoxShadow(
      color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)]);

  Widget _actionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white, size: 13),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.bold,
                  color: Colors.white)),
        ]),
      ),
    );
  }

  Widget _tinyChip(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F8FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFe2e8f0)),
        ),
        child: Text(label,
            style: const TextStyle(
                fontSize: 10, color: Color(0xFF4a5568),
                fontWeight: FontWeight.w500)),
      ),
    );
  }
}

// ── Bouncing dots typing indicator ───────────────────────────────────────────

class _BouncingDots extends StatefulWidget {
  const _BouncingDots();
  @override
  State<_BouncingDots> createState() => _BouncingDotsState();
}

class _BouncingDotsState extends State<_BouncingDots>
    with TickerProviderStateMixin {
  late final List<AnimationController> _ctrls;
  late final List<Animation<double>> _anims;

  @override
  void initState() {
    super.initState();
    _ctrls = List.generate(3, (i) => AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true));
    _anims = List.generate(3, (i) => Tween<double>(begin: 0, end: -5)
        .animate(CurvedAnimation(
          parent: _ctrls[i],
          curve: Interval(i * 0.15, i * 0.15 + 0.6,
              curve: Curves.easeInOut))));
    // Stagger start
    for (int i = 1; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 135), () {
        if (mounted) _ctrls[i].forward();
      });
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (int i = 0; i < 3; i++) ...[
        if (i > 0) const SizedBox(width: 4),
        AnimatedBuilder(
          animation: _anims[i],
          builder: (_, _) => Transform.translate(
            offset: Offset(0, _anims[i].value),
            child: Container(
              width: 6, height: 6,
              decoration: const BoxDecoration(
                color: Color(0xFFA0AEC0),
                shape: BoxShape.circle),
            ),
          ),
        ),
      ],
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ChatMessage {
  final String role;
  final String? text;
  final File? reportFile;
  final String? reportFormat;
  final String? reportLabel;
  final bool isRateLimit;

  _ChatMessage({
    required this.role,
    this.text,
    this.reportFile,
    this.reportFormat,
    this.reportLabel,
    this.isRateLimit = false,
  });
}
