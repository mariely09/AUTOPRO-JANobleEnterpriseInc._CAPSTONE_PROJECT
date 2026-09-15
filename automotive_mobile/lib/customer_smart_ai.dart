import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Base URL of the ai_assistant FastAPI service.
// ─────────────────────────────────────────────────────────────────────────────
const _kCustAiBaseUrl = String.fromEnvironment(
  'AI_BACKEND_URL',
  defaultValue: 'https://caltex-autopro-capstone-project.onrender.com',
);

// Flask/website backend — used to read the admin AI-pause status.
const _kCustFlaskBase = String.fromEnvironment(
  'FLASK_API_URL',
  defaultValue: 'https://caltex-autopro.onrender.com',
);

// ── Per-customer daily token limit ────────────────────────────────────────────
// Customers are limited to 2 000 tokens per day to prevent abuse.
const _kCustomerDailyTokenLimit = 0; // 0 = unlimited

// ─────────────────────────────────────────────────────────────────────────────
// Static chat store — survives page navigation (cleared on logout/refresh/delete)
// History sessions are persisted to SharedPreferences keyed by Firebase UID.
// ─────────────────────────────────────────────────────────────────────────────
class CustomerChatStore {
  static final List<_ChatMsg> messages = [];
  static String? sessionId;
  static String?
  localSessionId; // stable local conversation id (pre server assignment)
  static bool rateLimited = false;
  static String resetIn = '';
  static String? _lastSavedSig; // dedupe guard: signature of the last save

  // SharedPreferences key helpers
  static String _activeKey(String uid) => 'cust_ai_active_$uid';
  static String _storageKey(String uid) => 'cust_ai_chat_$uid';

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

  static void clearActiveSessionOnly() {
    messages.clear();
    sessionId = null;
    localSessionId = null;
    rateLimited = false;
    resetIn = '';
    _lastSavedSig = null;
  }

  static String _tokenKey(String uid) {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return 'cust_ai_tokens_${uid}_$today';
  }

  /// Persist current in-memory messages as the active session + upsert into
  /// the history list. Idempotent: skips the write when nothing changed
  /// since the last save.
  static Future<void> saveChat(String uid) async {
    if (messages.isEmpty) return;
    try {
      // Dedupe guard — avoid re-writing identical state on every event
      final sig =
          '${effectiveSid ?? ''}|${messages.length}|${messages.last.text}';
      if (sig == _lastSavedSig) return;
      _lastSavedSig = sig;
      final prefs = await SharedPreferences.getInstance();
      final sid = effectiveSid ?? newLocalId();
      if (sessionId == null && localSessionId == null) localSessionId = sid;
      final entry = {
        'id': sid,
        'ts': DateTime.now().millisecondsSinceEpoch,
        'messages': messages
            .map((m) => {'role': m.role, 'text': m.text})
            .toList(),
      };
      // Active slot
      await prefs.setString(_activeKey(uid), jsonEncode(entry));
      // History list — upsert by sid
      final all = await loadAllSessions(uid);
      final idx = all.indexWhere((s) => s['id'] == sid);
      if (idx >= 0)
        all[idx] = entry;
      else
        all.insert(0, entry);
      final trimmed = all.length > 50 ? all.sublist(0, 50) : all;
      await prefs.setString(_storageKey(uid), jsonEncode(trimmed));
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
        messages.add(_ChatMsg(role: role, text: text));
        prevRole = role;
        prevText = text;
      }
      _lastSavedSig = null;
      return messages.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<void> clearAllHistory(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey(uid));
      await prefs.remove(_activeKey(uid));
    } catch (_) {}
  }

  static Future<void> clearActiveSlot(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_activeKey(uid));
    } catch (_) {}
  }

  // ── Token tracking ────────────────────────────────────────────────────────
  static Future<int> getUsedTokens(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_tokenKey(uid)) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> addTokens(String uid, int n) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getInt(_tokenKey(uid)) ?? 0;
      await prefs.setInt(_tokenKey(uid), current + n);
    } catch (_) {}
  }

  static Future<bool> isTokenLimitReached(String uid) async {
    if (_kCustomerDailyTokenLimit <= 0) return false; // unlimited
    return (await getUsedTokens(uid)) >= _kCustomerDailyTokenLimit;
  }

  static Future<int> tokenLimitRemaining(String uid) async {
    if (_kCustomerDailyTokenLimit <= 0) return 999999; // unlimited
    final used = await getUsedTokens(uid);
    return (_kCustomerDailyTokenLimit - used).clamp(
      0,
      _kCustomerDailyTokenLimit,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class CustomerSmartAI extends StatefulWidget {
  const CustomerSmartAI({super.key});

  @override
  // ignore: library_private_types_in_public_api
  State<CustomerSmartAI> createState() => _CustomerSmartAIState();
}

class _CustomerSmartAIState extends State<CustomerSmartAI> {
  // ── Brand colours ─────────────────────────────────────────────────────────
  static const _red = Color(0xFFE8001C);
  static const _bg = Color(0xFFF7F8FA);

  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  // Messages and session live in the static store — widget rebuild-safe
  List<_ChatMsg> get _messages => CustomerChatStore.messages;
  String? get _sessionId => CustomerChatStore.sessionId;
  set _sessionId(String? v) => CustomerChatStore.sessionId = v;

  String _customerUid = '';
  String _customerName = '';
  String _initials = '?';
  int _vehicleCount = 0;

  bool _dataLoaded = false;
  bool _tokenLimitReached = false;
  int _tokensRemaining = _kCustomerDailyTokenLimit;

  // ── Admin AI-pause state ───────────────────────────────────────────────────
  bool _aiPaused = false;
  String _aiPauseReason = '';

  // ── History drawer state ───────────────────────────────────────────────────
  bool _historyOpen = false;
  List<Map<String, dynamic>> _historySessions = [];

  bool _loading = false;
  http.Client? _activeClient; // held so we can close() it to cancel the request
  bool _backendOnline = true;
  bool get _rateLimited => CustomerChatStore.rateLimited;
  set _rateLimited(bool v) => CustomerChatStore.rateLimited = v;
  String get _resetIn => CustomerChatStore.resetIn;
  set _resetIn(String v) => CustomerChatStore.resetIn = v;

  // ─────────────────────────────────────────────────────────────────────────
  //  Init
  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _eagerRestoreSession(); // restore messages ASAP — skips the welcome flash
    _loadIdentity();
    _checkBackend(silent: true);
    _checkAiStatus();
  }

  /// Eagerly restore messages from SharedPreferences before identity loads.
  /// This prevents the loading spinner from showing when re-opening the chat
  /// with existing history — the conversation appears immediately.
  Future<void> _eagerRestoreSession() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || CustomerChatStore.messages.isNotEmpty) return;
    final restored = await CustomerChatStore.restoreActiveSession(user.uid);
    if (restored && mounted) setState(() {});
  }

  /// Checks the backend admin AI-settings to see if customer AI access
  /// has been paused by the admin, and retrieves the pause reason to show
  /// as a notice in the chat.
  Future<void> _checkAiStatus() async {
    try {
      final resp = await http
          .get(Uri.parse('$_kCustFlaskBase/api/ai-settings/public'))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final enabled = (data['customer_ai_enabled'] as bool?) ?? true;
        final reason = (data['pause_reason'] as String?) ?? '';
        if (mounted) {
          setState(() {
            _aiPaused = !enabled;
            _aiPauseReason = reason;
          });
        }
      }
    } catch (_) {
      // Silently fail — don't show errors for the status check
    }
  }

  @override
  void dispose() {
    // Save chat on widget dispose (navigation away)
    if (_customerUid.isNotEmpty && CustomerChatStore.messages.isNotEmpty) {
      CustomerChatStore.saveChat(_customerUid);
    }
    _activeClient?.close();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadIdentity() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _customerUid = user.uid;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final name = doc.data()?['name'] as String? ?? user.displayName ?? '';
    _customerName = name;

    if (name.isNotEmpty) {
      final parts = name.trim().split(' ').where((p) => p.isNotEmpty).toList();
      _initials = parts.length >= 2
          ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
          : parts[0][0].toUpperCase();
    }

    // ── Resolve company name ──────────────────────────────────────────────
    final companyName = doc.data()?['companyName'] as String? ?? '';

    if (name.isNotEmpty || companyName.isNotEmpty) {
      final nameLower = name.toLowerCase();
      final companyLower = companyName.toLowerCase();
      final seenIds = <String>{};

      // Pass 1: ownerId == user.uid
      final snapById = await FirebaseFirestore.instance
          .collection('vehicles')
          .where('ownerId', isEqualTo: _customerUid)
          .get();
      for (final d in snapById.docs) seenIds.add(d.id);

      // Pass 2a: owner == exact name
      if (name.isNotEmpty) {
        final snapByName = await FirebaseFirestore.instance
            .collection('vehicles')
            .where('owner', isEqualTo: name)
            .get();
        for (final d in snapByName.docs) seenIds.add(d.id);
      }

      // Pass 2b: owner == company name (if different)
      if (companyName.isNotEmpty && companyLower != nameLower) {
        final snapByCompany = await FirebaseFirestore.instance
            .collection('vehicles')
            .where('owner', isEqualTo: companyName)
            .get();
        for (final d in snapByCompany.docs) seenIds.add(d.id);
      }

      // Pass 3: case-insensitive scan — always run to catch capitalisation mismatches
      final allVehicles = await FirebaseFirestore.instance
          .collection('vehicles')
          .get();
      for (final d in allVehicles.docs) {
        if (seenIds.contains(d.id)) continue;
        final stored = ((d.data()['owner'] as String?) ?? '')
            .toLowerCase()
            .trim();
        if (stored.isNotEmpty &&
            ((nameLower.isNotEmpty && stored == nameLower) ||
                (companyLower.isNotEmpty && stored == companyLower))) {
          seenIds.add(d.id);
        }
      }

      _vehicleCount = seenIds.length;
    }

    // Restore active session from SharedPreferences BEFORE setting _dataLoaded,
    // so the first visible state after loading already shows the conversation
    // instead of briefly flashing the welcome/default screen.
    if (_messages.isEmpty) {
      await CustomerChatStore.restoreActiveSession(user.uid);
    }

    // Check daily token limit
    final limitReached = await CustomerChatStore.isTokenLimitReached(user.uid);
    final remaining = await CustomerChatStore.tokenLimitRemaining(user.uid);

    if (mounted) {
      setState(() {
        _dataLoaded = true;
        _tokenLimitReached = limitReached;
        _tokensRemaining = remaining;
      });
      // Scroll to bottom after restoring conversation
      if (_messages.isNotEmpty) _scrollToBottom();
    }
  }

  // ── History drawer ─────────────────────────────────────────────────────────

  Future<void> _openHistory() async {
    if (_customerUid.isEmpty) return;
    // Save current chat before opening history
    if (_messages.isNotEmpty) await CustomerChatStore.saveChat(_customerUid);
    final sessions = await CustomerChatStore.loadAllSessions(_customerUid);
    if (mounted)
      setState(() {
        _historySessions = sessions;
        _historyOpen = true;
      });
  }

  void _closeHistory() {
    if (mounted) setState(() => _historyOpen = false);
  }

  Future<void> _loadHistorySession(Map<String, dynamic> session) async {
    final msgs =
        (session['messages'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (msgs.isEmpty) return;
    final sid = session['id'] as String?;
    // Selected conversation becomes the active one — keep its id so new
    // messages append to the SAME history entry.
    if (sid != null && !sid.startsWith('local_')) {
      CustomerChatStore.sessionId = sid;
      CustomerChatStore.localSessionId = null;
    } else {
      CustomerChatStore.sessionId = null;
      CustomerChatStore.localSessionId = sid;
    }
    setState(() {
      CustomerChatStore.messages.clear();
      String? prevRole;
      String? prevText;
      for (final m in msgs) {
        final role = m['role'] as String? ?? 'ai';
        final text = m['text'] as String? ?? '';
        if (role == prevRole && text == prevText) continue; // skip duplicates
        CustomerChatStore.messages.add(_ChatMsg(role: role, text: text));
        prevRole = role;
        prevText = text;
      }
      CustomerChatStore._lastSavedSig = null; // persist the switch
      _historyOpen = false;
    });
    // Persist as active slot so app restart reopens this conversation
    if (_customerUid.isNotEmpty) {
      await CustomerChatStore.saveChat(_customerUid);
    }
    _scrollToBottom();
  }

  Future<void> _deleteAllHistory() async {
    if (!mounted) return;
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
    if (_customerUid.isNotEmpty) {
      await CustomerChatStore.clearAllHistory(_customerUid);
      if (_sessionId != null) {
        http
            .delete(Uri.parse('$_kCustAiBaseUrl/session/$_sessionId'))
            .catchError((_) => http.Response('', 200));
      }
      CustomerChatStore.clear();
    }
    if (!mounted) return;
    setState(() {
      _historySessions = [];
      _historyOpen = false;
    });
  }

  // ── New Chat ───────────────────────────────────────────────────────────────

  Future<void> _newChat() async {
    // Save current session to history before clearing
    if (_customerUid.isNotEmpty && _messages.isNotEmpty) {
      await CustomerChatStore.saveChat(_customerUid);
      await CustomerChatStore.clearActiveSlot(_customerUid);
    }
    // Clear server-side session memory (only real server sessions)
    final oldSid = _sessionId;
    if (oldSid != null && !oldSid.startsWith('local_')) {
      http
          .delete(Uri.parse('$_kCustAiBaseUrl/session/$oldSid'))
          .catchError((_) => http.Response('', 200));
    }
    if (mounted) {
      setState(() {
        // Genuinely NEW conversation id — old chat stays in history.
        // No empty entry is written until the first message is sent.
        CustomerChatStore.startNewSession();
      });
      // Scroll to top so the welcome screen is fully visible
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.jumpTo(0);
        }
      });
    }
  }

  // ── Stop generation ────────────────────────────────────────────────────────
  void _stopGeneration() {
    _activeClient?.close();
    _activeClient = null;
    if (mounted) {
      setState(() {
        _loading = false;
        _messages.add(_ChatMsg(role: 'ai', text: '⏹ Generation stopped.'));
      });
    }
    CustomerChatStore._lastSavedSig = null;
    if (_customerUid.isNotEmpty) CustomerChatStore.saveChat(_customerUid);
    _scrollToBottom();
  }

  Future<void> _checkBackend({bool silent = false}) async {
    if (!silent && mounted) setState(() => _backendOnline = false);
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        final r = await http
            .get(Uri.parse('$_kCustAiBaseUrl/health'))
            .timeout(
              const Duration(seconds: 60),
            ); // 60s covers Render cold-start (~30–50s)
        if (r.statusCode == 200) {
          if (mounted) setState(() => _backendOnline = true);
          return;
        }
      } catch (_) {
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

  // ─────────────────────────────────────────────────────────────────────────
  //  Send
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _send([String? preset]) async {
    final text = (preset ?? _inputCtrl.text).trim();
    if (text.isEmpty || _loading || _rateLimited || _aiPaused) return;

    // ── Customer daily token limit check ─────────────────────────────────
    if (_tokenLimitReached) return;
    if (_customerUid.isNotEmpty) {
      final limitHit = await CustomerChatStore.isTokenLimitReached(
        _customerUid,
      );
      if (limitHit) {
        if (mounted) setState(() => _tokenLimitReached = true);
        return;
      }
    }

    if (!_dataLoaded) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Still loading your profile, please wait…'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    setState(() {
      _messages.add(_ChatMsg(role: 'user', text: text));
      _inputCtrl.clear();
      _loading = true;
    });
    _scrollToBottom();
    CustomerChatStore._lastSavedSig = null; // user message changed state

    // Save user message immediately
    if (_customerUid.isNotEmpty) await CustomerChatStore.saveChat(_customerUid);

    try {
      final client = http.Client();
      _activeClient = client;
      final resp = await client
          .post(
            Uri.parse('$_kCustAiBaseUrl/customer/chat'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'message': text,
              'customer_uid': _customerUid,
              'customer_name': _customerName,
              'session_id': _sessionId,
            }),
          )
          .timeout(const Duration(seconds: 120));
      _activeClient = null;

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final reply = (data['reply'] as String? ?? '').trim();
        final answer = reply.isNotEmpty ? reply : 'No response generated.';

        // Adopt the server session id in place (rename stored history entry)
        // so no duplicate history item is created.
        final serverId = data['session_id'] as String?;
        if (serverId != null &&
            serverId.isNotEmpty &&
            _customerUid.isNotEmpty) {
          await CustomerChatStore.adoptServerSession(_customerUid, serverId);
        } else if (serverId != null && serverId.isNotEmpty) {
          _sessionId = serverId;
        }

        if (data['rate_limited'] == true) {
          final resetIn = data['reset_in'] as String? ?? 'some time';
          if (mounted) {
            setState(() {
              _loading = false;
              _rateLimited = true;
              _resetIn = resetIn;
              _messages.add(
                _ChatMsg(
                  role: 'ai',
                  text:
                      'AI Unavailable\n\nThe AI service has reached its daily token limit (Groq free tier).\n\nThe limit resets in $resetIn.\n\nYou cannot send new messages until the quota resets automatically.',
                  isRateLimit: true,
                ),
              );
            });
          }
          if (_customerUid.isNotEmpty)
            await CustomerChatStore.saveChat(_customerUid);
          return;
        }

        if (mounted) {
          // Generate related queries for AI response
          final relatedQueries = _generateRelatedQueries(text, answer);
          setState(() {
            _loading = false;
            _messages.add(_ChatMsg(
              role: 'ai',
              text: answer,
              relatedQueries: relatedQueries.isNotEmpty ? relatedQueries : null,
            ));
          });
        }

        // ── Track token usage (estimate ~1 token per 4 chars) ─────────────
        if (_customerUid.isNotEmpty) {
          final approxTokens = ((text.length + answer.length) / 4).ceil();
          await CustomerChatStore.addTokens(_customerUid, approxTokens);
          final limitHit = await CustomerChatStore.isTokenLimitReached(
            _customerUid,
          );
          final remaining = await CustomerChatStore.tokenLimitRemaining(
            _customerUid,
          );
          if (mounted) {
            setState(() {
              _tokenLimitReached = limitHit;
              _tokensRemaining = remaining;
            });
          }
          // Persist after AI reply
          await CustomerChatStore.saveChat(_customerUid);
        }
      } else {
        // Non-200 response — try to extract a friendly reply from the body first
        String errorMsg =
            "I'm having trouble processing your request right now. Please try again in a moment, or contact us at caltexautopro2026@gmail.com if the issue persists.";
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
        if (mounted) {
          setState(() {
            _loading = false;
            _messages.add(_ChatMsg(role: 'ai', text: errorMsg));
          });
        }
        if (_customerUid.isNotEmpty)
          await CustomerChatStore.saveChat(_customerUid);
      }
    } on http.ClientException catch (e) {
      // If _activeClient is null, the request was cancelled intentionally — ignore
      if (_activeClient == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      _activeClient = null;
      if (mounted) {
        setState(() {
          _loading = false;
          _messages.add(
            _ChatMsg(
              role: 'ai',
              text:
                  'Cannot reach the AI service. Please check your internet connection and try again.',
            ),
          );
        });
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _messages.add(
            _ChatMsg(
              role: 'ai',
              text:
                  e.toString().contains('Timeout') ||
                      e.toString().contains('timed out')
                  ? 'The request took too long. Please check your connection and try again.'
                  : "I'm having trouble processing your request right now. Please try again in a moment.",
            ),
          );
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

  // ─────────────────────────────────────────────────────────────────────────
  //  Build
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
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
            // AI logo in AppBar — clean STATIC logo (moving rings live on the
            // dashboard floating bubble only); border still reflects status.
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
                              : const Color(0xFFF97316),
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
            onPressed: _newChat,
          ),
          // History button
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
                final oldSid = _sessionId;
                if (oldSid != null && !oldSid.startsWith('local_')) {
                  http
                      .delete(Uri.parse('$_kCustAiBaseUrl/session/$oldSid'))
                      .catchError((_) => http.Response('', 200));
                }
                if (_customerUid.isNotEmpty) {
                  await CustomerChatStore.saveChat(_customerUid);
                  await CustomerChatStore.clearActiveSlot(_customerUid);
                }
                setState(() {
                  // Genuinely NEW conversation id — old chat stays in history.
                  CustomerChatStore.startNewSession();
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
              // ── Offline banner ──────────────────────────────────────────
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

              // ── Admin AI-paused banner ──────────────────────────────────
              if (_aiPaused)
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
                        Icons.pause_circle_filled,
                        size: 18,
                        color: Color(0xFF9A3412),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'AI Assistant is temporarily unavailable',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF9A3412),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _aiPauseReason.isNotEmpty
                                  ? _aiPauseReason
                                  : 'The AI Assistant has been temporarily paused by the admin. Please try again later.',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF9A3412),
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              // ── Groq rate-limit banner ──────────────────────────────────
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

              // ── Customer daily token-limit banner ───────────────────────
              if (_tokenLimitReached)
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
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF9A3412),
                              height: 1.5,
                            ),
                            children: [
                              const TextSpan(
                                text: 'Daily message limit reached\n',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12.5,
                                ),
                              ),
                              TextSpan(
                                text:
                                    "You've used your $_kCustomerDailyTokenLimit-token daily allowance. "
                                    'Your quota resets at midnight tonight. '
                                    'You can still view your chat history.',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // ── Low-token warning (< 400 remaining) ────────────────────
              if (!_tokenLimitReached &&
                  _tokensRemaining < 400 &&
                  _tokensRemaining > 0)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFFBEB),
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFFCD34D), width: 1.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        size: 14,
                        color: Color(0xFF92400E),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Running low — ~$_tokensRemaining tokens remaining today.',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF92400E),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // ── Chat / Welcome ──────────────────────────────────────────
              Expanded(
                child: !_dataLoaded && _messages.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: _red),
                            SizedBox(height: 12),
                            Text(
                              'Loading your profile…',
                              style: TextStyle(
                                color: Color(0xFF718096),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      )
                    : _messages.isEmpty
                    ? _buildWelcome()
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length + (_loading ? 1 : 0),
                        itemBuilder: (_, i) {
                          if (_loading && i == _messages.length)
                            return _buildTypingIndicator();
                          return _buildBubble(_messages[i]);
                        },
                      ),
              ),

              // ── Input bar ───────────────────────────────────────────────
              SafeArea(
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _FocusInputBar(
                        inputCtrl: _inputCtrl,
                        loading: _loading,
                        rateLimited:
                            _rateLimited || _tokenLimitReached || _aiPaused,
                        hint: _aiPaused
                            ? 'AI Assistant is temporarily unavailable'
                            : _tokenLimitReached
                            ? 'Daily message limit reached — resets tomorrow'
                            : _rateLimited
                            ? 'AI unavailable — daily limit reached'
                            : 'Ask about your vehicles, bookings, or services…',
                        onSend: _send,
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

          // ── History overlay ───────────────────────────────────────────────
          if (_historyOpen)
            GestureDetector(
              onTap: _closeHistory,
              child: Container(color: Colors.black.withValues(alpha: 0.35)),
            ),

          // ── History drawer (slides in from right) ─────────────────────────
          AnimatedPositioned(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOut,
            top: 0,
            bottom: 0,
            right: _historyOpen ? 0 : -340,
            child: _buildHistoryDrawer(),
          ),
        ],
      ),
    );
  }

  // ── History drawer widget ──────────────────────────────────────────────────
  Widget _buildHistoryDrawer() {
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));

    String dayLabel(DateTime d) {
      if (d.year == today.year &&
          d.month == today.month &&
          d.day == today.day) {
        return 'Today';
      }
      if (d.year == yesterday.year &&
          d.month == yesterday.month &&
          d.day == yesterday.day) {
        return 'Yesterday';
      }
      return '${_monthAbbr(d.month)} ${d.day}, ${d.year}';
    }

    return Material(
      elevation: 8,
      child: Container(
        width: 300,
        color: Colors.white,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 48, 16, 14),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFc62828), Color(0xFFE8001C)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.history, color: Colors.white, size: 18),
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
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Delete all button
            GestureDetector(
              onTap: _deleteAllHistory,
              child: Container(
                margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF5F5),
                  border: Border.all(
                    color: const Color(0xFFFCA5A5),
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.delete_outline,
                      color: Color(0xFFDC2626),
                      size: 14,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Delete All Chats',
                      style: TextStyle(
                        color: Color(0xFFDC2626),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
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
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                      itemCount: _historySessions.length,
                      itemBuilder: (_, i) {
                        final s = _historySessions[i];
                        final ts = DateTime.fromMillisecondsSinceEpoch(
                          (s['ts'] as int?) ?? 0,
                        );
                        final day = dayLabel(ts);
                        final showLabel =
                            i == 0 ||
                            dayLabel(
                                  DateTime.fromMillisecondsSinceEpoch(
                                    (_historySessions[i - 1]['ts'] as int?) ??
                                        0,
                                  ),
                                ) !=
                                day;
                        final msgs =
                            (s['messages'] as List?)
                                ?.cast<Map<String, dynamic>>() ??
                            [];
                        final firstUser = msgs.firstWhere(
                          (m) => m['role'] == 'user',
                          orElse: () => {'text': '(empty)'},
                        );
                        final preview =
                            firstUser['text'] as String? ?? '(empty)';
                        final time =
                            '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';
                        final isActive =
                            s['id'] == CustomerChatStore.effectiveSid;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (showLabel)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 10,
                                  bottom: 6,
                                ),
                                child: Text(
                                  day.toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF94A3B8),
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ),
                            GestureDetector(
                              onTap: () => _loadHistorySession(s),
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      preview.length > 60
                                          ? '${preview.substring(0, 60)}…'
                                          : preview,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF1A202C),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '$time · ${msgs.length} message${msgs.length != 1 ? 's' : ''}',
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        color: Color(0xFF94A3B8),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _monthAbbr(int m) => const [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ][m - 1];

  // ─────────────────────────────────────────────────────────────────────────
  //  Welcome screen
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildWelcome() {
    final first = _customerName.isNotEmpty
        ? _customerName.split(' ').first
        : '';
    final sub = first.isEmpty
        ? 'Choose a quick query below or ask me anything about your vehicles, bookings, or services.'
        : _vehicleCount > 0
        ? 'Hi $first! You have $_vehicleCount registered '
              'vehicle${_vehicleCount != 1 ? 's' : ''}. How can I help you today?'
        : 'Hi $first! No vehicles are registered under your account yet.';

    // Six quick query cards with titles, descriptions, and icons
    final quickQueries = [
      {
        'title': 'My Vehicle',
        'desc': 'View your vehicle information',
        'icon': Icons.directions_car_outlined,
        'query': 'Show my vehicle information and status',
      },
      {
        'title': 'Book a Service',
        'desc': 'Schedule your vehicle maintenance',
        'icon': Icons.calendar_today_outlined,
        'query': 'I want to book a service for my vehicle',
      },
      {
        'title': 'Service History',
        'desc': 'View your previous vehicle services',
        'icon': Icons.history_outlined,
        'query': 'Show my complete service history',
      },
      {
        'title': 'Maintenance Schedule',
        'desc': 'Check your upcoming maintenance',
        'icon': Icons.schedule_outlined,
        'query': 'When is my next maintenance due?',
      },
      {
        'title': 'Services & Pricing',
        'desc': 'Explore services and estimated costs',
        'icon': Icons.attach_money_outlined,
        'query': 'What services do you offer and what are the prices?',
      },
      {
        'title': 'My Booking Status',
        'desc': 'Check your service appointment',
        'icon': Icons.info_outline,
        'query': 'What is the status of my booking?',
      },
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // AI logo
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF22c55e),
                width: 2.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF22c55e).withValues(alpha: 0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipOval(
              child: Image.asset('assets/img/AI_LOGO.png', fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Hey, how can I help?',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1a202c),
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            sub,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF94a3b8),
              height: 1.6,
            ),
          ),
          const SizedBox(height: 24),
          ...quickQueries.map(
            (q) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GestureDetector(
                onTap: () => _send(q['query'] as String),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
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
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFFF5F5), Color(0xFFFFE4E6)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Icon(
                          q['icon'] as IconData,
                          color: const Color(0xFFE8001C),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              q['title'] as String,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1a202c),
                                height: 1.3,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              q['desc'] as String,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF718096),
                                height: 1.5,
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
          ),
        ],
      ),
    );
  }
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

  // ─────────────────────────────────────────────────────────────────────────
  //  Typing indicator — 3 bouncing dots (matches website animation)
  // ─────────────────────────────────────────────────────────────────────────
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

  // ─────────────────────────────────────────────────────────────────────────
  //  Chat bubbles
  // ─────────────────────────────────────────────────────────────────────────
  
  // Generate 3 contextually relevant follow-up queries (customer-specific)
  List<String> _generateRelatedQueries(String userQuery, String aiResponse) {
    final q = userQuery.toLowerCase();
    final resp = aiResponse.toLowerCase();

    // Define customer-specific query bank
    final queryBank = {
      'vehicle': [
        'Show my vehicle maintenance history',
        'When is my next service due?',
        'What are common issues for my vehicle?',
        'Show my vehicle warranty status',
        'Update my vehicle mileage'
      ],
      'booking': [
        'Book another service appointment',
        'Reschedule my current booking',
        'What services are included in my booking?',
        'Cancel my appointment',
        'What are your available time slots?'
      ],
      'history': [
        'Show my most recent service',
        'What repairs have been done?',
        'Generate my service history report',
        'Show service costs over time',
        'What parts were replaced?'
      ],
      'pricing': [
        'Get a quote for oil change',
        'What is included in basic service?',
        'Do you offer service packages?',
        'Compare service prices',
        'What payment methods do you accept?'
      ],
      'maintenance': [
        'What maintenance is overdue?',
        'Show my PMS schedule',
        'Set reminders for next service',
        'What is the recommended service interval?',
        'Show maintenance alerts'
      ],
      'general': [
        'Show my vehicle information',
        'Book a service',
        'View my service history',
        'Check service pricing',
        'What are your operating hours?'
      ]
    };

    // Determine context
    String context = 'general';
    if (RegExp(r'vehicle|car|plate|registration', caseSensitive: false)
        .hasMatch('$q $resp')) {
      context = 'vehicle';
    } else if (RegExp(r'book|appointment|schedule|reservation',
            caseSensitive: false)
        .hasMatch('$q $resp')) {
      context = 'booking';
    } else if (RegExp(r'history|past|previous|completed', caseSensitive: false)
        .hasMatch('$q $resp')) {
      context = 'history';
    } else if (RegExp(r'price|cost|quote|payment|fee', caseSensitive: false)
        .hasMatch('$q $resp')) {
      context = 'pricing';
    } else if (RegExp(r'maintenance|service|pms|due|overdue',
            caseSensitive: false)
        .hasMatch('$q $resp')) {
      context = 'maintenance';
    }

    // Get relevant queries and shuffle
    final relevantQueries = queryBank[context] ?? queryBank['general']!;
    final shuffled = List<String>.from(relevantQueries)..shuffle();

    // Filter out queries too similar to current user query
    final filtered = shuffled
        .where((sq) =>
            !sq.toLowerCase().contains(q) && !q.contains(sq.toLowerCase()))
        .toList();

    // Return first 3
    return filtered.take(3).toList();
  }

  Widget _buildBubble(_ChatMsg msg) {
    // ── User bubble ──
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
                          color: _red.withValues(alpha: 0.22),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: Text(
                      msg.text,
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
                            ClipboardData(text: msg.text),
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
                              final editCtrl = TextEditingController(
                                text: msg.text,
                              );
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
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Message cannot be empty',
                                            ),
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                        return;
                                      }
                                      if (editedText == msg.text) {
                                        Navigator.pop(ctx);
                                        return;
                                      }
                                      Navigator.pop(ctx);

                                      // Remove this message and all after it
                                      setState(() {
                                        _messages.removeRange(
                                          msgIndex,
                                          _messages.length,
                                        );
                                      });

                                      // Send edited message
                                      _inputCtrl.text = editedText;
                                      _send();
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

    // ── Rate-limit card ──
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
                              text:
                                  '.\n\nYou cannot send new messages until the limit resets automatically.',
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

    // ── AI bubble (matches website: white card, rounded, left-aligned) ──
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _aiAvatar(),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.78,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: _aiBubbleDecoration(),
                  child: _renderMarkdown(msg.text),
                ),
                // Copy button and timestamp
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 2),
                  child: Row(
                    children: [
                      // Copy button for AI responses
                      _userPromptActionBtn(
                        icon: Icons.copy_outlined,
                        label: 'Copy',
                        onTap: () async {
                          await Clipboard.setData(
                            ClipboardData(text: msg.text),
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
                      const SizedBox(width: 10),
                      const Text(
                        'AI Assistant',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF94a3b8),
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Text(
                        '·',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFFcbd5e0),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _formatTimestamp(msg.timestamp ?? DateTime.now()),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF94a3b8),
                        ),
                      ),
                    ],
                  ),
                ),
                // Related query chips
                if (msg.relatedQueries != null && msg.relatedQueries!.isNotEmpty && !_loading) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: msg.relatedQueries!
                        .map(
                          (query) => GestureDetector(
                            onTap: () => _send(query),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8F9FB),
                                border: Border.all(
                                  color: const Color(0xFFe2e8f0),
                                  width: 1.5,
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                query,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF475569),
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Format timestamp to HH:MM AM/PM
  String _formatTimestamp(DateTime dt) {
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  // ── Shared decoration for AI bubble ──
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

  // ── AI avatar — white background, status-colour border ──
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

  // ── Simple markdown renderer for AI responses ──
  Widget _renderMarkdown(String text) {
    // Replace <br> tags with newlines before processing
    text = text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');

    final spans = <TextSpan>[];
    final lines = text.split('\n');

    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      final lineSpans = <InlineSpan>[];

      // Check for bullet point
      if (line.startsWith('• ') ||
          line.startsWith('- ') ||
          line.startsWith('* ')) {
        lineSpans.add(
          const TextSpan(
            text: '• ',
            style: TextStyle(
              color: Color(0xFFE8001C),
              fontWeight: FontWeight.bold,
            ),
          ),
        );
        line = line.substring(2);
      }

      // Process bold (**text**, __text__, or <b>text</b>)
      final boldPattern = RegExp(r'\*\*(.+?)\*\*|__(.+?)__|<b>(.+?)</b>');
      var lastIndex = 0;

      for (final match in boldPattern.allMatches(line)) {
        // Add text before the match
        if (match.start > lastIndex) {
          lineSpans.add(TextSpan(text: line.substring(lastIndex, match.start)));
        }

        // Add bold text (check all three groups: **, __, and <b>)
        final boldText =
            match.group(1) ?? match.group(2) ?? match.group(3) ?? '';
        lineSpans.add(
          TextSpan(
            text: boldText,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        );

        lastIndex = match.end;
      }

      // Add remaining text
      if (lastIndex < line.length) {
        lineSpans.add(TextSpan(text: line.substring(lastIndex)));
      }

      spans.add(TextSpan(children: lineSpans));

      // Add line break if not the last line
      if (i < lines.length - 1) {
        spans.add(const TextSpan(text: '\n'));
      }
    }

    return SelectableText.rich(
      TextSpan(
        children: spans,
        style: const TextStyle(
          fontSize: 13,
          color: Color(0xFF1a202c),
          height: 1.6,
        ),
      ),
    );
  }

  // ── User prompt action button (Copy / Edit) ──
  Widget _userPromptActionBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F6F9),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: const Color(0xFF64748B)),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── User avatar — gradient red with initials ──
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
          fontWeight: FontWeight.bold,
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Focused input bar — matches admin/website wrapped input style
// ─────────────────────────────────────────────────────────────────────────────
class _FocusInputBar extends StatefulWidget {
  final TextEditingController inputCtrl;
  final bool loading;
  final bool rateLimited;
  final String hint;
  final Future<void> Function([String?]) onSend;
  final VoidCallback? onStop;

  const _FocusInputBar({
    required this.inputCtrl,
    required this.loading,
    required this.rateLimited,
    required this.hint,
    required this.onSend,
    this.onStop,
  });

  @override
  State<_FocusInputBar> createState() => _FocusInputBarState();
}

class _FocusInputBarState extends State<_FocusInputBar> {
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
          // Stop button — shown while generating
          if (widget.loading && widget.onStop != null)
            GestureDetector(
              onTap: widget.onStop,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE8001C), Color(0xFFC0001A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE8001C).withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.stop_rounded,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            )
          // Send button — shown when idle
          else
            GestureDetector(
              onTap: canSend ? () => widget.onSend() : null,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: canSend
                      ? const LinearGradient(
                          colors: [Color(0xFFE8001C), Color(0xFFC0001A)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: canSend ? null : Colors.grey.shade300,
                  shape: BoxShape.circle,
                  boxShadow: canSend
                      ? [
                          BoxShadow(
                            color: const Color(
                              0xFFE8001C,
                            ).withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : [],
                ),
                child: const Icon(
                  Icons.send_rounded,
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

// ─────────────────────────────────────────────────────────────────────────────
//  Bouncing dots — same animation as website / admin AI
// ─────────────────────────────────────────────────────────────────────────────
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
class _ChatMsg {
  final String role;
  final String text;
  final bool isRateLimit;
  final DateTime? timestamp;
  final List<String>? relatedQueries;

  _ChatMsg({
    required this.role,
    required this.text,
    this.isRateLimit = false,
    DateTime? timestamp,
    this.relatedQueries,
  }) : timestamp = timestamp ?? DateTime.now();
}
