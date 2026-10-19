import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../utils/sanitize_chat_text.dart';

/// Chat-friendly Markdown (headings, bold, lists) on a light assistant bubble.
class MindSyncMarkdownBody extends StatelessWidget {
  const MindSyncMarkdownBody({
    super.key,
    required this.data,
    this.textColor = const Color(0xFF20222B),
    this.linkColor = const Color(0xFF6F39E8),
  });

  final String data;
  final Color textColor;
  final Color linkColor;

  @override
  Widget build(BuildContext context) {
    return MarkdownBody(
      data: sanitizeChatDisplayText(data),
      onTapLink: (_, __, ___) {},
      shrinkWrap: true,
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(
          fontSize: 13,
          height: 1.45,
          color: textColor,
          fontWeight: FontWeight.w500,
        ),
        h1: TextStyle(
          fontSize: 16,
          height: 1.3,
          fontWeight: FontWeight.w800,
          color: textColor,
          letterSpacing: -0.2,
        ),
        h2: TextStyle(
          fontSize: 14.5,
          height: 1.35,
          fontWeight: FontWeight.w800,
          color: textColor,
          letterSpacing: -0.15,
        ),
        h3: TextStyle(
          fontSize: 13.5,
          height: 1.35,
          fontWeight: FontWeight.w800,
          color: textColor,
        ),
        strong: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: textColor,
        ),
        em: TextStyle(
          fontSize: 12.5,
          fontStyle: FontStyle.italic,
          color: textColor.withValues(alpha: 0.85),
        ),
        listBullet: TextStyle(
          fontSize: 13,
          color: textColor,
          fontWeight: FontWeight.w600,
        ),
        blockSpacing: 8,
        listIndent: 20,
        horizontalRuleDecoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: textColor.withValues(alpha: 0.12)),
          ),
        ),
        a: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: linkColor,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }
}
