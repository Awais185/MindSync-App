import 'package:flutter/material.dart';

import '../../services/community_service.dart';
import '../../services/plan_access_service.dart';

class DoctorChatScreen extends StatefulWidget {
  const DoctorChatScreen({
    super.key,
    required this.doctor,
  });

  final DoctorItem doctor;

  @override
  State<DoctorChatScreen> createState() => _DoctorChatScreenState();
}

class _DoctorChatScreenState extends State<DoctorChatScreen> {
  final _service = CommunityService();
  final _controller = TextEditingController();
  bool _loading = false;
  bool _sending = false;
  List<DoctorChatMessageItem> _messages = const [];

  @override
  void initState() {
    super.initState();
    _guardAndLoadChat();
  }

  Future<void> _guardAndLoadChat() async {
    final allowed = await PlanAccessService.instance.canAccess(
      'chat_digital_psychologist',
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
      Navigator.of(context).maybePop();
      return;
    }
    await _loadChat();
  }

  Future<void> _loadChat() async {
    setState(() => _loading = true);
    final data = await _service.fetchDoctorChat(widget.doctor.id);
    if (!mounted) return;
    setState(() {
      _messages = data;
      _loading = false;
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    final allowed = await PlanAccessService.instance.canAccess(
      'chat_digital_psychologist',
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

    setState(() => _sending = true);
    final ok = await _service.sendDoctorChatMessage(
      doctorId: widget.doctor.id,
      message: text,
    );
    if (!mounted) return;
    if (ok) {
      _controller.clear();
      await _loadChat();
    }
    setState(() => _sending = false);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(title: Text(widget.doctor.fullName)),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? const Center(
                        child: Text(
                          'No messages yet. Start chatting with doctor.',
                          style: TextStyle(color: Color(0xFF676977)),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
                          final isMine = msg.sender == 'user';
                          return Align(
                            alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              constraints: const BoxConstraints(maxWidth: 280),
                              decoration: BoxDecoration(
                                color: isMine ? const Color(0xFF6F39E8) : const Color(0xFFEDEEF4),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(
                                crossAxisAlignment:
                                    isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    msg.message,
                                    style: TextStyle(
                                      color: isMine ? Colors.white : const Color(0xFF161820),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _stamp(msg.createdAt),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isMine
                                          ? Colors.white.withOpacity(0.8)
                                          : const Color(0xFF8A8D98),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          Container(
            color: const Color(0xFFF5F6FA),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration: InputDecoration(
                          hintText: 'Type your message...',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: const BorderSide(color: Color(0xFFD9DBE5)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _sending ? null : _send,
                      icon: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _stamp(DateTime dt) {
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final ap = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ap';
  }
}
