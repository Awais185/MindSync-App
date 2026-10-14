import 'package:flutter/material.dart';

/// Theme tokens for late-night activity & sleep analytics UI.
abstract final class LateNightSleepColors {
  static const Color activityAccent = Color(0xFF6F39E8);
  static const Color sleepAccent = Color(0xFF14B8A6);
  static const Color barTrack = Color(0xFFE3E4EA);
  static const Color barHighlight = Color(0xFF6F39E8);
  static const Color categorySocial = Color(0xFF1877F2);
  static const Color categoryVideo = Color(0xFFE1306C);
  static const Color categoryGaming = Color(0xFF8B5CF6);
  static const Color categoryOther = Color(0xFF7A80A0);

  static Color categoryColor(String category) {
    final lower = category.toLowerCase();
    if (lower.contains('social')) return categorySocial;
    if (lower.contains('video')) return categoryVideo;
    if (lower.contains('gaming')) return categoryGaming;
    return categoryOther;
  }
}

/// Device-side late-night screen activity and estimated sleep (22:00–05:00).
class LateNightSleepSnapshot {
  const LateNightSleepSnapshot({
    this.sleepTonightMinutes = 0,
    this.lateNightTonightMinutes = 0,
    this.lateNightCategoriesTonight = const {},
    this.sleepWeekMinutes = 0,
    this.lateNightWeekMinutes = 0,
    this.lateNightByDayMinutes = _empty7,
    this.sleepByDayMinutes = _empty7,
    this.lateNightCategoriesWeek = const {},
  });

  final int sleepTonightMinutes;
  final int lateNightTonightMinutes;
  final Map<String, int> lateNightCategoriesTonight;
  final int sleepWeekMinutes;
  final int lateNightWeekMinutes;
  final List<int> lateNightByDayMinutes;
  final List<int> sleepByDayMinutes;
  final Map<String, int> lateNightCategoriesWeek;

  static const List<int> _empty7 = [0, 0, 0, 0, 0, 0, 0];

  static const empty = LateNightSleepSnapshot();

  bool get hasData =>
      sleepTonightMinutes > 0 ||
      lateNightTonightMinutes > 0 ||
      sleepWeekMinutes > 0 ||
      lateNightWeekMinutes > 0 ||
      lateNightByDayMinutes.any((v) => v > 0) ||
      sleepByDayMinutes.any((v) => v > 0);

  factory LateNightSleepSnapshot.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return LateNightSleepSnapshot.empty;
    return LateNightSleepSnapshot(
      sleepTonightMinutes: (raw['sleepTonightMinutes'] as num?)?.toInt() ?? 0,
      lateNightTonightMinutes:
          (raw['lateNightTonightMinutes'] as num?)?.toInt() ?? 0,
      lateNightCategoriesTonight:
          _coerceCategoryMap(raw['lateNightCategoriesTonight']),
      sleepWeekMinutes: (raw['sleepWeekMinutes'] as num?)?.toInt() ?? 0,
      lateNightWeekMinutes: (raw['lateNightWeekMinutes'] as num?)?.toInt() ?? 0,
      lateNightByDayMinutes: _coerceIntList7(raw['lateNightByDayMinutes']),
      sleepByDayMinutes: _coerceIntList7(raw['sleepByDayMinutes']),
      lateNightCategoriesWeek:
          _coerceCategoryMap(raw['lateNightCategoriesWeek']),
    );
  }

  static List<int> _coerceIntList7(dynamic raw) {
    if (raw is! List) return List<int>.from(_empty7);
    final out = <int>[];
    for (final e in raw) {
      if (out.length >= 7) break;
      out.add((e as num?)?.toInt() ?? 0);
    }
    while (out.length < 7) {
      out.add(0);
    }
    return out;
  }

  static Map<String, int> _coerceCategoryMap(dynamic raw) {
    if (raw is! Map) return const {};
    final out = <String, int>{};
    for (final e in raw.entries) {
      final k = e.key.toString();
      final v = (e.value as num?)?.toInt() ?? 0;
      if (k.isNotEmpty && v > 0) out[k] = v;
    }
    return out;
  }
}

String formatSleepDuration(int totalMinutes) {
  if (totalMinutes <= 0) return '0h, 0m';
  final h = totalMinutes ~/ 60;
  final m = totalMinutes % 60;
  if (h <= 0) return '${m}m';
  if (m <= 0) return '${h}h';
  return '${h}h, ${m}m';
}

/// Labels for rolling 7-day arrays (index 0 = six days ago, index 6 = today).
List<String> rollingSevenDayLabels({DateTime? reference}) {
  const short = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final ref = reference ?? DateTime.now();
  return List.generate(7, (i) {
    final d = ref.subtract(Duration(days: 6 - i));
    return short[d.weekday - 1];
  });
}

/// Merge device live late-night data with archive snapshot (prefer non-zero live).
LateNightSleepSnapshot mergeLateNightSleepSources({
  LateNightSleepSnapshot live = LateNightSleepSnapshot.empty,
  LateNightSleepSnapshot archive = LateNightSleepSnapshot.empty,
}) {
  if (!live.hasData && !archive.hasData) return LateNightSleepSnapshot.empty;
  if (!archive.hasData) return live;
  if (!live.hasData) return archive;

  List<int> pickList(List<int> a, List<int> b) {
    final sumA = a.fold<int>(0, (s, v) => s + v);
    final sumB = b.fold<int>(0, (s, v) => s + v);
    return sumA >= sumB ? a : b;
  }

  return LateNightSleepSnapshot(
    sleepTonightMinutes: live.sleepTonightMinutes > 0
        ? live.sleepTonightMinutes
        : archive.sleepTonightMinutes,
    lateNightTonightMinutes: live.lateNightTonightMinutes > 0
        ? live.lateNightTonightMinutes
        : archive.lateNightTonightMinutes,
    lateNightCategoriesTonight: live.lateNightCategoriesTonight.isNotEmpty
        ? live.lateNightCategoriesTonight
        : archive.lateNightCategoriesTonight,
    sleepWeekMinutes: live.sleepWeekMinutes > 0
        ? live.sleepWeekMinutes
        : archive.sleepWeekMinutes,
    lateNightWeekMinutes: live.lateNightWeekMinutes > 0
        ? live.lateNightWeekMinutes
        : archive.lateNightWeekMinutes,
    lateNightByDayMinutes: pickList(
      live.lateNightByDayMinutes,
      archive.lateNightByDayMinutes,
    ),
    sleepByDayMinutes: pickList(
      live.sleepByDayMinutes,
      archive.sleepByDayMinutes,
    ),
    lateNightCategoriesWeek: live.lateNightCategoriesWeek.isNotEmpty
        ? live.lateNightCategoriesWeek
        : archive.lateNightCategoriesWeek,
  );
}
