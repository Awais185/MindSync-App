import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import '../pages/report_screen.dart';
import '../../widgets/mindsync_chat_charts.dart';
import '../../widgets/mindsync_markdown_body.dart';
import '../../services/api_client.dart';
import '../../services/chat_behavior_context_service.dart';
import '../../services/plan_access_service.dart';
import '../../utils/sanitize_chat_text.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => ChatScreenState();
}

class ChatScreenState extends State<ChatScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  void openDrawer() => _scaffoldKey.currentState?.openDrawer();

  /// Header “My Report” — same as the My Report quick chip (7-day MCP tool).
  void openMyReportInChat() {
    if (_isLoading) return;
    _messageController.text = 'My Report';
    unawaited(_sendMessage(tool: _toolSevenDayReport));
  }
  final TextEditingController _messageController = TextEditingController();
  final List<ChatMessage> _messages = [];
  final List<Map<String, String>> _history = [];
  final List<ChatSessionItem> _sessions = [];
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  bool _loadingSessions = false;
  int? _sessionId;

  @override
  void initState() {
    super.initState();
    _resetToWelcome();
    _fetchSessions();
  }

  void _resetToWelcome() {
    _messages
      ..clear()
      ..add(
        ChatMessage(
          text: "Hello! How can I help you today?",
          isUser: false,
          timestamp: DateTime.now(),
        ),
      );
    _history
      ..clear()
      ..add({
        'role': 'assistant',
        'content':
            "Hello! I noticed your sleep data shows a bit of restlessness last night. Would you like to try a 5-minute breathing exercise before we start our session?",
      });
  }

  Future<void> _fetchSessions() async {
    if (mounted) setState(() => _loadingSessions = true);
    try {
      final response = await ApiClient.instance.get(
        '/api/chat/sessions/',
        timeout: const Duration(seconds: 15),
      );
      if (response == null ||
          response.statusCode < 200 ||
          response.statusCode >= 300) {
        return;
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final items = (body['results'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(ChatSessionItem.fromJson)
          .toList();
      if (!mounted) return;
      setState(() {
        _sessions
          ..clear()
          ..addAll(items);
      });
    } catch (_) {
      // Keep chat usable even when the session list cannot load.
    } finally {
      if (mounted) setState(() => _loadingSessions = false);
    }
  }

  Future<void> _deleteSession(ChatSessionItem session) async {
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete chat?'),
        content: const Text(
          'This conversation will be permanently deleted and cannot be recovered.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final response = await ApiClient.instance.delete(
        '/api/chat/sessions/${session.id}/',
        timeout: const Duration(seconds: 15),
      );
      if (response == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not delete chat. Check connection.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      if (response.statusCode != 204 && (response.statusCode < 200 || response.statusCode >= 300)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete chat.'), behavior: SnackBarBehavior.floating),
        );
        return;
      }
      if (_sessionId == session.id) {
        _sessionId = null;
        _resetToWelcome();
      }
      await _fetchSessions();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete chat.'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _openSession(ChatSessionItem session) async {
    if (!mounted) return;
    Navigator.of(context).maybePop();
    setState(() => _isLoading = true);
    try {
      final response = await ApiClient.instance.get(
        '/api/chat/sessions/${session.id}/messages/',
        timeout: const Duration(seconds: 15),
      );
      if (response == null ||
          response.statusCode < 200 ||
          response.statusCode >= 300) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        return;
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final rows = (body['results'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();
      final loadedMessages = <ChatMessage>[];
      final loadedHistory = <Map<String, String>>[];
      for (final row in rows) {
        final createdAt =
            DateTime.tryParse((row['created_at'] ?? '').toString()) ??
            DateTime.now();
        final message = (row['message'] ?? '').toString();
        final responseText = (row['response'] ?? '').toString();
        if (message.isNotEmpty) {
          loadedMessages.add(
            ChatMessage(text: message, isUser: true, timestamp: createdAt),
          );
          loadedHistory.add({'role': 'user', 'content': message});
        }
        if (responseText.isNotEmpty) {
          loadedMessages.add(
            ChatMessage(
              text: responseText,
              isUser: false,
              timestamp: createdAt,
            ),
          );
          loadedHistory.add({'role': 'assistant', 'content': responseText});
        }
      }
      if (!mounted) return;
      setState(() {
        _sessionId = session.id;
        _messages
          ..clear()
          ..addAll(loadedMessages);
        _history
          ..clear()
          ..addAll(loadedHistory);
        _isLoading = false;
      });
      if (_messages.isEmpty) {
        setState(_resetToWelcome);
      }
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _startNewChat() {
    Navigator.of(context).maybePop();
    setState(() {
      _sessionId = null;
      _resetToWelcome();
    });
  }

  static const String _toolSevenDayReport = 'seven_day_comprehensive_report';

  Future<void> _sendMessage({String? tool}) async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isLoading) return;
    final canUseChat = await PlanAccessService.instance.canAccess(
      'chat_digital_psychologist',
    );
    if (!canUseChat) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Upgrade your plan to access this feature.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Add user message
    setState(() {
      _messages.add(
        ChatMessage(text: text, isUser: true, timestamp: DateTime.now()),
      );
      _messageController.clear();
      _isLoading = true;
    });
    _history.add({'role': 'user', 'content': text});

    // Scroll to bottom
    _scrollToBottom();
    final response = await _fetchAssistantReply(tool: tool);
    if (!mounted) return;
    setState(() {
      _messages.add(
        ChatMessage(
          text: response.text,
          isUser: false,
          timestamp: DateTime.now(),
          charts: response.charts,
        ),
      );
      _isLoading = false;
    });
    _history.add({'role': 'assistant', 'content': response.text});
    _scrollToBottom();
  }

  Future<_AssistantFetchResult> _fetchAssistantReply({String? tool}) async {
    try {
      final latestUserMessage =
          _history.lastWhere(
            (item) => item['role'] == 'user',
            orElse: () => {'role': 'user', 'content': ''},
          )['content'] ??
          '';
      Map<String, dynamic> behaviorContext = const {'has_data': false};
      try {
        behaviorContext =
            await ChatBehaviorContextService.instance
                .buildPayload(forceRefresh: false)
                .timeout(const Duration(seconds: 12));
      } catch (_) {
        behaviorContext = const {'has_data': false};
      }

      final response = await ApiClient.instance.post(
        '/api/chat/',
        body: {
          'message': latestUserMessage,
          if (_sessionId != null) 'session_id': _sessionId,
          if (tool != null && tool.isNotEmpty) 'tool': tool,
          'history': _history
              .where(
                (item) =>
                    item['role'] == 'user' || item['role'] == 'assistant',
              )
              .toList(),
          'behavior_context': behaviorContext,
        },
        timeout: const Duration(seconds: 90),
      );

      if (response == null) {
        return const _AssistantFetchResult(text: kChatNetworkErrorMessage);
      }

      if (response.statusCode == 401) {
        return const _AssistantFetchResult(
          text: 'Session expired. Please login again.',
        );
      }
      if (response.statusCode == 403) {
        return const _AssistantFetchResult(
          text: 'Upgrade your plan to access Digital Psychologist chat.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _AssistantFetchResult(
          text:
              'MindSync AI is temporarily unavailable (HTTP ${response.statusCode}). '
              'Please try again shortly.',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final reply = sanitizeChatDisplayText(
        (data['reply'] ?? '').toString().trim(),
      );
      final charts = MindSyncChartSpec.listFromDynamic(
        data['charts'] as List<dynamic>?,
      );
      final session = data['session_id'];
      if (session is int) {
        _sessionId = session;
      }
      _fetchSessions();
      if (reply.isEmpty) {
        return const _AssistantFetchResult(
          text: 'I could not generate a response right now. Please try again.',
        );
      }
      return _AssistantFetchResult(text: reply, charts: charts);
    } on TimeoutException {
      return const _AssistantFetchResult(
        text:
            'The request timed out. The AI may still be working — try again in a moment.',
      );
    } on FormatException {
      return const _AssistantFetchResult(
        text: 'Received an invalid response from the server. Please try again.',
      );
    } catch (_) {
      return const _AssistantFetchResult(text: kChatNetworkErrorMessage);
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendQuickChip(String text, {String? tool}) {
    _messageController.text = text;
    _sendMessage(tool: tool);
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF5F6FA),
      drawer: _buildSessionDrawer(),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final message = _messages[index];
                  return _buildChatMessage(message);
                },
              ),
            ),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.only(left: 16, right: 16, bottom: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'MindSync is thinking...',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF7E8291),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

            // Quick Chips
            _buildQuickChips(),

            // Input Field
            _buildInputField(),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFFF8F7FC),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Chat History',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF20222B),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: _fetchSessions,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton.icon(
                  onPressed: _startNewChat,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('New chat'),
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: const Color(0xFF6F39E8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: _openWeeklyReport,
                  icon: const Icon(Icons.insights_rounded, size: 20),
                  label: const Text('Weekly report'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF6F39E8),
                    side: const BorderSide(color: Color(0xFFD8CCF5)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_loadingSessions)
              const Padding(
                padding: EdgeInsets.all(18),
                child: LinearProgressIndicator(),
              ),
            Expanded(
              child: _sessions.isEmpty && !_loadingSessions
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No saved chats yet.',
                          style: TextStyle(color: Color(0xFF777A88)),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                      itemCount: _sessions.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final session = _sessions[index];
                        final selected = session.id == _sessionId;
                        return Material(
                          color: selected
                              ? const Color(0xFFEDE9FB)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            leading: Icon(
                              Icons.chat_bubble_outline_rounded,
                              color: selected
                                  ? const Color(0xFF6F39E8)
                                  : const Color(0xFF7D8090),
                            ),
                            title: Text(
                              session.displayTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              '${session.turns} messages',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFB3261E)),
                              tooltip: 'Delete chat',
                              onPressed: () => _deleteSession(session),
                            ),
                            onTap: () => _openSession(session),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openWeeklyReport() async {
    final allowed = await PlanAccessService.instance.canAccess(
      'weekly_reports',
      forceRefresh: true,
    );
    if (!allowed) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Upgrade your plan to access this feature.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (!mounted) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ReportScreen()));
  }

  Widget _buildChatMessage(ChatMessage message) {
    if (message.isUser) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const SizedBox(height: 8),
          const _RoleLabel('USER'),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: _UserBubble(text: message.text),
          ),
          const SizedBox(height: 4),
          _buildTimestamp(message.timestamp, isUser: true),
        ],
      );
    } else {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          const _RoleLabel('ASSISTANT'),
          const SizedBox(height: 6),
          _AssistantBubble(
            text: sanitizeChatDisplayText(message.text),
          ),
          if (message.charts.isNotEmpty)
            ...message.charts.map(
              (spec) => Padding(
                padding: const EdgeInsets.only(top: 4, right: 8),
                child: MindSyncChatChartCard(spec: spec),
              ),
            ),
          const SizedBox(height: 4),
          _buildTimestamp(message.timestamp, isUser: false),
        ],
      );
    }
  }

  Widget _buildTimestamp(DateTime timestamp, {required bool isUser}) {
    return Padding(
      padding: EdgeInsets.only(
        left: isUser ? 0 : 12,
        right: isUser ? 12 : 0,
        top: 4,
      ),
      child: Text(
        _formatTime(timestamp),
        style: const TextStyle(
          fontSize: 12,
          color: Color(0xFFA1A3AE),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildQuickChips() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _QuickChip(
            text: 'I feel stressed',
            bg: const Color(0xFFC6F2ED),
            fg: const Color(0xFF126F69),
            onTap: () => _sendQuickChip('I feel stressed'),
          ),
          _QuickChip(
            text: 'How can I focus?',
            bg: const Color(0xFFEDE9FB),
            fg: const Color(0xFF6F39E8),
            onTap: () => _sendQuickChip('How can I focus?'),
          ),
          _QuickChip(
            text: 'My Report',
            bg: const Color(0xFFEAEFFB),
            fg: const Color(0xFF385A87),
            onTap: () => _sendQuickChip(
              'My Report',
              tool: _toolSevenDayReport,
            ),
          ),
          _QuickChip(
            text: 'Breathing exercise',
            bg: const Color(0xFFFCE8E6),
            fg: const Color(0xFFD95A5A),
            onTap: () => _sendQuickChip('Can we do a breathing exercise?'),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F6FA),
        border: Border(
          top: BorderSide(color: const Color(0xFFE5E5EA).withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _messageController,
                style: const TextStyle(fontSize: 14, color: Color(0xFF1A1C24)),
                decoration: const InputDecoration(
                  hintText: 'Type your message...',
                  hintStyle: TextStyle(fontSize: 13, color: Color(0xFFA1A3AE)),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _sendMessage,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6F39E8), Color(0xFF8455EF)],
                ),
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6F39E8).withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.send_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final List<MindSyncChartSpec> charts;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.charts = const [],
  });
}

class _AssistantFetchResult {
  const _AssistantFetchResult({
    required this.text,
    this.charts = const [],
  });

  final String text;
  final List<MindSyncChartSpec> charts;
}

class ChatSessionItem {
  const ChatSessionItem({
    required this.id,
    required this.title,
    required this.turns,
    required this.updatedAt,
  });

  final int id;
  final String title;
  final int turns;
  final DateTime updatedAt;

  String get displayTitle {
    final clean = title.trim();
    if (clean.isEmpty || clean == 'New chat') return 'Chat #$id';
    return clean;
  }

  factory ChatSessionItem.fromJson(Map<String, dynamic> json) {
    return ChatSessionItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: (json['title'] ?? 'New chat').toString(),
      turns: (json['turns'] as num?)?.toInt() ?? 0,
      updatedAt:
          DateTime.tryParse((json['updated_at'] ?? '').toString()) ??
          DateTime.now(),
    );
  }
}

class _RoleLabel extends StatelessWidget {
  const _RoleLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 12),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          color: Color(0xFF8A8C98),
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.fromLTRB(0, 12, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F9FC),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 3,
              margin: const EdgeInsets.only(top: 2, bottom: 2),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF6F39E8),
                    Color(0xFF0E9186),
                    Color(0xFF2E6FD2),
                  ],
                ),
                borderRadius: BorderRadius.all(Radius.circular(2)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MindSyncMarkdownBody(data: text),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6F39E8), Color(0xFF7B51EA)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6F39E8).withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, height: 1.45, color: Colors.white),
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({
    required this.text,
    required this.bg,
    required this.fg,
    required this.onTap,
  });
  final String text;
  final Color bg;
  final Color fg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: fg.withValues(alpha: 0.2), width: 0.5),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: fg,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
