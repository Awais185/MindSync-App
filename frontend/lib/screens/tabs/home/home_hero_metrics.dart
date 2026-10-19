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
    this.topHabitApp,
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
  final AppUsageItem? topHabitApp;

  double get wellbeingProgress =>
      (wellbeingScore.clamp(0, 100) / 100.0).clamp(0.0, 1.0);

  String get wellbeingDeltaLabel {
    if (wellbeingDeltaPoints == 0) return 'No change vs yesterday';
    final sign = wellbeingDeltaPoints > 0 ? '+' : '';
    return '$sign$wellbeingDeltaPoints pts vs yesterday';
  }

  static HomeHeroMetrics compose({
    required WellnessDashboardData wellness,
    required WellnessDashboardData reportWellness,
    required ScreenTimeSnapshot screen,
    required int yesterdayDaySeconds,
    required int backendSleepSeconds,
    required int backendLateNightSeconds,
    required int wellbeingDeltaPoints,
    List<AppUsageItem> rollingApps = const [],
  }) {
    final score = _resolveWellbeingScore(wellness, reportWellness: reportWellness);
    final showScore = score > 0 ||
        wellness.hasWellbeingSignal ||
        reportWellness.hasWellbeingSignal ||
        wellness.mentalHealth.hasData;
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

    final topApp = _topUsageAppToday(screen, rollingApps: rollingApps);
    final habitDuration = topApp == null
        ? ''
        : formatDurationShort(topApp.durationSeconds);

    return HomeHeroMetrics(
      wellbeingScore: showScore ? score : 0,
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
      habitValue: topApp == null
          ? '—'
          : '${_truncate(topApp.appName, 12)} - $habitDuration',
      habitCaption: topApp == null
          ? 'Usage data pending'
          : 'Highest today · last 24h',
      topHabitApp: topApp,
    );
  }

  /// Device usage stats for today (midnight → now), same source as App Usage card.
  static AppUsageItem? _topUsageAppToday(
    ScreenTimeSnapshot screen, {
    List<AppUsageItem> rollingApps = const [],
  }) {
    final useNativeToday =
        screen.nativeTrackerConfigured && screen.topApps.isNotEmpty;
    final useRolling =
        !useNativeToday && screen.usageStatsGranted && rollingApps.isNotEmpty;
    final ranked = List<AppUsageItem>.from(
      useNativeToday
          ? screen.topApps
          : (useRolling ? rollingApps : screen.topApps),
    )..sort((a, b) => b.sortKeyMs.compareTo(a.sortKeyMs));

    if (ranked.isEmpty) return null;
    return ranked.first;
  }

  /// Mind Balance Index = report (7-day) wellbeing score when available.
  static int resolveMindBalanceWellbeingScore(
    WellnessDashboardData homeWindow, {
    WellnessDashboardData reportWindow = WellnessDashboardData.empty,
  }) =>
      _resolveWellbeingScore(homeWindow, reportWellness: reportWindow);

  static int _resolveWellbeingScore(
    WellnessDashboardData wellness, {
    WellnessDashboardData reportWellness = WellnessDashboardData.empty,
  }) {
    final reportWb = reportWellness.wellbeingScore;
    if (reportWb > 0) return reportWb.clamp(0, 100);
    final homeWb = wellness.wellbeingScore;
    if (homeWb > 0) return homeWb.clamp(0, 100);
    if (wellness.mentalHealth.hasData) {
      return (100 - wellness.mentalHealth.overall.score)
          .round()
          .clamp(0, 100);
    }
    if (reportWellness.mentalHealth.hasData) {
      return (100 - reportWellness.mentalHealth.overall.score)
          .round()
          .clamp(0, 100);
    }
    return 0;
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
    const thresholdLabel = 'Daily threshold · 5h';
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
