import '../../../services/screen_time_service.dart';
import '../../../services/wellness_dashboard_service.dart';
import '../../../utils/mental_health_severity.dart';

/// Pure helpers for Mind Balance hero tiles (layout unchanged; values only).
class HomeHeroMetrics {
  const HomeHeroMetrics({
    required this.wellbeingScore,
    required this.wellbeingDeltaPoints,
    required this.balanceRingLabel,
    required this.screenTimeValue,
    required this.screenTimeCaption,
    required this.stressValue,
    required this.stressCaption,
    required this.sleepValue,
    required this.sleepCaption,
    required this.habitValue,
    required this.habitCaption,
  });

  final int wellbeingScore;
  final int wellbeingDeltaPoints;
  final String balanceRingLabel;
  final String screenTimeValue;
  final String screenTimeCaption;
  final String stressValue;
  final String stressCaption;
  final String sleepValue;
  final String sleepCaption;
  final String habitValue;
  final String habitCaption;

  double get wellbeingProgress =>
      (wellbeingScore.clamp(0, 100) / 100.0).clamp(0.0, 1.0);

  String get wellbeingDeltaLabel {
    if (wellbeingDeltaPoints == 0) return 'No change vs yesterday';
    final sign = wellbeingDeltaPoints > 0 ? '+' : '';
    return '$sign$wellbeingDeltaPoints pts vs yesterday';
  }

  static HomeHeroMetrics compose({
    required WellnessDashboardData wellness,
    required ScreenTimeSnapshot screen,
    required int yesterdayDaySeconds,
    required int backendSleepSeconds,
    required int backendLateNightSeconds,
    required int wellbeingDeltaPoints,
    List<AppUsageItem> rollingApps = const [],
  }) {
    final score = wellness.wellbeingScore.clamp(0, 100);
    final stressScore = wellness.mentalHealth.hasData
        ? wellness.mentalHealth.stress.score
        : wellness.stressIndicator.toDouble();

    final deviceSleepMin = screen.lateNightSleep.sleepTonightMinutes;
    final deviceLateMin = screen.lateNightSleep.lateNightTonightMinutes;
    final sleepSeconds = [
      wellness.sleepSecondsToday,
      backendSleepSeconds,
      deviceSleepMin * 60,
    ].reduce((a, b) => a > b ? a : b);
    final lateSeconds = [
      wellness.lateNightSecondsToday,
      backendLateNightSeconds,
      deviceLateMin * 60,
    ].reduce((a, b) => a > b ? a : b);

    final todaySec = screen.daySeconds;
    final screenValue = formatDurationShort(todaySec);
    final screenCaption = _screenComparisonCaption(
      todaySeconds: todaySec,
      yesterdaySeconds: yesterdayDaySeconds,
    );

    final topApp = _topUsageApp(screen, rollingApps: rollingApps);

    return HomeHeroMetrics(
      wellbeingScore: score,
      wellbeingDeltaPoints: wellbeingDeltaPoints,
      balanceRingLabel: _balanceRingLabel(score),
      screenTimeValue: screenValue,
      screenTimeCaption: screenCaption,
      stressValue: stressScore > 0
          ? MentalHealthSeverity.labelFromPercent(stressScore)
          : '—',
      stressCaption: _stressCaption(stressScore),
      sleepValue: _formatSleepHoursMinutes(sleepSeconds),
      sleepCaption: _sleepCaption(
        sleepSeconds: sleepSeconds,
        lateNightSeconds: lateSeconds,
      ),
      habitValue: topApp == null ? '—' : _truncate(topApp.appName, 14),
      habitCaption: topApp == null
          ? 'Usage data pending'
          : 'Top today · ${formatDurationShort(topApp.durationSeconds)}',
    );
  }

  static AppUsageItem? _topUsageApp(
    ScreenTimeSnapshot screen, {
    List<AppUsageItem> rollingApps = const [],
  }) {
    final merged = <String, AppUsageItem>{};
    for (final a in screen.topApps) {
      merged[a.packageName] = a;
    }
    for (final a in rollingApps) {
      final prev = merged[a.packageName];
      if (prev == null || a.sortKeyMs > prev.sortKeyMs) {
        merged[a.packageName] = a;
      }
    }
    if (merged.isEmpty) return null;
    final ranked = merged.values.toList()
      ..sort((a, b) => b.sortKeyMs.compareTo(a.sortKeyMs));
    return ranked.first;
  }

  static String _balanceRingLabel(int score) {
    if (score >= 70) return 'CALM';
    if (score >= 40) return 'BALANCED';
    return 'REST';
  }

  static String _screenComparisonCaption({
    required int todaySeconds,
    required int yesterdaySeconds,
  }) {
    final thresholdLabel = 'Daily threshold · 5h';
    if (yesterdaySeconds <= 0) {
      return 'Today · $thresholdLabel';
    }
    final delta = todaySeconds - yesterdaySeconds;
    final pct = (delta / yesterdaySeconds * 100).round();
    final sign = pct > 0 ? '+' : '';
    return '$sign$pct% vs yesterday · $thresholdLabel';
  }

  static String _stressCaption(double score) {
    if (score <= 0) return 'Awaiting mental health signals';
    if (score < 30) return 'Controlled & manageable';
    if (score < 60) return 'Moderate — monitor load';
    if (score < 80) return 'Elevated — take breaks';
    return 'High — prioritize recovery';
  }

  static String _formatSleepHoursMinutes(int sleepSeconds) {
    if (sleepSeconds <= 0) return '—';
    final totalMin = (sleepSeconds / 60).round();
    final h = totalMin ~/ 60;
    final m = totalMin % 60;
    if (h <= 0) return '${m}m';
    if (m <= 0) return '${h}h';
    return '${h}h ${m}m';
  }

  static String _sleepCaption({
    required int sleepSeconds,
    required int lateNightSeconds,
  }) {
    if (sleepSeconds <= 0 && lateNightSeconds <= 0) {
      return '10 PM–6 AM window · tracking';
    }
    if (lateNightSeconds > 0) {
      return 'Late night · ${formatDurationShort(lateNightSeconds)}';
    }
    return 'Rest window 10 PM–6 AM';
  }

  static String _truncate(String s, int max) {
    final t = s.trim();
    if (t.length <= max) return t;
    return '${t.substring(0, max - 1)}…';
  }
}
