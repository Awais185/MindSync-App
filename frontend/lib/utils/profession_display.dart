/// Human-readable profession for profile / More screen (matches signup options).
String formatProfessionLabel(String? raw) {
  final v = (raw ?? '').trim().toLowerCase();
  if (v.isEmpty || v == 'other') return 'MindSync member';
  if (v == 'student') return 'Student';
  if (v == 'children' || v == 'child') return 'Children';
  if (v == 'professional' ||
      v == 'working professional' ||
      v.contains('work') ||
      v.contains('professional')) {
    return 'Working Professional';
  }
  if (v.length == 1) return v.toUpperCase();
  return '${v[0].toUpperCase()}${v.substring(1)}';
}
