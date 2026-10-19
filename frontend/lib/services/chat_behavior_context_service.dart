import '../models/late_night_sleep_snapshot.dart';
import 'screen_time_service.dart';
import 'wellness_dashboard_service.dart';

/// Collects on-device + cached wellness data for Gemini chat context (API only).
class ChatBehaviorContextService {
  ChatBehaviorContextService._();
  static final ChatBehaviorContextService instance = ChatBehaviorContextService._();

  /// Refreshes wellness cache when stale, then returns a structured payload.
  Future<Map<String, dynamic>> buildPayload({bool forceRefresh = true}) async {
    if (forceRefresh) {
      await WellnessDashboardService.instance.refreshHome(force: true);
    }

    final screen = ScreenTimeService.instance.snapshot.value;
    final wellness = WellnessDashboardService.instance.dashboard.value;
    final sleep = screen.lateNightSleep;

    final topApps = screen.topApps
        .take(5)
        .map((a) => '${a.appName} (${formatDurationShort(a.durationSeconds)})')
        .toList();

    final lateCats = sleep.lateNightCategoriesWeek.isNotEmpty
        ? sleep.lateNightCategoriesWeek.entries
            .map((e) => '${e.key} (${formatDurationShort(e.value * 60)})')
            .toList()
        : sleep.lateNightCategoriesTonight.entries
            .map((e) => '${e.key} (${formatDurationShort(e.value * 60)})')
            .toList();

    final contentTypes = wellness.contentBuckets
        .map((b) {
          final label = (b['label'] ?? b['category'] ?? b['name'] ?? '').toString();
          final pct = b['percent'] ?? b['value'];
          if (label.isEmpty) return null;
          if (pct != null) return '$label ($pct%)';
          return label;
        })
        .whereType<String>()
        .take(5)
        .toList();

    final insights = <String>[
      if (wellness.facetSummary.trim().isNotEmpty) wellness.facetSummary.trim(),
      if (wellness.dominantMoodWeek.trim().isNotEmpty &&
          wellness.dominantMoodWeek != 'neutral')
        'Dominant mood this week: ${wellness.dominantMoodWeek}',
    ];

    final mood = <String, dynamic>{
      if (wellness.mentalHealth.hasData) ...{
        'stress_score': wellness.mentalHealth.stress.score.round(),
        'anxiety_score': wellness.mentalHealth.anxiety.score.round(),
        'depression_score': wellness.mentalHealth.depression.score.round(),
        'wellbeing_score': wellness.wellbeingScore,
      },
      if (wellness.stressIndicator > 0) 'stress': wellness.stressIndicator,
      if (wellness.anxietyIndicator > 0) 'anxiety_score': wellness.anxietyIndicator,
      if (wellness.depressionIndicator > 0)
        'depression_score': wellness.depressionIndicator,
      if (wellness.dominantMoodWeek.isNotEmpty)
        'emotion': wellness.dominantMoodWeek,
    };

    final hasScreen = screen.usageStatsGranted &&
        (screen.daySeconds > 0 || screen.weekSeconds > 0);
    final hasSleep = sleep.hasData;
    final hasWellness = wellness.mentalHealth.hasData ||
        wellness.contentBuckets.isNotEmpty ||
        wellness.wellbeingScore > 0;

    if (!hasScreen && !hasSleep && !hasWellness && contentTypes.isEmpty) {
      return {'has_data': false};
    }

    final weekSummary = _buildSevenDaySummary(screen, wellness, sleep);

    return {
      'has_data': true,
      'screen_time': {
        if (screen.daySeconds > 0) 'today_total': formatDurationShort(screen.daySeconds),
        if (screen.socialSeconds > 0)
          'today_social': formatDurationShort(screen.socialSeconds),
        if (screen.videoSeconds > 0)
          'today_entertainment_video': formatDurationShort(screen.videoSeconds),
        if (screen.weekSeconds > 0) 'week_total': formatDurationShort(screen.weekSeconds),
        if (topApps.isNotEmpty) 'top_apps_today': topApps,
      },
      'late_night': {
        if (sleep.lateNightTonightMinutes > 0)
          'today_duration': formatDurationShort(sleep.lateNightTonightMinutes * 60),
        if (sleep.lateNightWeekMinutes > 0)
          'week_duration': formatDurationShort(sleep.lateNightWeekMinutes * 60),
        if (lateCats.isNotEmpty) 'categories_week': lateCats,
        if (screen.lateNightWeekSeconds > 0 && sleep.lateNightWeekMinutes == 0)
          'week_duration': formatDurationShort(screen.lateNightWeekSeconds),
      },
      if (contentTypes.isNotEmpty) 'content_types': contentTypes,
      if (insights.isNotEmpty) 'behaviour_insights': insights,
      if (mood.isNotEmpty) 'mood_indicators': mood,
      'sleep_estimate': {
        if (sleep.sleepTonightMinutes > 0)
          'tonight_minutes': sleep.sleepTonightMinutes,
        if (sleep.sleepWeekMinutes > 0) 'week_minutes': sleep.sleepWeekMinutes,
        if (sleep.sleepTonightMinutes > 0)
          'hours': double.parse(
            (sleep.sleepTonightMinutes / 60.0).toStringAsFixed(1),
          ),
      },
      if (weekSummary.isNotEmpty) 'seven_day_summary': weekSummary,
      if (wellness.totalChunks > 0) 'observed_chunks_7d': wellness.totalChunks,
    };
  }

  String _buildSevenDaySummary(
    ScreenTimeSnapshot screen,
    WellnessDashboardData wellness,
    LateNightSleepSnapshot sleep,
  ) {
    final parts = <String>[];
    if (screen.weekSeconds > 0) {
      parts.add('Weekly screen time ${formatDurationShort(screen.weekSeconds)}');
    }
    if (wellness.screenMinutesWeek > 0) {
      parts.add('Dashboard weekly screen ${wellness.screenMinutesWeek} min');
    }
    if (sleep.lateNightWeekMinutes > 0) {
      parts.add(
        'Late-night activity ${formatDurationShort(sleep.lateNightWeekMinutes * 60)}',
      );
    }
    if (wellness.mentalHealth.hasMinimumExpressions) {
      parts.add(
        'Mental health scores — stress ${wellness.mentalHealth.stress.score.round()}, '
        'anxiety ${wellness.mentalHealth.anxiety.score.round()}, '
        'depression ${wellness.mentalHealth.depression.score.round()}',
      );
    }
    return parts.join('; ');
  }
}
