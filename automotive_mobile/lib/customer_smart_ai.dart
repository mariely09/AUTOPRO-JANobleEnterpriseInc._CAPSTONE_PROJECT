import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Base URL of the ai_assistant FastAPI service.
// ─────────────────────────────────────────────────────────────────────────────
const _kCustAiBaseUrl = String.fromEnvironment(
  'AI_BACKEND_URL',
  defaultValue: 'https://caltex-autopro-capstone-project.onrender.com',
);

// ─────────────────────────────────────────────────────────────────────────────
// Static chat store — survives page navigation (cleared on logout/refresh/delete)
// ─────────────────────────────────────────────────────────────────────────────
class CustomerChatStore {
  static final List<_ChatMsg> messages = [];
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

class CustomerSmartAI extends StatefulWidget {
  const CustomerSmartAI({super.key});

  @override
  // ignore: library_private_types_in_public_api
  State<CustomerSmartAI> createState() => _CustomerSmartAIState();
}

class _CustomerSmartAIState extends State<CustomerSmartAI> {
  // ── Brand colours ─────────────────────────────────────────────────────────
  static const _red  = Color(0xFFE8001C);
  static const _bg   = Color(0xFFF7F8FA);

  final _inputCtrl  = TextEditingController();
  final _scrollCtrl = ScrollController();

  // Messages and session live in the static store — widget rebuild-safe
  List<_ChatMsg> get _messages => CustomerChatStore.messages;
  String? get _sessionId => CustomerChatStore.sessionId;
  set _sessionId(String? v) => CustomerChatStore.sessionId = v;

  String _customerUid   = '';
  String _customerName  = '';
  String _initials      = '?';
  int    _vehicleCount  = 0;

  bool _dataLoaded    = false;
  bool _loading       = false;
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
    _loadIdentity();
    _checkBackend(silent: true);
    _checkAiStatus();
  }

  /// Checks the backend AI key status on startup.
  /// If at least one key is active (not rate-limited), clears any stale
  /// _rateLimited flag left over from a previous session.
  Future<void> _checkAiStatus() async {
    try {
      final r = await http
          .get(Uri.parse('$_kCustAiBaseUrl/ai-settings/status'))
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

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadIdentity() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _customerUid = user.uid;

    final doc = await FirebaseFirestore.instance
        .collection('users').doc(user.uid).get();
    final name = doc.data()?['name'] as String? ?? user.displayName ?? '';
    _customerName = name;

    if (name.isNotEmpty) {
      final parts = name.trim().split(' ').where((p) => p.isNotEmpty).toList();
      _initials = parts.length >= 2
          ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
          : parts[0][0].toUpperCase();

      // Query by ownerId (Firebase UID) — most reliable
      final snapById = await FirebaseFirestore.instance
          .collection('vehicles')
          .where('ownerId', isEqualTo: _customerUid)
          .get();
      // Fallback: query by owner name for older documents
      final snapByName = await FirebaseFirestore.instance
          .collection('vehicles')
          .where('owner', isEqualTo: name)
          .get();
      // Deduplicate by doc ID
      final seenIds = <String>{};
      for (final doc in snapById.docs) seenIds.add(doc.id);
      for (final doc in snapByName.docs) seenIds.add(doc.id);
      _vehicleCount = seenIds.length;
    }

    if (mounted) setState(() => _dataLoaded = true);
  }

  Future<void> _checkBackend({bool silent = false}) async {
    if (!silent && mounted) setState(() => _backendOnline = false);
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        final r = await http
            .get(Uri.parse('$_kCustAiBaseUrl/health'))
            .timeout(const Duration(seconds: 20));
        if (r.statusCode == 200) {
          if (mounted) setState(() => _backendOnline = true);
          return;
        }
      } catch (_) {
        if (attempt < 3) await Future.delayed(const Duration(seconds: 5));
      }
    }
    if (!silent && mounted) setState(() => _backendOnline = false);
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
    if (text.isEmpty || _loading || _rateLimited) return;

    if (!_dataLoaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Still loading your profile, please wait…'),
            duration: Duration(seconds: 2)),
      );
      return;
    }

    setState(() {
      _messages.add(_ChatMsg(role: 'user', text: text));
      _inputCtrl.clear();
      _loading = true;
    });
    _scrollToBottom();

    try {
      final resp = await http
          .post(
            Uri.parse('$_kCustAiBaseUrl/customer/chat'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'message':       text,
              'customer_uid':  _customerUid,
              'customer_name': _customerName,
              'session_id':    _sessionId,
            }),
          )
          .timeout(const Duration(seconds: 120));

      if (resp.statusCode == 200) {
        final data  = jsonDecode(resp.body) as Map<String, dynamic>;
        final reply = (data['reply'] as String? ?? '').trim();
        final answer = reply.isNotEmpty ? reply : 'No response generated.';

        if (data['session_id'] != null) {
          _sessionId = data['session_id'] as String;
        }

        if (data['rate_limited'] == true) {
          final resetIn = data['reset_in'] as String? ?? 'some time';
          if (mounted) {
            setState(() {
              _loading = false;
              _rateLimited = true;
              _resetIn = resetIn;
              _messages.add(_ChatMsg(
                role: 'ai',
                text: 'AI Unavailable\n\nThe AI service has reached its daily token limit (Groq free tier).\n\nThe limit resets in $resetIn.\n\nYou cannot send new messages until the quota resets automatically.',
                isRateLimit: true,
              ));
            });
          }
          return;
        }

        if (mounted) {
          setState(() {
            _loading = false;
            _messages.add(_ChatMsg(role: 'ai', text: answer));
          });
        }
      } else {
        final err = _parseError(resp.body);
        if (mounted) {
          setState(() {
            _loading = false;
            _messages.add(_ChatMsg(role: 'ai', text: 'AI service error (${resp.statusCode}): $err'));
          });
        }
      }
    } on http.ClientException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _messages.add(_ChatMsg(role: 'ai',
              text: 'Cannot reach the AI service.\n\nPlease check your internet connection.\n\nError: $e'));
        });
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _messages.add(_ChatMsg(role: 'ai',
              text: e.toString().contains('Timeout') || e.toString().contains('timed out')
                  ? 'Request timed out. Please check your connection and try again.'
                  : 'Unexpected error: $e'));
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
        backgroundColor: _red,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Row(
          children: [
            Container(
              width: 40, height: 40,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 2),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8)],
              ),
              child: ClipOval(
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Image.asset('assets/img/AI_LOGO.png', fit: BoxFit.contain),
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'AI Assistant',
                    style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7, height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _backendOnline ? const Color(0xFF4ade80) : Colors.orange,
                          boxShadow: [BoxShadow(
                            color: _backendOnline
                                ? const Color(0xFF4ade80).withValues(alpha: 0.8)
                                : Colors.orange.withValues(alpha: 0.6),
                            blurRadius: 6,
                          )],
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _backendOnline ? 'Online' : 'Offline',
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
          if (_messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.white),
              tooltip: 'Clear chat',
              onPressed: () {
                if (_sessionId != null) {
                  http.delete(Uri.parse('$_kCustAiBaseUrl/session/$_sessionId'))
                      .catchError((_) => http.Response('', 200));
                }
                setState(() {
                  CustomerChatStore.clear();
                });
              },
            ),
        ],
      ),
      body: Column(children: [
        // ── Offline banner ───────────────────────────────────────────────
        if (!_backendOnline && _dataLoaded)
          Container(
            width: double.infinity,
            color: const Color(0xFFFFFBEB),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFF975A16)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Cannot reach AI backend. Tap Retry.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF975A16))),
              ),
              GestureDetector(
                onTap: () => _checkBackend(),
                child: const Text('Retry',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF975A16))),
              ),
            ]),
          ),

        // ── Rate-limit banner ────────────────────────────────────────────
        if (_rateLimited)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFFFF7ED),
              border: Border(bottom: BorderSide(color: Color(0xFFFB923C), width: 2)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.block, size: 18, color: Color(0xFF9A3412)),
              const SizedBox(width: 10),
              Expanded(child: RichText(
                text: TextSpan(
                  style: const TextStyle(fontSize: 12, color: Color(0xFF9A3412), height: 1.5),
                  children: [
                    const TextSpan(
                      text: 'AI unavailable — daily token limit reached\n',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                    ),
                    const TextSpan(text: 'Groq free-tier quota is exhausted. Resets in '),
                    TextSpan(
                        text: _resetIn,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const TextSpan(text: '. Chat is disabled until then.'),
                  ],
                ),
              )),
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

        // ── Chat / Welcome ───────────────────────────────────────────────
        Expanded(
          child: !_dataLoaded
              ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  CircularProgressIndicator(color: _red),
                  SizedBox(height: 12),
                  Text('Loading your profile…',
                      style: TextStyle(color: Color(0xFF718096), fontSize: 13)),
                ]))
              : _messages.isEmpty
                  ? _buildWelcome()
                  : ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length + (_loading ? 1 : 0),
                      itemBuilder: (_, i) {
                        if (_loading && i == _messages.length) return _buildTypingIndicator();
                        return _buildBubble(_messages[i]);
                      },
                    ),
        ),

        // ── Input bar ────────────────────────────────────────────────────
        SafeArea(
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _FocusInputBar(
                inputCtrl: _inputCtrl,
                loading: _loading,
                rateLimited: _rateLimited,
                hint: _rateLimited
                    ? 'AI unavailable — daily limit reached'
                    : 'Ask about your vehicles, bookings, or services…',
                onSend: _send,
              ),
              const SizedBox(height: 4),
              const Text(
                'Enter to send  ·  Shift+Enter for new line',
                style: TextStyle(fontSize: 10, color: Color(0xFFC0C8D4)),
                textAlign: TextAlign.center,
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Welcome screen
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildWelcome() {
    final first = _customerName.isNotEmpty ? _customerName.split(' ').first : '';
    final sub = first.isEmpty
        ? 'Ask me anything about your vehicles — PMS status, history, costs, and more.'
        : _vehicleCount > 0
            ? 'Hi $first! You have $_vehicleCount registered '
              'vehicle${_vehicleCount != 1 ? 's' : ''}. Ask me anything about them.'
            : 'Hi $first! No vehicles are registered under your account yet.';

    final suggestions = [
      'List all my registered vehicles',
      'Give me a fleet summary',
      'Which of my vehicles are under maintenance?',
      'Which vehicles have PMS overdue?',
      'Which vehicles have PMS due soon?',
      'Show my complete service history',
      'Show my upcoming and past bookings',
      'What services do you offer and what are the prices?',
      'How much would a change oil and brake cleaning cost?',
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
        // AI logo — transparent circle with image
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFE8001C).withValues(alpha: 0.2), width: 2),
            boxShadow: [BoxShadow(color: const Color(0xFFE8001C).withValues(alpha: 0.12), blurRadius: 16)],
          ),
          child: ClipOval(
            child: Image.asset('assets/img/AI_LOGO.png', fit: BoxFit.cover),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'AI Assistant',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1a202c)),
        ),
        const SizedBox(height: 6),
        Text(
          sub,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: Color(0xFF718096), height: 1.5),
        ),
        const SizedBox(height: 24),
        ...suggestions.map((s) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GestureDetector(
            onTap: () => _send(s),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFe8edf2), width: 1.5),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4)],
              ),
              child: Row(children: [
                Container(
                  width: 7, height: 7,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE8001C),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    s,
                    style: const TextStyle(fontSize: 13, color: Color(0xFF4a5568), fontWeight: FontWeight.w500),
                  ),
                ),
              ]),
            ),
          ),
        )),
      ]),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Typing indicator — 3 bouncing dots (matches website animation)
  // ─────────────────────────────────────────────────────────────────────────
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

  // ─────────────────────────────────────────────────────────────────────────
  //  Chat bubbles
  // ─────────────────────────────────────────────────────────────────────────
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
              child: Container(
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE8001C), Color(0xFFC41E3A)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16), topRight: Radius.circular(4),
                    bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
                  boxShadow: [BoxShadow(color: _red.withValues(alpha: 0.22), blurRadius: 6)],
                ),
                child: Text(msg.text,
                    style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.6)),
              ),
            ),
            const SizedBox(width: 8),
            _userAvatar(),
          ],
        ),
      );
    }

    // ── Rate-limit card ──
    if (msg.isRateLimit) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _aiAvatar(),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.80),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4), topRight: Radius.circular(14),
                  bottomLeft: Radius.circular(14), bottomRight: Radius.circular(14)),
                border: Border.all(color: const Color(0xFFFB923C), width: 1.5),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: const BoxDecoration(
                    color: Color(0xFFEA580C),
                    borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(2), topRight: Radius.circular(13))),
                  child: const Row(children: [
                    Icon(Icons.block, color: Colors.white, size: 14),
                    SizedBox(width: 8),
                    Text('AI Service Unavailable',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: RichText(text: TextSpan(
                    style: const TextStyle(fontSize: 12.5, color: Color(0xFF9A3412), height: 1.55),
                    children: [
                      const TextSpan(text: 'Daily token limit reached.\n\n',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const TextSpan(text: 'Resets in '),
                      TextSpan(
                          text: _resetIn.isNotEmpty ? _resetIn : 'some time',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      const TextSpan(text: '.\n\nYou cannot send new messages until the limit resets automatically.'),
                    ],
                  )),
                ),
              ]),
            ),
          ),
        ]),
      );
    }

    // ── AI bubble (matches website: white card, rounded, left-aligned) ──
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        _aiAvatar(),
        const SizedBox(width: 8),
        Flexible(
          child: Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: _aiBubbleDecoration(),
            child: SelectableText(
              msg.text,
              style: const TextStyle(fontSize: 13, color: Color(0xFF1a202c), height: 1.6),
            ),
          ),
        ),
      ]),
    );
  }

  // ── Shared decoration for AI bubble ──
  BoxDecoration _aiBubbleDecoration() => BoxDecoration(
    color: Colors.white,
    borderRadius: const BorderRadius.only(
      topLeft: Radius.circular(4), topRight: Radius.circular(16),
      bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
  );

  // ── AI avatar — uses AI_LOGO image, transparent background ──
  Widget _aiAvatar() => Container(
    width: 32, height: 32,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: const Color(0xFFe2e8f0), width: 1.5),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4)],
    ),
    child: ClipOval(
      child: Image.asset('assets/img/AI_LOGO.png', fit: BoxFit.cover),
    ),
  );

  // ── User avatar — gradient red with initials ──
  Widget _userAvatar() => Container(
    width: 30, height: 30,
    decoration: const BoxDecoration(
      gradient: LinearGradient(
          colors: [Color(0xFFE8001C), Color(0xFFC41E3A)],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
      shape: BoxShape.circle,
    ),
    child: Center(
      child: Text(_initials,
          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
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

  const _FocusInputBar({
    required this.inputCtrl,
    required this.loading,
    required this.rateLimited,
    required this.hint,
    required this.onSend,
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
            ? [BoxShadow(color: const Color(0xFFE8001C).withValues(alpha: 0.08), blurRadius: 8)]
            : [],
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: TextField(
            controller: widget.inputCtrl,
            maxLines: 4,
            minLines: 1,
            enabled: canSend,
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF718096)),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 6),
            ),
            style: const TextStyle(fontSize: 13, color: Color(0xFF1a202c)),
            onTap: () => setState(() => _focused = true),
            onEditingComplete: () => setState(() => _focused = false),
            textInputAction: TextInputAction.send,
            onSubmitted: (_) { widget.onSend(); },
          ),
        ),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: canSend ? () => widget.onSend() : null,
          child: Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              gradient: canSend
                  ? const LinearGradient(
                      colors: [Color(0xFFE8001C), Color(0xFFC0001A)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight)
                  : null,
              color: canSend ? null : Colors.grey.shade300,
              shape: BoxShape.circle,
              boxShadow: canSend
                  ? [BoxShadow(color: const Color(0xFFE8001C).withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 3))]
                  : [],
            ),
            child: const Icon(Icons.send_rounded, color: Colors.white, size: 16),
          ),
        ),
      ]),
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

class _BouncingDotsState extends State<_BouncingDots> with TickerProviderStateMixin {
  late final List<AnimationController> _ctrls;
  late final List<Animation<double>> _anims;

  @override
  void initState() {
    super.initState();
    _ctrls = List.generate(3, (i) => AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true));
    _anims = List.generate(3, (i) => Tween<double>(begin: 0, end: -5).animate(
      CurvedAnimation(parent: _ctrls[i],
          curve: Interval(i * 0.15, i * 0.15 + 0.6, curve: Curves.easeInOut))));
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
                  color: Color(0xFFA0AEC0), shape: BoxShape.circle),
            ),
          ),
        ),
      ],
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class _ChatMsg {
  final String role;
  final String text;
  final bool isRateLimit;
  _ChatMsg({required this.role, required this.text, this.isRateLimit = false});
}
