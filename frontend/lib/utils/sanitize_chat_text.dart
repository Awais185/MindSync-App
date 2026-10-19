/// Strip URLs and dev endpoints from text shown in chat (privacy / safety).
String sanitizeChatDisplayText(String input) {
  var text = input.trim();
  if (text.isEmpty) return text;

  final urlPattern = RegExp(
    r'https?://[^\s\)\]]+',
    caseSensitive: false,
  );
  text = text.replaceAll(urlPattern, '[link removed]');

  text = text.replaceAll(
    RegExp(r'\b127\.0\.0\.1(?::\d+)?\b', caseSensitive: false),
    '[server]',
  );
  text = text.replaceAll(
    RegExp(r'\blocalhost(?::\d+)?\b', caseSensitive: false),
    '[server]',
  );
  text = text.replaceAll(
    RegExp(r'adb\s+reverse[^\n.]*', caseSensitive: false),
    '',
  );
  text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return text.trim();
}

const String kChatNetworkErrorMessage =
    'Cannot reach MindSync right now. Check your connection and try again.';
