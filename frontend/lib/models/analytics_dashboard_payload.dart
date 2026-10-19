import '../widgets/behavioral_insights_modules.dart';

class AnalyticsMindSyncIndex {
  const AnalyticsMindSyncIndex({
    required this.wellbeingScore,
    required this.stressAvg,
    required this.depressionAvg,
    required this.latestEmotion,
    this.trendPointsVsPrior,
  });

  final int wellbeingScore;
  final double stressAvg;
  final double depressionAvg;
  final String latestEmotion;
  final int? trendPointsVsPrior;

  factory AnalyticsMindSyncIndex.fromJson(Map<String, dynamic>? j) {
    if (j == null) return AnalyticsMindSyncIndex.empty;
    return AnalyticsMindSyncIndex(
      wellbeingScore: (j['wellbeing_score'] as num?)?.toInt() ?? 0,
      stressAvg: (j['stress_avg'] as num?)?.toDouble() ?? 0,
      depressionAvg: (j['depression_avg'] as num?)?.toDouble() ?? 0,
      latestEmotion: (j['latest_emotion'] ?? '').toString().trim(),
      trendPointsVsPrior: (j['trend_points_vs_prior'] as num?)?.toInt(),
    );
  }

  static const empty = AnalyticsMindSyncIndex(
    wellbeingScore: 0,
    stressAvg: 0,
    depressionAvg: 0,
    latestEmotion: '',
  );
}

class AnalyticsBehaviorMetrics {
  const AnalyticsBehaviorMetrics({
    required this.sleepMinutes,
    required this.sleepDisplay,
    required this.moodScore,
    required this.moodCaption,
    required this.avgDailyScreenSeconds,
    required this.avgDailyScreenDisplay,
  });

  final int sleepMinutes;
  final String sleepDisplay;
  final int moodScore;
  final String moodCaption;
  final int avgDailyScreenSeconds;
  final String avgDailyScreenDisplay;

  factory AnalyticsBehaviorMetrics.fromJson(Map<String, dynamic>? j) {
    if (j == null) return AnalyticsBehaviorMetrics.empty;
    return AnalyticsBehaviorMetrics(
      sleepMinutes: (j['sleep_minutes'] as num?)?.toInt() ?? 0,
      sleepDisplay: (j['sleep_display'] ?? '—').toString(),
      moodScore: (j['mood_score'] as num?)?.toInt() ?? 0,
      moodCaption: (j['mood_caption'] ?? '').toString(),
      avgDailyScreenSeconds:
          (j['avg_daily_screen_seconds'] as num?)?.toInt() ?? 0,
      avgDailyScreenDisplay:
          (j['avg_daily_screen_display'] ?? '—').toString(),
    );
  }

  static const empty = AnalyticsBehaviorMetrics(
    sleepMinutes: 0,
    sleepDisplay: '—',
    moodScore: 0,
    moodCaption: '',
    avgDailyScreenSeconds: 0,
    avgDailyScreenDisplay: '—',
  );
}

class AnalyticsRhythmChart {
  const AnalyticsRhythmChart({
    required this.labels,
    required this.hoursPerDay,
    required this.peakDayLabel,
  });

  final List<String> labels;
  final List<double> hoursPerDay;
  final String peakDayLabel;

  factory AnalyticsRhythmChart.fromJson(Map<String, dynamic>? j) {
    if (j == null) return AnalyticsRhythmChart.empty;
    final labels = (j['labels'] as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .toList();
    final hours = (j['hours_per_day'] as List<dynamic>? ?? const [])
        .map((e) => (e as num?)?.toDouble() ?? 0)
        .toList();
    return AnalyticsRhythmChart(
      labels: labels,
      hoursPerDay: hours,
      peakDayLabel: (j['peak_day_label'] ?? '').toString(),
    );
  }

  static const empty = AnalyticsRhythmChart(
    labels: [],
    hoursPerDay: [],
    peakDayLabel: '',
  );
}

class AnalyticsLateNightActivity {
  const AnalyticsLateNightActivity({
    required this.totalSeconds,
    required this.socialMediaSeconds,
    required this.topAppName,
    required this.topAppSeconds,
    required this.totalDisplay,
    required this.socialDisplay,
    required this.topAppDisplay,
    required this.periodLabel,
  });

  final int totalSeconds;
  final int socialMediaSeconds;
  final String topAppName;
  final int topAppSeconds;
  final String totalDisplay;
  final String socialDisplay;
  final String topAppDisplay;
  final String periodLabel;

  bool get hasData => totalSeconds > 0 || topAppSeconds > 0;

  factory AnalyticsLateNightActivity.fromJson(Map<String, dynamic>? j) {
    if (j == null) return AnalyticsLateNightActivity.empty;
    return AnalyticsLateNightActivity(
      totalSeconds: (j['total_seconds'] as num?)?.toInt() ?? 0,
      socialMediaSeconds: (j['social_media_seconds'] as num?)?.toInt() ?? 0,
      topAppName: (j['top_app_name'] ?? '').toString(),
      topAppSeconds: (j['top_app_seconds'] as num?)?.toInt() ?? 0,
      totalDisplay: (j['total_display'] ?? '0m').toString(),
      socialDisplay: (j['social_display'] ?? '0m').toString(),
      topAppDisplay: (j['top_app_display'] ?? '0m').toString(),
      periodLabel: (j['period_label'] ?? '').toString(),
    );
  }

  static const empty = AnalyticsLateNightActivity(
    totalSeconds: 0,
    socialMediaSeconds: 0,
    topAppName: '',
    topAppSeconds: 0,
    totalDisplay: '0m',
    socialDisplay: '0m',
    topAppDisplay: '0m',
    periodLabel: '',
  );
}

class AnalyticsDashboardPayload {
  const AnalyticsDashboardPayload({
    required this.period,
    required this.periodLabel,
    required this.mindsyncIndex,
    required this.behavior,
    required this.rhythm,
    required this.lateNight,
    required this.behaviourStudy,
    required this.facialExpressionStudy,
    required this.contentTypeAnalysis,
  });

  final String period;
  final String periodLabel;
  final AnalyticsMindSyncIndex mindsyncIndex;
  final AnalyticsBehaviorMetrics behavior;
  final AnalyticsRhythmChart rhythm;
  final AnalyticsLateNightActivity lateNight;
  final BehaviourStudyData behaviourStudy;
  final FacialExpressionStudyData facialExpressionStudy;
  final ContentTypeAnalysisData contentTypeAnalysis;

  static const empty = AnalyticsDashboardPayload(
    period: 'week',
    periodLabel: '',
    mindsyncIndex: AnalyticsMindSyncIndex.empty,
    behavior: AnalyticsBehaviorMetrics.empty,
    rhythm: AnalyticsRhythmChart.empty,
    lateNight: AnalyticsLateNightActivity.empty,
    behaviourStudy: BehaviourStudyData.empty,
    facialExpressionStudy: FacialExpressionStudyData.empty,
    contentTypeAnalysis: ContentTypeAnalysisData.empty,
  );

  factory AnalyticsDashboardPayload.fromJson(Map<String, dynamic> j) {
    final insights = j['insights'] as Map<String, dynamic>? ?? {};
    return AnalyticsDashboardPayload(
      period: (j['period'] ?? 'week').toString(),
      periodLabel: (j['period_label'] ?? '').toString(),
      mindsyncIndex: AnalyticsMindSyncIndex.fromJson(
        j['mindsync_index'] as Map<String, dynamic>?,
      ),
      behavior: AnalyticsBehaviorMetrics.fromJson(
        j['behavior'] as Map<String, dynamic>?,
      ),
      rhythm: AnalyticsRhythmChart.fromJson(
        j['rhythm'] as Map<String, dynamic>?,
      ),
      lateNight: AnalyticsLateNightActivity.fromJson(
        j['late_night_activity'] as Map<String, dynamic>?,
      ),
      behaviourStudy: BehaviourStudyData.fromJson(
        insights['behaviour_study'] as Map<String, dynamic>?,
      ),
      facialExpressionStudy: FacialExpressionStudyData.fromJson(
        insights['facial_expression_study'] as Map<String, dynamic>?,
      ),
      contentTypeAnalysis: ContentTypeAnalysisData.fromJson(
        insights['content_type_analysis'] as Map<String, dynamic>?,
      ),
    );
  }
}
