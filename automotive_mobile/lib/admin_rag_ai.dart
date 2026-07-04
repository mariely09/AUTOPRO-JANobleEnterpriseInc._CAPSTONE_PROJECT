import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';

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

// ─────────────────────────────────────────────────────────────────────────────

class AdminSmartReports extends StatefulWidget {
  const AdminSmartReports({super.key});

  @override
  State<AdminSmartReports> createState() => _AdminSmartReportsState();
}

class _AdminSmartReportsState extends State<AdminSmartReports> {
  static const _red  = Color(0xFFE8001C);
  static const _blue = Color(0xFF003087);

  final _inputCtrl  = TextEditingController();
  final _scrollCtrl = ScrollController();

  final List<_ChatMessage> _messages = [];
  final List<Map<String, String>> _history = []; // legacy — kept for fallback only
  String? _sessionId;  // server-side memory key

  bool _loading       = false;
  bool _rateLimited   = false;   // true when Groq daily token limit is reached
  String _resetIn     = '';      // human-readable reset time
  bool _backendOnline = false;

  @override
  void initState() {
    super.initState();
    _checkBackend();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Backend health check ───────────────────────────────────────────────────

  Future<void> _checkBackend() async {
    try {
      final r = await http
          .get(Uri.parse('$_kAiBaseUrl/health'))
          .timeout(const Duration(seconds: 5));
      if (mounted) setState(() => _backendOnline = r.statusCode == 200);
    } catch (_) {
      if (mounted) setState(() => _backendOnline = false);
    }
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
      _showReportConfirm(reportType, isExcel ? 'excel' : 'pdf');
      return;
    }

    setState(() {
      _messages.add(_ChatMessage(role: 'user', text: text));
      _inputCtrl.clear();
      _loading = true;
    });
    _scrollToBottom();

    final historyPayload = _history.length > 20
        ? _history.sublist(_history.length - 20)
        : List<Map<String, String>>.from(_history);

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
          .timeout(const Duration(seconds: 60));

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
              text: '🚫 AI Unavailable\n\n'
                  'The AI service has reached its daily token limit (Groq free tier).\n\n'
                  '⏱️ The limit resets in $resetIn.\n\n'
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
            text: '⚠️ AI service error (${resp.statusCode}): ${_parseError(resp.body)}',
          ));
        });
      }
    } on http.ClientException catch (e) {
      setState(() {
        _loading = false;
        _messages.add(_ChatMessage(
          role: 'ai',
          text: '🔌 Cannot reach the AI service.\n\n'
              'Start the backend:\n'
              '  cd ai_assistant\n'
              '  venv\\Scripts\\uvicorn main:app --port 8001\n\n'
              'Error: $e',
        ));
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _messages.add(_ChatMessage(role: 'ai', text: '⚠️ Unexpected error: $e'));
      });
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
  void _showReportConfirm(String reportType, String format) {
    final title = _kReportTypes[reportType] ?? 'Report';
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 16),
          const Text('📄 Download Report',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
                  color: Color(0xFF1a202c))),
          const SizedBox(height: 6),
          Text(title,
              style: const TextStyle(fontSize: 13, color: Color(0xFF718096))),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: _reportFormatBtn(
                label: '📄 PDF',
                subtitle: 'Branded report',
                selected: format == 'pdf',
                onTap: () { Navigator.pop(context); _downloadReport(reportType, 'pdf'); },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _reportFormatBtn(
                label: '📊 Excel',
                subtitle: 'Spreadsheet',
                selected: format == 'excel',
                onTap: () { Navigator.pop(context); _downloadReport(reportType, 'excel'); },
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _reportFormatBtn({
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
          color: selected ? _red.withOpacity(0.06) : const Color(0xFFF7F8FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? _red : const Color(0xFFe2e8f0),
              width: selected ? 1.5 : 1),
        ),
        child: Column(children: [
          Text(label,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: selected ? _red : const Color(0xFF1a202c))),
          const SizedBox(height: 4),
          Text(subtitle,
              style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
        ]),
      ),
    );
  }

  Future<void> _downloadReport(String reportType, String format) async {
    final typeName = _kReportTypes[reportType] ?? reportType;
    final fmtLabel = format.toUpperCase();

    // Show progress in chat
    setState(() {
      _messages.add(_ChatMessage(
          role: 'ai',
          text: '⏳ Generating $typeName ($fmtLabel)…'));
      _loading = true;
    });
    _scrollToBottom();

    try {
      final resp = await http
          .post(
            Uri.parse('$_kAiBaseUrl/admin/report'
                '?report_type=$reportType&format=$format'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 90));

      if (resp.statusCode == 200) {
        final ext      = format == 'pdf' ? 'pdf' : 'xlsx';
        final filename = '${reportType}_report.$ext';

        // Save to temp dir and open with system viewer
        final dir  = await getTemporaryDirectory();
        final file = File('${dir.path}/$filename');
        await file.writeAsBytes(resp.bodyBytes);

        setState(() {
          _loading = false;
          _messages.removeLast(); // remove the "Generating…" message
          _messages.add(_ChatMessage(
            role: 'ai',
            text: '✅ $typeName downloaded successfully!',
            reportFile: file,
            reportFormat: format,
            reportLabel: typeName,
          ));
        });
        _scrollToBottom();

        // Auto-open the file
        await OpenFile.open(file.path);
      } else {
        throw Exception('Server error ${resp.statusCode}: ${_parseError(resp.body)}');
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _messages.removeLast();
        _messages.add(_ChatMessage(
          role: 'ai',
          text: '❌ Failed to generate $typeName: $e',
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
                      .catchError((_) {});
                  _sessionId = null;
                }
                setState(() {
                  _messages.clear();
                  _history.clear();
                  _rateLimited = false;
                  _resetIn = '';
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
                  'AI backend offline. Start: venv\\Scripts\\uvicorn main:app --port 8001',
                  style: TextStyle(fontSize: 11, color: Color(0xFF975A16)),
                ),
              ),
              GestureDetector(
                onTap: _checkBackend,
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
            color: const Color(0xFFFFF7ED),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFFFB923C), width: 2),
              ),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('🚫', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AI service unavailable — daily token limit reached',
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
                          const TextSpan(text: 'The Groq API free-tier quota is exhausted. '),
                          TextSpan(
                            text: 'Resets in $_resetIn. ',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const TextSpan(
                              text: 'You cannot send messages until the limit resets automatically.'),
                        ],
                      ),
                    ),
                  ],
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
    final chips = [
      ('📊 Fleet summary',    'Show fleet summary'),
      ('⚠️ PMS overdue',     'Which vehicles have PMS overdue?'),
      ('📦 Low stock',        'What items are low in stock?'),
      ('💰 Repair cost',      'Total repair cost this month'),
      ('⏳ Pending services', 'How many services are pending?'),
      ('📈 Fast moving',      'What are the fast moving inventory items?'),
      ('🚗 All vehicles',     'List all vehicles'),
      ('📋 Bookings',         'Show all service bookings'),
      ('📄 Inventory PDF',    'Generate inventory report PDF'),
      ('📊 Issuance Excel',   'Generate issuance report excel'),
      ('📄 Maintenance PDF',  'Generate maintenance report PDF'),
      ('📊 Vehicle Excel',    'Generate vehicle fleet report excel'),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        const SizedBox(height: 12),
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
              color: _blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20)),
          child: const Icon(Icons.smart_toy_outlined, color: _blue, size: 32),
        ),
        const SizedBox(height: 14),
        const Text('Smart Reports AI',
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold,
                color: Color(0xFF1a202c))),
        const SizedBox(height: 6),
        const Text(
          'Ask me anything about the fleet, inventory, maintenance costs, '
          'or generate branded PDF/Excel reports.',
          style: TextStyle(fontSize: 13, color: Color(0xFF718096), height: 1.5),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: chips.map((c) => GestureDetector(
            onTap: () => _sendQuery(c.$2),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFe2e8f0)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4)
                ],
              ),
              child: Text(c.$1,
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF4a5568),
                      fontWeight: FontWeight.w500)),
            ),
          )).toList(),
        ),
      ]),
    );
  }

  // ── Typing indicator ───────────────────────────────────────────────────────

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6)
          ],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(
            width: 24, height: 24,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Color(0xFFE8001C)),
          ),
          const SizedBox(width: 10),
          Text('Thinking…',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
        ]),
      ),
    );
  }

  // ── Chat bubble ────────────────────────────────────────────────────────────

  Widget _buildBubble(_ChatMessage msg) {
    if (msg.role == 'user') {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12, left: 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _red,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(color: _red.withOpacity(0.25), blurRadius: 6)],
          ),
          child: Text(msg.text!,
              style: const TextStyle(color: Colors.white, fontSize: 13)),
        ),
      );
    }

    // Rate-limit special card
    if (msg.isRateLimit) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12, right: 16),
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.88),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7ED),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFB923C), width: 1.5),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6)
            ],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: const BoxDecoration(
                color: Color(0xFFEA580C),
                borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: const Row(children: [
                Text('🚫', style: TextStyle(fontSize: 14)),
                SizedBox(width: 8),
                Text('AI Service Unavailable',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Daily token limit reached (Groq free tier)',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF9A3412)),
                  ),
                  const SizedBox(height: 8),
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(
                          fontSize: 12.5, color: Color(0xFF9A3412), height: 1.55),
                      children: [
                        const TextSpan(
                            text: 'The Groq API has exhausted its free-tier quota for today.\n\n'),
                        const TextSpan(text: '⏱️ Resets in '),
                        TextSpan(
                          text: _resetIn.isNotEmpty ? _resetIn : 'some time',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const TextSpan(
                            text: '.\n\nYou cannot send new messages until the limit resets automatically.'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ]),
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12, right: 48),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header strip
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _blue,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: const Row(children: [
              Text('🤖', style: TextStyle(fontSize: 14)),
              SizedBox(width: 8),
              Text('Smart Reports AI',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12)),
            ]),
          ),
          // Body
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    msg.text ?? '',
                    style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF1a202c),
                        height: 1.6),
                  ),
                  // If a report file was downloaded, show Open + Share buttons
                  if (msg.reportFile != null) ...[
                    const SizedBox(height: 10),
                    Row(children: [
                      _actionBtn('📂 Open', _red, () async {
                        await OpenFile.open(msg.reportFile!.path);
                      }),
                      const SizedBox(width: 8),
                      _actionBtn('📤 Share', _blue, () async {
                        await Printing.sharePdf(
                          bytes: await msg.reportFile!.readAsBytes(),
                          filename: msg.reportFile!.path.split('/').last,
                        );
                      }),
                    ]),
                  ],
                  // Re-download buttons for long AI text responses
                  if (msg.reportFile == null && (msg.text ?? '').length > 80) ...[
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 6, children: [
                      for (final entry in _kReportTypes.entries)
                        _tinyChip(
                          '📄 ${entry.value.replaceAll(' Report', '')} PDF',
                          () => _downloadReport(entry.key, 'pdf'),
                        ),
                    ]),
                  ],
                ]),
          ),
        ]),
      ),
    );
  }

  Widget _actionBtn(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(label,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.bold,
                color: Colors.white)),
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
