import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  'inventory': 'Inventory Report',
  'issuance': 'Issuance Report',
  'maintenance': 'Maintenance Report',
  'vehicles': 'Vehicle Fleet Report',
  'bookings': 'Service Bookings Report',
};

// ── Report intent keywords (mirrors Flask proxy logic) ───────────────────────
const _kReportTypeKeywords = {
  'inventory': ['inventory', 'stock'],
  'issuance': ['issuance', 'issued'],
  'maintenance': ['maintenance', 'service', 'repair'],
  'vehicles': ['vehicle', 'fleet'],
  'bookings': ['booking', 'appointment'],
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
    'january',
    'february',
    'march',
    'april',
    'may',
    'june',
    'july',
    'august',
    'september',
    'october',
    'november',
    'december',
  ];
  const monthAbbrs = [
    'jan',
    'feb',
    'mar',
    'apr',
    'may',
    'jun',
    'jul',
    'aug',
    'sep',
    'oct',
    'nov',
    'dec',
  ];

  // "this month" / "current month"
  if (RegExp(
    r'\b(this month|current month)\b',
    caseSensitive: false,
  ).hasMatch(lower)) {
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
// History sessions are persisted to SharedPreferences keyed by Firebase UID.
// ─────────────────────────────────────────────────────────────────────────────
class AdminChatStore {
  static final List<_ChatMessage> messages = [];
  static String? sessionId;
  static String?
  localSessionId; // stable local conversation id (pre server assignment)
  static bool rateLimited = false;
  static String resetIn = '';
  static String? _lastSavedSig; // dedupe guard: signature of the last save

  // SharedPreferences key helpers
  static String _activeKey(String uid) => 'rag_ai_active_$uid';
  static String _storageKey(String uid) => 'rag_ai_chat_$uid';

  /// Stable unique id for a NEW conversation. Generated once per conversation
  /// (on New Chat), then reused across restarts so every write for the same
  /// conversation lands on the same history slot instead of duplicating it.
  static String newLocalId() =>
      'local_${DateTime.now().millisecondsSinceEpoch}_${(DateTime.now().microsecondsSinceEpoch % 46656).toRadixString(36)}';

  /// The id under which this conversation is currently stored.
  static String? get effectiveSid => sessionId ?? localSessionId;

  static void clear() {
    messages.clear();
    sessionId = null;
    localSessionId = null;
    rateLimited = false;
    resetIn = '';
    _lastSavedSig = null;
  }

  /// Begin a genuinely NEW conversation (New Chat): fresh unique id, old chat
  /// stays in history. Nothing is persisted until the first message is sent.
  static void startNewSession() {
    clear();
    localSessionId = newLocalId();
  }

  /// Rename the stored conversation (history list + active slot) when the
  /// server assigns its real session id, so the same conversation never
  /// appears as two history entries.
  static Future<void> adoptServerSession(String uid, String serverId) async {
    final oldId = effectiveSid;
    if (oldId == null || oldId == serverId) {
      sessionId = serverId;
      localSessionId = null;
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      // Rename in the history list
      final all = await loadAllSessions(uid);
      final idx = all.indexWhere((s) => s['id'] == oldId);
      if (idx >= 0) all[idx]['id'] = serverId;
      // Drop an older entry already stored under the server id (past duplicates)
      all.removeWhere((s) => s['id'] == serverId && all.indexOf(s) != idx);
      await prefs.setString(_storageKey(uid), jsonEncode(all));
      // Rename in the active slot
      final raw = prefs.getString(_activeKey(uid));
      if (raw != null) {
        final entry = jsonDecode(raw) as Map<String, dynamic>;
        if (entry['id'] == oldId) {
          entry['id'] = serverId;
          await prefs.setString(_activeKey(uid), jsonEncode(entry));
        }
      }
    } catch (_) {}
    sessionId = serverId;
    localSessionId = null;
    _lastSavedSig = null;
  }

  /// Persist current in-memory messages as the active session + upsert into
  /// the history list. Call after every AI reply and on clear/page-exit.
  /// Idempotent: skips the write when nothing changed since the last save.
  static Future<void> saveChat(String uid) async {
    if (messages.isEmpty) return;
    try {
      // Dedupe guard — avoid re-writing identical state on every event
      final sig =
          '${effectiveSid ?? ''}|${messages.length}|${messages.last.text ?? ''}';
      if (sig == _lastSavedSig) return;
      _lastSavedSig = sig;
      final prefs = await SharedPreferences.getInstance();
      final sid = effectiveSid ?? newLocalId();
      if (sessionId == null && localSessionId == null) localSessionId = sid;
      final entry = {
        'id': sid,
        'ts': DateTime.now().millisecondsSinceEpoch,
        'messages': messages
            .map((m) => {'role': m.role, 'text': m.text ?? ''})
            .toList(),
      };
      // Active slot
      prefs.setString(_activeKey(uid), jsonEncode(entry));
      // History list — upsert by sid
      final all = await loadAllSessions(uid);
      final idx = all.indexWhere((s) => s['id'] == sid);
      if (idx >= 0)
        all[idx] = entry;
      else
        all.insert(0, entry);
      final trimmed = all.length > 50 ? all.sublist(0, 50) : all;
      prefs.setString(_storageKey(uid), jsonEncode(trimmed));
    } catch (_) {}
  }

  /// Load all saved sessions for [uid] sorted newest first.
  static Future<List<Map<String, dynamic>>> loadAllSessions(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey(uid));
      if (raw == null) return [];
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      list.sort(
        (a, b) => ((b['ts'] as int?) ?? 0).compareTo((a['ts'] as int?) ?? 0),
      );
      return list;
    } catch (_) {
      return [];
    }
  }

  /// Clear all persisted history for [uid].
  static Future<void> clearAllHistory(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey(uid));
      await prefs.remove(_activeKey(uid));
    } catch (_) {}
  }

  /// Remove the active slot so a cleared session isn't restored on next open.
  static Future<void> clearActiveSlot(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_activeKey(uid));
    } catch (_) {}
  }

  /// Restore the most recent active session into in-memory messages.
  /// Returns true if a session was restored.
  static Future<bool> restoreActiveSession(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_activeKey(uid));
      if (raw == null) {
        localSessionId ??= newLocalId();
        return false;
      }
      final entry = jsonDecode(raw) as Map<String, dynamic>;
      final msgs =
          (entry['messages'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (msgs.isEmpty) {
        localSessionId ??= newLocalId();
        return false;
      }
      final sid = entry['id'] as String?;
      // Reuse the SAME conversation id so saves keep writing to the same slot
      if (sid != null && !sid.startsWith('local_')) {
        sessionId = sid;
        localSessionId = null;
      } else {
        sessionId = null;
        localSessionId = sid ?? newLocalId();
      }
      // Dedupe restored messages (consecutive same-role rows from older saves)
      messages.clear();
      String? prevRole;
      String? prevText;
      for (final m in msgs) {
        final role = m['role'] as String? ?? 'ai';
        final text = m['text'] as String? ?? '';
        if (role == prevRole && text == prevText) continue; // duplicate row
        messages.add(_ChatMessage(role: role, text: text));
        prevRole = role;
        prevText = text;
      }
      _lastSavedSig = null;
      return messages.isNotEmpty;
    } catch (_) {
      return false;
    }
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
  static const _red = Color(0xFFE8001C);

  // ── Fields ────────────────────────────────────────────────────────────────
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  // Messages and session live in the static store — widget rebuild-safe
  List<_ChatMessage> get _messages => AdminChatStore.messages;
  String? get _sessionId => AdminChatStore.sessionId;
  set _sessionId(String? v) => AdminChatStore.sessionId = v;

  final List<Map<String, String>> _history =
      []; // legacy — kept for fallback only
  String _initials = 'AD'; // admin initials shown on user bubble
  String _currentUid = ''; // Firebase UID for history persistence

  bool _loading = false;

  http.Client? _activeClient; // HTTP client for cancelling ongoing requests

  bool get _rateLimited => AdminChatStore.rateLimited;
  set _rateLimited(bool v) => AdminChatStore.rateLimited = v;
  String get _resetIn => AdminChatStore.resetIn;
  set _resetIn(String v) => AdminChatStore.resetIn = v;
  bool _backendOnline = true;

  // ── History drawer state ───────────────────────────────────────────────────
  bool _historyOpen = false;
  List<Map<String, dynamic>> _historySessions = [];

  @override
  void initState() {
    super.initState();
    _checkBackend(silent: true);
    _checkAiStatus();
    _loadInitials();
  }

  /// Previously checked backend AI key status on startup.
  /// Removed after AI Settings management feature was deleted.
  Future<void> _checkAiStatus() async {
    // No-op: AI Settings feature has been removed
  }

  Future<void> _loadInitials() async {
    try {
      final user = firebase_auth.FirebaseAuth.instance.currentUser;
      if (user == null) return;
      if (mounted) setState(() => _currentUid = user.uid);
      final doc = await cloud_firestore.FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final name = (doc.data()?['name'] as String? ?? '').trim();
      if (name.isNotEmpty) {
        final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
        final ini = parts.length >= 2
            ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
            : parts[0][0].toUpperCase();
        if (mounted) setState(() => _initials = ini);
      }
      // Restore active session if in-memory store is empty (cold start)
      if (AdminChatStore.messages.isEmpty) {
        final restored = await AdminChatStore.restoreActiveSession(user.uid);
        if (restored && mounted)
          setState(() {}); // rebuild to show restored messages
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    // Save chat on widget dispose (tab switch, navigation away)
    if (_currentUid.isNotEmpty && AdminChatStore.messages.isNotEmpty) {
      AdminChatStore.saveChat(_currentUid);
    }
    _activeClient?.close();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Backend health check ───────────────────────────────────────────────────
  // The backend is always deployed on Render. We do a silent health probe on
  // startup — if it responds, we mark online; if all attempts fail we show the
  // offline banner so the user can manually retry.

  Future<void> _checkBackend({bool silent = false}) async {
    if (!silent && mounted) setState(() => _backendOnline = false);
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        final r = await http
            .get(Uri.parse('$_kAiBaseUrl/health'))
            .timeout(
              const Duration(seconds: 60),
            ); // 60s covers Render cold-start (~30–50s)
        if (r.statusCode == 200) {
          if (mounted) setState(() => _backendOnline = true);
          return;
        }
      } catch (_) {
        // wait before retry (skip delay on last attempt)
        if (attempt < 3) await Future.delayed(const Duration(seconds: 5));
      }
    }
    // All attempts failed — if silent (startup), schedule a delayed re-check
    // so the dot corrects itself once Render finishes waking up
    if (silent) {
      Future.delayed(const Duration(seconds: 60), () {
        if (mounted) _checkBackend(silent: false);
      });
    } else {
      if (mounted) setState(() => _backendOnline = false);
    }
  }

  // ── History drawer ─────────────────────────────────────────────────────────

  Future<void> _openHistory() async {
    if (_currentUid.isEmpty) return;
    final sessions = await AdminChatStore.loadAllSessions(_currentUid);
    if (mounted)
      setState(() {
        _historySessions = sessions;
        _historyOpen = true;
      });
  }

  void _closeHistory() {
    if (mounted) setState(() => _historyOpen = false);
  }

  Future<void> _loadSession(Map<String, dynamic> session) async {
    final msgs =
        (session['messages'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (msgs.isEmpty) return;
    final sid = session['id'] as String?;
    // Selected conversation becomes the active one — keep its id so new
    // messages append to the SAME history entry.
    if (sid != null && !sid.startsWith('local_')) {
      AdminChatStore.sessionId = sid;
      AdminChatStore.localSessionId = null;
    } else {
      AdminChatStore.sessionId = null;
      AdminChatStore.localSessionId = sid;
    }
    setState(() {
      AdminChatStore.messages.clear();
      String? prevRole;
      String? prevText;
      for (final m in msgs) {
        final role = m['role'] as String? ?? 'ai';
        final text = m['text'] as String? ?? '';
        if (role == prevRole && text == prevText) continue; // skip duplicates
        AdminChatStore.messages.add(_ChatMessage(role: role, text: text));
        prevRole = role;
        prevText = text;
      }
      AdminChatStore._lastSavedSig =
          null; // force the next save to persist the switch
      _historyOpen = false;
    });
    _scrollToBottom();
  }

  Future<void> _deleteAllHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete All Chats',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: const Text('Delete all chat history? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF718096)),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE8001C),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete All',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (_currentUid.isNotEmpty) {
      await AdminChatStore.clearAllHistory(_currentUid);
      // Also clear server session
      if (_sessionId != null && !_sessionId!.startsWith('local_')) {
        http
            .delete(Uri.parse('$_kAiBaseUrl/session/$_sessionId'))
            .catchError((_) => http.Response('', 200));
      }
      AdminChatStore.clear();
      AdminChatStore.localSessionId = AdminChatStore.newLocalId();
    }
    if (mounted)
      setState(() {
        _historySessions = [];
        _historyOpen = false;
      });
  }

  // ── Stop generation ────────────────────────────────────────────────────────
  void _stopGeneration() {
    _activeClient?.close();
    _activeClient = null;
    if (mounted) {
      setState(() {
        _loading = false;
        _messages.add(_ChatMessage(role: 'ai', text: '⏹ Generation stopped.'));
      });
    }
    AdminChatStore._lastSavedSig = null;
    if (_currentUid.isNotEmpty) AdminChatStore.saveChat(_currentUid);
    _scrollToBottom();
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
      _showReportConfirm(
        reportType,
        isExcel ? 'excel' : 'pdf',
        preselectedMonth: extractedMonth,
      );
      return;
    }

    setState(() {
      _messages.add(_ChatMessage(role: 'user', text: text));
      _inputCtrl.clear();
      _loading = true;
    });
    _scrollToBottom();
    AdminChatStore._lastSavedSig = null; // user message changed state

    // session memory is handled server-side via _sessionId

    try {
      _activeClient = http.Client(); // Create client for cancellation support
      final resp = await _activeClient!
          .post(
            Uri.parse('$_kAiBaseUrl/admin/chat'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'message': text,
              'session_id': _sessionId, // server-side memory key
            }),
          )
          .timeout(const Duration(seconds: 120));
      _activeClient = null;

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final rawReply = (data['reply'] as String? ?? '').trim();

        // Persist session_id for continuity across turns — adopt it in place
        // (rename stored history entry) so no duplicate history item is created.
        final serverId = data['session_id'] as String?;
        if (serverId != null && serverId.isNotEmpty && _currentUid.isNotEmpty) {
          await AdminChatStore.adoptServerSession(_currentUid, serverId);
        } else if (serverId != null && serverId.isNotEmpty) {
          _sessionId = serverId;
        }

        // Handle rate limit
        if (data['rate_limited'] == true) {
          final resetIn = data['reset_in'] as String? ?? 'some time';
          setState(() {
            _loading = false;
            _rateLimited = true;
            _resetIn = resetIn;
            _messages.add(
              _ChatMessage(
                role: 'ai',
                text:
                    'AI Unavailable\n\n'
                    'The AI service has reached its daily token limit (Groq free tier).\n\n'
                    'The limit resets in $resetIn.\n\n'
                    'You cannot send new messages until the quota resets automatically.',
                isRateLimit: true,
              ),
            );
          });
          return;
        }

        // ── Parse report_payload block from the raw reply ──────────────────
        // The FastAPI backend embeds a ```report_payload {...} ``` block when
        // it detects a report request. We parse it here (mirroring Flask proxy
        // logic) so we can show a proper download button instead of raw JSON.
        final rpMatch = RegExp(
          r'```report_payload\s*\n(.*?)\n```',
          dotAll: true,
        ).firstMatch(rawReply);

        if (rpMatch != null) {
          try {
            final rpJson =
                jsonDecode(rpMatch.group(1)!.trim()) as Map<String, dynamic>;
            if (rpJson['report_type'] != null) {
              // Strip the JSON block from the visible reply text
              final cleanReply = rawReply
                  .replaceAll(
                    RegExp(r'\n?```report_payload\s*\n.*?\n```', dotAll: true),
                    '',
                  )
                  .trim();

              final rawFilters = Map<String, dynamic>.from(
                (rpJson['filters'] as Map<String, dynamic>?) ?? {},
              );
              final reportMonth = rawFilters.remove('month') as String?;
              final reportStartDate =
                  rawFilters.remove('start_date') as String?;
              final reportEndDate = rawFilters.remove('end_date') as String?;
              final reportType = rpJson['report_type'] as String;
              final rawFmt = ((rpJson['format'] as String?) ?? 'pdf')
                  .toLowerCase()
                  .replaceAll('xlsx', 'excel');

              // ── Future-date guard ────────────────────────────────────────
              bool isFuture = false;
              if (reportMonth != null) {
                final mMatch = RegExp(
                  r'([A-Za-z]+)\s+(\d{4})',
                ).firstMatch(reportMonth);
                if (mMatch != null) {
                  const monthNames = [
                    'january',
                    'february',
                    'march',
                    'april',
                    'may',
                    'june',
                    'july',
                    'august',
                    'september',
                    'october',
                    'november',
                    'december',
                  ];
                  final mIdx = monthNames.indexOf(
                    mMatch.group(1)!.toLowerCase(),
                  );
                  final yr = int.tryParse(mMatch.group(2)!) ?? 0;
                  final now = DateTime.now();
                  if (mIdx >= 0) {
                    final mo = mIdx + 1;
                    isFuture =
                        yr > now.year || (yr == now.year && mo > now.month);
                  }
                }
              }

              if (isFuture) {
                final label = reportMonth ?? 'the requested period';
                setState(() {
                  _loading = false;
                  _messages.add(
                    _ChatMessage(
                      role: 'ai',
                      text:
                          'No records found for **$label** — that date range is in the future. '
                          'Reports can only be generated for dates with existing historical data.',
                    ),
                  );
                });
                _scrollToBottom();
                return;
              }

              final displayReply = cleanReply.isNotEmpty
                  ? cleanReply
                  : 'Your ${_kReportTypes[reportType] ?? reportType} is ready.';

              setState(() {
                _loading = false;
                _messages.add(
                  _ChatMessage(
                    role: 'ai',
                    text: displayReply,
                    reportReady: true,
                    reportType: reportType,
                    reportFormat: rawFmt,
                    reportMonth: reportMonth,
                    reportStartDate: reportStartDate,
                    reportEndDate: reportEndDate,
                    reportFilters: rawFilters,
                    reportLabel: _kReportTypes[reportType] ?? reportType,
                  ),
                );
              });
              _scrollToBottom();
              return;
            }
          } catch (_) {
            // JSON parse failed — fall through to normal reply rendering
          }
        }

        // ── Normal reply (no report_payload) ───────────────────────────────
        final answer = rawReply.isNotEmpty
            ? rawReply
            : 'No response generated.';
        setState(() {
          _loading = false;
          _messages.add(_ChatMessage(role: 'ai', text: answer));
        });
        _activeClient = null; // Clear after successful completion
      } else {
        // Non-200 response — try to extract a friendly reply from the body first
        String errorMsg =
            "I'm having trouble processing your request right now. Please try again in a moment.";
        try {
          final errData = jsonDecode(resp.body) as Map<String, dynamic>;
          final bodyReply =
              (errData['reply'] as String? ??
                      errData['detail'] as String? ??
                      '')
                  .trim();
          if (bodyReply.isNotEmpty &&
              !bodyReply.contains('Error') &&
              !bodyReply.contains('500') &&
              !bodyReply.contains('503')) {
            errorMsg = bodyReply;
          }
        } catch (_) {}
        setState(() {
          _loading = false;
          _messages.add(_ChatMessage(role: 'ai', text: errorMsg));
        });
      }
    } on http.ClientException catch (_) {
      // If _activeClient is null, the request was cancelled intentionally — ignore
      if (_activeClient == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      setState(() {
        _loading = false;
        _messages.add(
          _ChatMessage(
            role: 'ai',
            text:
                'Cannot reach the AI service. Please check your internet connection and try again.',
          ),
        );
      });
      _activeClient = null;
    } on Exception catch (e) {
      // If _activeClient is null, the request was cancelled intentionally — ignore
      if (_activeClient == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      // Covers TimeoutException and other network errors
      setState(() {
        _loading = false;
        _messages.add(
          _ChatMessage(
            role: 'ai',
            text:
                e.toString().contains('TimeoutException') ||
                    e.toString().contains('timed out')
                ? 'The request took too long. Please check your connection and try again.'
                : "I'm having trouble processing your request right now. Please try again in a moment.",
          ),
        );
      });
      _activeClient = null;
    }
    _scrollToBottom();
    // Persist the exchange to history after every turn
    if (_currentUid.isNotEmpty) AdminChatStore.saveChat(_currentUid);
  }

  String _parseError(String body) {
    try {
      final d = jsonDecode(body) as Map<String, dynamic>;
      return d['detail']?.toString() ?? d['error']?.toString() ?? body;
    } catch (_) {
      return body.length > 120 ? '${body.substring(0, 120)}…' : body;
    }
  }

  // ── Report-ready download buttons ─────────────────────────────────────────
  // Renders PDF / Excel / both buttons based on the format in the message.
  // Tapping a button calls _downloadReport which streams the file and updates
  // the message in-place with Open + Share actions.

  Widget _buildReportDownloadButtons(_ChatMessage msg) {
    final fmt = (msg.reportFormat ?? 'pdf').toLowerCase();
    final monthLabel = msg.reportMonth != null ? ' (${msg.reportMonth})' : '';

    Widget _dlBtn(String format, bool primary) {
      final fmtLabel = format.toUpperCase();
      return GestureDetector(
        onTap: () => _downloadReport(
          msg.reportType!,
          format,
          month: msg.reportMonth,
          startDate: msg.reportStartDate,
          endDate: msg.reportEndDate,
          msgRef: msg,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: primary ? _red : const Color(0xFFF7F8FA),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: primary ? _red : const Color(0xFFe2e8f0),
              width: primary ? 0 : 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                format == 'pdf'
                    ? Icons.picture_as_pdf_outlined
                    : Icons.table_chart_outlined,
                color: primary ? Colors.white : const Color(0xFF4a5568),
                size: 13,
              ),
              const SizedBox(width: 5),
              Text(
                '↓ Download $fmtLabel$monthLabel',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: primary ? Colors.white : const Color(0xFF4a5568),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        if (fmt == 'pdf' || fmt == 'both') _dlBtn('pdf', true),
        if (fmt == 'excel' || fmt == 'both') _dlBtn('excel', fmt != 'both'),
      ],
    );
  }

  // ── Report generation ──────────────────────────────────────────────────────

  /// Shows a bottom sheet to confirm the report type/format then downloads it.
  /// For issuance reports, also shows an optional month picker.
  void _showReportConfirm(
    String reportType,
    String format, {
    String? preselectedMonth,
  }) {
    final title = _kReportTypes[reportType] ?? 'Report';

    // Month filter applies to date-based reports
    const monthSupported = {'issuance', 'maintenance', 'bookings'};
    final supportsMonth = monthSupported.contains(reportType);

    // Month names / options
    const monthNames = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final currentYear = DateTime.now().year;
    final monthOptions = <String>['All Months'];
    for (int y = currentYear; y >= currentYear - 1; y--) {
      for (int m = 12; m >= 1; m--) {
        monthOptions.add('${monthNames[m - 1]} $y');
      }
    }

    // Pre-select month extracted from the user message (if valid)
    String? selectedMonth =
        (preselectedMonth != null && monthOptions.contains(preselectedMonth))
        ? preselectedMonth
        : null;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            20,
            24,
            32 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Download Report',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1a202c),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                style: const TextStyle(fontSize: 13, color: Color(0xFF718096)),
              ),

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
                      color: Colors.grey.shade600,
                    ),
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
                      items: monthOptions
                          .map(
                            (m) => DropdownMenuItem(
                              value: m,
                              child: Text(
                                m,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setSheet(() {
                        selectedMonth = (v == 'All Months') ? null : v;
                      }),
                    ),
                  ),
                ),
                if (selectedMonth != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.filter_alt_outlined,
                          size: 13,
                          color: Color(0xFFE8001C),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Showing records for $selectedMonth only',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFFE8001C),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],

              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _reportFormatBtn(
                      icon: Icons.picture_as_pdf_outlined,
                      label: 'PDF',
                      subtitle: 'Branded report',
                      selected: format == 'pdf',
                      onTap: () {
                        Navigator.pop(ctx);
                        _downloadReport(
                          reportType,
                          'pdf',
                          month: selectedMonth,
                        );
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
                        _downloadReport(
                          reportType,
                          'excel',
                          month: selectedMonth,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
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
          color: selected
              ? _red.withValues(alpha: 0.06)
              : const Color(0xFFF7F8FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? _red : const Color(0xFFe2e8f0),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 22,
              color: selected ? _red : const Color(0xFF4a5568),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: selected ? _red : const Color(0xFF1a202c),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: Color(0xFF718096)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadReport(
    String reportType,
    String format, {
    String? month,
    String? startDate,
    String? endDate,
    _ChatMessage? msgRef,
  }) async {
    final typeName = _kReportTypes[reportType] ?? reportType;
    final fmtLabel = format.toUpperCase();
    final monthLabel = month != null ? ' ($month)' : '';

    final int targetIdx;
    if (msgRef != null) {
      final idx = _messages.indexOf(msgRef);
      targetIdx = idx >= 0 ? idx : _messages.length;
    } else {
      targetIdx = _messages.length;
    }

    setState(() {
      _loading = true;
      final placeholder = _ChatMessage(
        role: 'ai',
        text: 'Generating $typeName$monthLabel ($fmtLabel)…',
      );
      if (targetIdx < _messages.length) {
        _messages[targetIdx] = placeholder;
      } else {
        _messages.add(placeholder);
      }
    });
    _scrollToBottom();

    // Build query params
    final queryParams = StringBuffer()
      ..write('?report_type=$reportType')
      ..write('&format=$format');
    if (month != null)
      queryParams.write('&month=${Uri.encodeComponent(month)}');
    if (startDate != null)
      queryParams.write('&start_date=${Uri.encodeComponent(startDate)}');
    if (endDate != null)
      queryParams.write('&end_date=${Uri.encodeComponent(endDate)}');

    final uri = Uri.parse('$_kAiBaseUrl/admin/report$queryParams');

    Future<http.Response> _attempt() => http
        .post(uri, headers: {'Content-Type': 'application/json'})
        .timeout(const Duration(seconds: 120));

    void _setError(String text) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        final idx = targetIdx < _messages.length
            ? targetIdx
            : _messages.length - 1;
        _messages[idx] = _ChatMessage(role: 'ai', text: text);
      });
      _scrollToBottom();
    }

    try {
      http.Response resp;
      try {
        resp = await _attempt();
      } on SocketException {
        // Backend is cold-starting — warm it up then retry once
        try {
          await http
              .get(Uri.parse('$_kAiBaseUrl/health'))
              .timeout(const Duration(seconds: 60));
        } catch (_) {}
        await Future.delayed(const Duration(seconds: 2));
        resp = await _attempt();
      }

      if (resp.statusCode == 200) {
        final ext = format == 'pdf' ? 'pdf' : 'xlsx';
        final safeName =
            '$reportType'
            '${month != null ? '_${month.replaceAll(' ', '_')}' : ''}'
            '_report.$ext';

        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/$safeName');
        await file.writeAsBytes(resp.bodyBytes);

        if (!mounted) return;
        setState(() {
          _loading = false;
          final idx = targetIdx < _messages.length
              ? targetIdx
              : _messages.length - 1;
          _messages[idx] = _ChatMessage(
            role: 'ai',
            text: '$typeName$monthLabel downloaded successfully.',
            reportFile: file,
            reportFormat: format,
            reportLabel: typeName,
          );
        });
        _scrollToBottom();
        await OpenFile.open(file.path);
      } else {
        final errMsg = _parseError(resp.body);
        final isNoRecords =
            resp.statusCode == 400 &&
            (errMsg.toLowerCase().contains('no record') ||
                errMsg.toLowerCase().contains('no data') ||
                errMsg.toLowerCase().contains('not found'));
        final isQuota =
            resp.statusCode == 503 &&
            (errMsg.toLowerCase().contains('quota') ||
                errMsg.toLowerCase().contains('resource_exhausted') ||
                errMsg.toLowerCase().contains('429'));
        final isColdStart = resp.statusCode == 503 && !isQuota;

        _setError(
          isNoRecords
              ? 'No records found for $typeName$monthLabel. '
                    'The report cannot be generated because no matching data exists for this period.'
              : isQuota
              ? 'Firestore quota limit reached (free-tier). '
                    'The database is temporarily unavailable — please wait a few minutes and try again.'
              : isColdStart
              ? 'The AI service is warming up (Render cold start). '
                    'Please wait 30–60 seconds and try again.'
              : 'Failed to generate $typeName$monthLabel '
                    '(${resp.statusCode}): $errMsg',
        );
      }
    } on SocketException {
      _setError(
        'Cannot reach the AI service. '
        'It may be starting up — please wait 30–60 seconds and try again.',
      );
    } catch (e) {
      final msg = e.toString();
      final isTimeout =
          msg.contains('TimeoutException') || msg.contains('timed out');
      _setError(
        isTimeout
            ? 'The AI service took too long to respond. It may still be warming up — '
                  'please try again in a moment.'
            : 'Failed to generate $typeName$monthLabel: $msg',
      );
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: const Color(0xFF004B5F),
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF004B5F), Color(0xFFEE152A)],
              stops: [0.0, 1.0],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        title: Row(
          children: [
            // AI logo in AppBar with status-colour border (no pulse rings)
            Stack(
              alignment: Alignment.center,
              children: [
                // Avatar circle with status-colour border
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(
                      color: _backendOnline
                          ? const Color(0xFF4ade80)
                          : const Color(0xFFF97316),
                      width: 2.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:
                            (_backendOnline
                                    ? const Color(0xFF4ade80)
                                    : const Color(0xFFF97316))
                                .withValues(alpha: 0.5),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Image.asset(
                        'assets/img/AI_LOGO.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'AI Assistant',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _backendOnline
                              ? const Color(0xFF4ade80)
                              : Colors.orange,
                          boxShadow: [
                            BoxShadow(
                              color: _backendOnline
                                  ? const Color(
                                      0xFF4ade80,
                                    ).withValues(alpha: 0.8)
                                  : const Color(
                                      0xFFF97316,
                                    ).withValues(alpha: 0.6),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _backendOnline ? 'Online' : 'Local',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // New Chat button
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            tooltip: 'New chat',
            onPressed: () async {
              // Save current session to history before starting a new one
              if (_currentUid.isNotEmpty && _messages.isNotEmpty) {
                await AdminChatStore.saveChat(_currentUid);
                await AdminChatStore.clearActiveSlot(_currentUid);
              }
              // Clear server-side session memory (only real server sessions)
              final oldSid = _sessionId;
              if (oldSid != null && !oldSid.startsWith('local_')) {
                http
                    .delete(Uri.parse('$_kAiBaseUrl/session/$oldSid'))
                    .catchError((_) => http.Response('', 200));
              }
              if (mounted) {
                setState(() {
                  // Genuinely NEW conversation id — old chat stays in history.
                  // No empty entry is written until the first message is sent.
                  AdminChatStore.startNewSession();
                  _history.clear();
                });
              }
            },
          ),
          // History button — always visible
          IconButton(
            icon: const Icon(Icons.history, color: Colors.white),
            tooltip: 'Chat history',
            onPressed: _openHistory,
          ),
          if (_messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.white),
              tooltip: 'Clear chat',
              onPressed: () async {
                // Save current session to history before clearing
                if (_currentUid.isNotEmpty) {
                  await AdminChatStore.saveChat(_currentUid);
                  await AdminChatStore.clearActiveSlot(_currentUid);
                }
                // Clear server-side session memory (only real server sessions)
                final oldSid = _sessionId;
                if (oldSid != null && !oldSid.startsWith('local_')) {
                  http
                      .delete(Uri.parse('$_kAiBaseUrl/session/$oldSid'))
                      .catchError((_) => http.Response('', 200));
                }
                setState(() {
                  AdminChatStore.startNewSession();
                  _history.clear();
                });
              },
            ),
        ],
      ),
      body: Stack(
        children: [
          // ── Main chat column ──────────────────────────────────────────────
          Column(
            children: [
              // Offline banner
              if (!_backendOnline)
                Container(
                  width: double.infinity,
                  color: const Color(0xFFFFFBEB),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: Color(0xFF975A16),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Cannot reach AI backend. Check your connection or tap Retry.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF975A16),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _checkBackend(),
                        child: const Text(
                          'Retry',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF975A16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Rate-limit banner
              if (_rateLimited)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFF7ED),
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFFB923C), width: 2),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.block,
                        size: 18,
                        color: Color(0xFF9A3412),
                      ),
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
                                color: Color(0xFF9A3412),
                              ),
                            ),
                            const SizedBox(height: 3),
                            RichText(
                              text: TextSpan(
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF9A3412),
                                  height: 1.5,
                                ),
                                children: [
                                  const TextSpan(
                                    text:
                                        'Groq free-tier quota is exhausted. Resets in ',
                                  ),
                                  TextSpan(
                                    text: _resetIn,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const TextSpan(
                                    text: '. Chat is disabled until then.',
                                  ),
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
                          child: Text(
                            'Retry',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF9A3412),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
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
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _AdminFocusInputBar(
                        inputCtrl: _inputCtrl,
                        loading: _loading,
                        rateLimited: _rateLimited,
                        hint: _rateLimited
                            ? 'AI unavailable — daily limit reached'
                            : 'Ask about fleet, inventory, reports…',
                        onSend: _sendQuery,
                        onStop: _loading ? _stopGeneration : null,
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Enter to send  ·  Shift+Enter for new line',
                        style: TextStyle(
                          fontSize: 10,
                          color: Color(0xFFC0C8D4),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // ── History drawer overlay ────────────────────────────────────────
          if (_historyOpen) ...[
            // Scrim
            GestureDetector(
              onTap: _closeHistory,
              child: Container(color: Colors.black.withValues(alpha: 0.25)),
            ),
            // Drawer panel — slides in from the right
            Positioned(
              top: 0,
              right: 0,
              bottom: 0,
              width: 300,
              child: Material(
                elevation: 8,
                child: Column(
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFFc62828), Color(0xFFE8001C)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.history,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Chat History',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: _closeHistory,
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Delete all button
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                      child: GestureDetector(
                        onTap: _deleteAllHistory,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF5F5),
                            border: Border.all(color: const Color(0xFFFCA5A5)),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.delete_outline,
                                size: 14,
                                color: Color(0xFFDC2626),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Delete All Chats',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFDC2626),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Session list
                    Expanded(
                      child: _historySessions.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                  'No chat history yet.\nStart a conversation!',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF94A3B8),
                                  ),
                                ),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(
                                14,
                                12,
                                14,
                                14,
                              ),
                              itemCount: _historySessions.length,
                              itemBuilder: (_, i) {
                                final s = _historySessions[i];
                                final ts = s['ts'] as int? ?? 0;
                                final d = DateTime.fromMillisecondsSinceEpoch(
                                  ts,
                                );
                                final msgs =
                                    (s['messages'] as List?)
                                        ?.cast<Map<String, dynamic>>() ??
                                    [];
                                final firstUser = msgs.firstWhere(
                                  (m) => m['role'] == 'user',
                                  orElse: () => {'text': '(empty)'},
                                );
                                final preview =
                                    (firstUser['text'] as String? ?? '');
                                final time =
                                    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
                                final isActive =
                                    s['id'] == AdminChatStore.effectiveSid;
                                return GestureDetector(
                                  onTap: () => _loadSession(s),
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 7),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isActive
                                          ? const Color(0xFFFFF0F0)
                                          : const Color(0xFFF8F9FB),
                                      border: Border.all(
                                        color: isActive
                                            ? const Color(0xFFE8001C)
                                            : const Color(0xFFE8EDF2),
                                        width: 1.5,
                                      ),
                                      borderRadius: BorderRadius.circular(11),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          preview.length > 55
                                              ? '${preview.substring(0, 55)}…'
                                              : preview,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            color: Color(0xFF1A202C),
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          '$time  ·  ${msgs.length} message${msgs.length != 1 ? 's' : ''}',
                                          style: const TextStyle(
                                            fontSize: 10.5,
                                            color: Color(0xFF94A3B8),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // AI logo — transparent circle with image
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFFE8001C).withValues(alpha: 0.2),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE8001C).withValues(alpha: 0.12),
                  blurRadius: 16,
                ),
              ],
            ),
            child: ClipOval(
              child: Image.asset('assets/img/AI_LOGO.png', fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'AI Assistant',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1a202c),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Ask me about fleet, inventory, maintenance costs, or generate PDF/Excel reports.',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF718096),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ...suggestions.map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GestureDetector(
                onTap: () => _sendQuery(s),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFe8edf2),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Color(0xFFE8001C),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          s,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF4a5568),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Typing indicator ───────────────────────────────────────────────────────

  // ── Typing indicator — 3 bouncing dots (matches web design) ──────────────

  Widget _buildTypingIndicator() {
    // Randomly choose between "Thinking..." and "Processing..."
    final thinkingTexts = ['Thinking...', 'Processing...'];
    final randomText = thinkingTexts[DateTime.now().millisecond % 2];
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _aiAvatar(),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: _aiBubbleDecoration(),
            child: Text(
              randomText,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF64748B),
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.72,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFE8001C), Color(0xFFC41E3A)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(14),
                        topRight: Radius.circular(4),
                        bottomLeft: Radius.circular(14),
                        bottomRight: Radius.circular(14),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFFE8001C,
                          ).withValues(alpha: 0.22),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: Text(
                      msg.text ?? '',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        height: 1.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Copy / Edit actions
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _userPromptActionBtn(
                        icon: Icons.copy_outlined,
                        label: 'Copy',
                        onTap: () async {
                          await Clipboard.setData(
                            ClipboardData(text: msg.text ?? ''),
                          );
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Copied to clipboard'),
                                duration: Duration(seconds: 2),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                      ),
                      const SizedBox(width: 6),
                      _userPromptActionBtn(
                        icon: Icons.edit_outlined,
                        label: 'Edit',
                        onTap: () {
                          // Find message index
                          final msgIndex = _messages.indexOf(msg);
                          if (msgIndex == -1) return;
                          
                          // Show edit dialog with the message
                          showDialog(
                            context: context,
                            builder: (ctx) {
                              final editCtrl = TextEditingController(text: msg.text ?? '');
                              return AlertDialog(
                                title: const Text('Edit Message'),
                                content: TextField(
                                  controller: editCtrl,
                                  maxLines: null,
                                  minLines: 3,
                                  autofocus: true,
                                  decoration: const InputDecoration(
                                    hintText: 'Edit your message...',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text('Cancel'),
                                  ),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFE8001C),
                                    ),
                                    onPressed: () {
                                      final editedText = editCtrl.text.trim();
                                      if (editedText.isEmpty) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('Message cannot be empty'),
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                        return;
                                      }
                                      if (editedText == (msg.text ?? '')) {
                                        Navigator.pop(ctx);
                                        return;
                                      }
                                      Navigator.pop(ctx);
                                      
                                      // Remove this message and all after it
                                      setState(() {
                                        _messages.removeRange(msgIndex, _messages.length);
                                      });
                                      
                                      // Send edited message
                                      _inputCtrl.text = editedText;
                                      _sendMessage();
                                    },
                                    child: const Text('Send'),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // ── Rate-limit card ──────────────────────────────────────
    if (msg.isRateLimit) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _aiAvatar(),
            const SizedBox(width: 8),
            Flexible(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.80,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(14),
                    bottomLeft: Radius.circular(14),
                    bottomRight: Radius.circular(14),
                  ),
                  border: Border.all(
                    color: const Color(0xFFFB923C),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      decoration: const BoxDecoration(
                        color: Color(0xFFEA580C),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(2),
                          topRight: Radius.circular(13),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.block, color: Colors.white, size: 14),
                          SizedBox(width: 8),
                          Text(
                            'AI Service Unavailable',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF9A3412),
                            height: 1.55,
                          ),
                          children: [
                            const TextSpan(
                              text: 'Daily token limit reached.\n\n',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const TextSpan(text: 'Resets in '),
                            TextSpan(
                              text: _resetIn.isNotEmpty
                                  ? _resetIn
                                  : 'some time',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const TextSpan(
                              text: '. You cannot send messages until then.',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // ── Normal AI bubble ─────────────────────────────────────
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _aiAvatar(),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.76,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
              decoration: _aiBubbleDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    msg.text ?? '',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF1a202c),
                      height: 1.6,
                    ),
                  ),
                  // ── Downloaded report: Open + Share buttons ──────────────
                  if (msg.reportFile != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _actionBtn(
                          Icons.folder_open_outlined,
                          'Open',
                          const Color(0xFFE8001C),
                          () async {
                            await OpenFile.open(msg.reportFile!.path);
                          },
                        ),
                        const SizedBox(width: 8),
                        _actionBtn(
                          Icons.share_outlined,
                          'Share',
                          const Color(0xFF003087),
                          () async {
                            await Printing.sharePdf(
                              bytes: await msg.reportFile!.readAsBytes(),
                              filename: msg.reportFile!.path.split('/').last,
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                  // ── Report-ready from AI: Download PDF / Excel buttons ───
                  if (msg.reportReady && msg.reportType != null) ...[
                    const SizedBox(height: 10),
                    _buildReportDownloadButtons(msg),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Avatar helpers ─────────────────────────────────────────────────────────

  Widget _aiAvatar() => Container(
    width: 32,
    height: 32,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white,
      border: Border.all(
        color: _backendOnline
            ? const Color(0xFF4ade80)
            : const Color(0xFFF97316),
        width: 1.5,
      ),
      boxShadow: [
        BoxShadow(
          color:
              (_backendOnline
                      ? const Color(0xFF4ade80)
                      : const Color(0xFFF97316))
                  .withValues(alpha: 0.35),
          blurRadius: 5,
        ),
      ],
    ),
    child: ClipOval(
      child: Image.asset('assets/img/AI_LOGO.png', fit: BoxFit.cover),
    ),
  );

  Widget _userAvatar() => Container(
    width: 30,
    height: 30,
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [Color(0xFFE8001C), Color(0xFFC41E3A)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      shape: BoxShape.circle,
    ),
    child: Center(
      child: Text(
        _initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );

  BoxDecoration _aiBubbleDecoration() => BoxDecoration(
    color: Colors.white,
    borderRadius: const BorderRadius.only(
      topLeft: Radius.circular(4),
      topRight: Radius.circular(16),
      bottomLeft: Radius.circular(16),
      bottomRight: Radius.circular(16),
    ),
    boxShadow: [
      BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6),
    ],
  );

  Widget _userPromptActionBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F6F9),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 10, color: const Color(0xFF64748B)),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionBtn(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 13),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Focused input bar — matches admin/website wrapped input style ─────────────

class _AdminFocusInputBar extends StatefulWidget {
  final TextEditingController inputCtrl;
  final bool loading;
  final bool rateLimited;
  final String hint;
  final Future<void> Function([String?]) onSend;
  final VoidCallback? onStop;

  const _AdminFocusInputBar({
    required this.inputCtrl,
    required this.loading,
    required this.rateLimited,
    required this.hint,
    required this.onSend,
    this.onStop,
  });

  @override
  State<_AdminFocusInputBar> createState() => _AdminFocusInputBarState();
}

class _AdminFocusInputBarState extends State<_AdminFocusInputBar> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final canSend = !widget.loading && !widget.rateLimited;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6F9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _focused ? const Color(0xFFE8001C) : const Color(0xFFEDF0F5),
          width: 1.5,
        ),
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: const Color(0xFFE8001C).withValues(alpha: 0.08),
                  blurRadius: 8,
                ),
              ]
            : [],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: widget.inputCtrl,
              maxLines: 4,
              minLines: 1,
              enabled: canSend,
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF718096),
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
              ),
              style: const TextStyle(fontSize: 13, color: Color(0xFF1a202c)),
              onTap: () => setState(() => _focused = true),
              onEditingComplete: () => setState(() => _focused = false),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) {
                widget.onSend();
              },
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: widget.loading
                ? widget.onStop
                : (canSend ? () => widget.onSend() : null),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                gradient: (canSend || widget.loading)
                    ? LinearGradient(
                        colors: widget.loading
                            ? [const Color(0xFF718096), const Color(0xFF4A5568)]
                            : [
                                const Color(0xFFE8001C),
                                const Color(0xFFC0001A),
                              ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: (canSend || widget.loading)
                    ? null
                    : Colors.grey.shade300,
                shape: BoxShape.circle,
                boxShadow: (canSend || widget.loading)
                    ? [
                        BoxShadow(
                          color: widget.loading
                              ? const Color(0xFF718096).withValues(alpha: 0.35)
                              : const Color(0xFFE8001C).withValues(alpha: 0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : [],
              ),
              child: Icon(
                widget.loading ? Icons.stop_rounded : Icons.send_rounded,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
        ],
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
    _ctrls = List.generate(
      3,
      (i) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 900),
      )..repeat(reverse: true),
    );
    _anims = List.generate(
      3,
      (i) => Tween<double>(begin: 0, end: -5).animate(
        CurvedAnimation(
          parent: _ctrls[i],
          curve: Interval(i * 0.15, i * 0.15 + 0.6, curve: Curves.easeInOut),
        ),
      ),
    );
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          AnimatedBuilder(
            animation: _anims[i],
            builder: (_, _) => Transform.translate(
              offset: Offset(0, _anims[i].value),
              child: Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Color(0xFFA0AEC0),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ],
      ],
    );
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

  // Fields for AI-detected report-ready messages (from report_payload parsing)
  final bool reportReady;
  final String? reportType;
  final String? reportMonth;
  final String? reportStartDate;
  final String? reportEndDate;
  final Map<String, dynamic>? reportFilters;

  _ChatMessage({
    required this.role,
    this.text,
    this.reportFile,
    this.reportFormat,
    this.reportLabel,
    this.isRateLimit = false,
    this.reportReady = false,
    this.reportType,
    this.reportMonth,
    this.reportStartDate,
    this.reportEndDate,
    this.reportFilters,
  });
}
