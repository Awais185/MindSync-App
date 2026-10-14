class SevenDayStudioReport {
  SevenDayStudioReport({
    required this.user,
    required this.range,
    required this.summary,
    required this.pastReports,
    required this.dailyMentalHealth,
    required this.contentTypeAnalytics,
    required this.mentalHealthInsights,
    required this.metricCards,
    required this.wellbeing,
    required this.charts,
    required this.sleepQuality,
    required this.riskSummary,
    required this.aiConfidence,
    required this.dailySummary,
    required this.metricsStatus,
    required this.clinicalSummary,
    required this.conditionAveragesLine,
  });

  final StudioUser user;
  final StudioRange range;
  final StudioSummary summary;
  final List<StudioPastReport> pastReports;
  final List<StudioDailyMental> dailyMentalHealth;
  final List<StudioContentType> contentTypeAnalytics;
  final List<String> mentalHealthInsights;
  final StudioMetricCards metricCards;
  final StudioWellbeing wellbeing;
  final StudioCharts charts;
  final StudioSleepQuality sleepQuality;
  final StudioRiskSummary riskSummary;
  final StudioAiConfidence aiConfidence;
  final List<StudioDailySummaryRow> dailySummary;
  final StudioMetricsStatus metricsStatus;
  final String clinicalSummary;
  final String conditionAveragesLine;

  bool get hasData =>
      summary.analysedVideoChunks > 0 ||
      summary.wellbeingScore != null ||
      dailyMentalHealth.any((d) => d.stress != null);

  /// Shown when API/studio payload is missing — keeps full report layout visible.
  factory SevenDayStudioReport.empty({String name = '', String email = ''}) {
    return SevenDayStudioReport(
      user: StudioUser(name: name, email: email, avatar: ''),
      range: StudioRange(startDate: '', endDate: '', label: 'Last 7 days'),
      summary: StudioSummary(
        wellbeingScore: null,
        mentalWellnessIndex: null,
        stress: null,
        anxiety: null,
        depression: null,
        analysedVideoChunks: 0,
        screenOnMinutes: 0,
        dominantMoodTrend: '',
        moodStatus: 'No data',
      ),
      pastReports: const [],
      dailyMentalHealth: List.generate(
        7,
        (i) => StudioDailyMental(
          date: '',
          dayLabel: 'Day ${i + 1}',
          stress: null,
          anxiety: null,
          depression: null,
        ),
      ),
      contentTypeAnalytics: const [],
      mentalHealthInsights: const [],
      metricCards: StudioMetricCards(
        avgScreen: StudioMetricCard(label: 'Avg Screen', display: '—', status: 'No Data'),
        mood: StudioMetricCard(label: 'Mood', display: '—', status: 'No Data'),
        sleep: StudioMetricCard(label: 'Sleep', display: '—', status: 'No Data'),
        wellbeing: StudioMetricCard(label: 'Wellbeing', display: '—', status: 'No Data'),
      ),
      wellbeing: StudioWellbeing(
        score: null,
        message: '',
        usageCategories: const [],
        recommendation: '',
      ),
      charts: StudioCharts(
        screenTimeVsMood: const [],
        dailyScreenTrend: const [],
        moodOverWeek: const [],
      ),
      sleepQuality: StudioSleepQuality(
        score: null,
        status: 'No Data',
        message: 'Uses phone use between 10 PM – 5 AM (local time, last 7 days) plus rough daytime load.',
        lateNightHours: 0,
      ),
      riskSummary: StudioRiskSummary(
        hasRisk: false,
        riskDays: 0,
        message: 'No risk factors detected this week.',
        alerts: const [],
      ),
      aiConfidence: StudioAiConfidence(
        emotion: null,
        behavior: null,
        risk: null,
        banner: 'Not enough data for confidence analysis',
        isFallback: true,
      ),
      dailySummary: List.generate(
        7,
        (i) => StudioDailySummaryRow(
          day: 'Day ${i + 1}',
          date: '',
          screen: 'No data',
          mood: 'No data',
        ),
      ),
      metricsStatus: StudioMetricsStatus(
        normal: 0,
        positive: 0,
        stable: 0,
        warning: 0,
        message: 'No data for this period yet',
      ),
      clinicalSummary: '',
      conditionAveragesLine: '',
    );
  }

  factory SevenDayStudioReport.fromJson(Map<String, dynamic> json) {
    return SevenDayStudioReport(
      user: StudioUser.fromJson(json['user'] as Map<String, dynamic>? ?? {}),
      range: StudioRange.fromJson(json['range'] as Map<String, dynamic>? ?? {}),
      summary: StudioSummary.fromJson(json['summary'] as Map<String, dynamic>? ?? {}),
      pastReports: (json['past_reports'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(StudioPastReport.fromJson)
          .toList(),
      dailyMentalHealth: (json['daily_mental_health'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(StudioDailyMental.fromJson)
          .toList(),
      contentTypeAnalytics: (json['content_type_analytics'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(StudioContentType.fromJson)
          .toList(),
      mentalHealthInsights: (json['mental_health_insights'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .where((s) => s.trim().isNotEmpty)
          .toList(),
      metricCards: StudioMetricCards.fromJson(
        json['metric_cards'] as Map<String, dynamic>? ?? {},
      ),
      wellbeing: StudioWellbeing.fromJson(json['wellbeing'] as Map<String, dynamic>? ?? {}),
      charts: StudioCharts.fromJson(json['charts'] as Map<String, dynamic>? ?? {}),
      sleepQuality: StudioSleepQuality.fromJson(
        json['sleep_quality'] as Map<String, dynamic>? ?? {},
      ),
      riskSummary: StudioRiskSummary.fromJson(
        json['risk_summary'] as Map<String, dynamic>? ?? {},
      ),
      aiConfidence: StudioAiConfidence.fromJson(
        json['ai_confidence'] as Map<String, dynamic>? ?? {},
      ),
      dailySummary: (json['daily_summary'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(StudioDailySummaryRow.fromJson)
          .toList(),
      metricsStatus: StudioMetricsStatus.fromJson(
        json['metrics_status'] as Map<String, dynamic>? ?? {},
      ),
      clinicalSummary: (json['clinical_summary'] ?? '').toString(),
      conditionAveragesLine: (json['condition_averages_line'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'user': {
          'name': user.name,
          'email': user.email,
          'avatar': user.avatar,
        },
        'range': {
          'start_date': range.startDate,
          'end_date': range.endDate,
          'label': range.label,
        },
        'summary': {
          'wellbeing_score': summary.wellbeingScore,
          'mental_wellness_index': summary.mentalWellnessIndex,
          'stress': summary.stress,
          'anxiety': summary.anxiety,
          'depression': summary.depression,
          'analysed_video_chunks': summary.analysedVideoChunks,
          'screen_on_minutes': summary.screenOnMinutes,
          'dominant_mood_trend': summary.dominantMoodTrend,
          'mood_status': summary.moodStatus,
        },
        'past_reports': pastReports
            .map(
              (p) => {
                'id': p.id,
                'week_start': p.weekStart,
                'week_end': p.weekEnd,
                'generated_at': p.generatedAt,
              },
            )
            .toList(),
        'daily_mental_health': dailyMentalHealth
            .map(
              (d) => {
                'date': d.date,
                'day_label': d.dayLabel,
                'stress': d.stress,
                'anxiety': d.anxiety,
                'depression': d.depression,
              },
            )
            .toList(),
        'content_type_analytics': contentTypeAnalytics
            .map((c) => {'label': c.label, 'count': c.count, 'percent': c.percent})
            .toList(),
        'mental_health_insights': mentalHealthInsights,
        'metric_cards': {
          'avg_screen': _metricToJson(metricCards.avgScreen),
          'mood': _metricToJson(metricCards.mood),
          'sleep': _metricToJson(metricCards.sleep),
          'wellbeing': _metricToJson(metricCards.wellbeing),
        },
        'wellbeing': {
          'score': wellbeing.score,
          'message': wellbeing.message,
          'usage_categories': wellbeing.usageCategories
              .map((c) => {'label': c.label, 'percent': c.percent})
              .toList(),
          'recommendation': wellbeing.recommendation,
        },
        'charts': {
          'screen_time_vs_mood': charts.screenTimeVsMood,
          'daily_screen_trend': charts.dailyScreenTrend,
          'mood_over_week': charts.moodOverWeek,
        },
        'sleep_quality': {
          'score': sleepQuality.score,
          'status': sleepQuality.status,
          'message': sleepQuality.message,
          'late_night_hours': sleepQuality.lateNightHours,
        },
        'risk_summary': {
          'has_risk': riskSummary.hasRisk,
          'risk_days': riskSummary.riskDays,
          'message': riskSummary.message,
          'alerts': riskSummary.alerts,
        },
        'ai_confidence': {
          'emotion': aiConfidence.emotion,
          'behavior': aiConfidence.behavior,
          'risk': aiConfidence.risk,
          'banner': aiConfidence.banner,
          'is_fallback': aiConfidence.isFallback,
        },
        'daily_summary': dailySummary
            .map(
              (r) => {
                'day': r.day,
                'date': r.date,
                'screen': r.screen,
                'mood': r.mood,
              },
            )
            .toList(),
        'metrics_status': {
          'normal': metricsStatus.normal,
          'positive': metricsStatus.positive,
          'stable': metricsStatus.stable,
          'warning': metricsStatus.warning,
          'message': metricsStatus.message,
        },
        'clinical_summary': clinicalSummary,
        'condition_averages_line': conditionAveragesLine,
      };

  static Map<String, dynamic> _metricToJson(StudioMetricCard c) => {
        'label': c.label,
        'display': c.display,
        'status': c.status,
        'value': c.value,
      };
}

class StudioUser {
  StudioUser({required this.name, required this.email, required this.avatar});
  final String name;
  final String email;
  final String avatar;
  factory StudioUser.fromJson(Map<String, dynamic> j) => StudioUser(
        name: (j['name'] ?? '').toString(),
        email: (j['email'] ?? '').toString(),
        avatar: (j['avatar'] ?? '').toString(),
      );
}

class StudioRange {
  StudioRange({required this.startDate, required this.endDate, required this.label});
  final String startDate;
  final String endDate;
  final String label;
  factory StudioRange.fromJson(Map<String, dynamic> j) => StudioRange(
        startDate: (j['start_date'] ?? '').toString(),
        endDate: (j['end_date'] ?? '').toString(),
        label: (j['label'] ?? 'Last 7 days').toString(),
      );
}

class StudioSummary {
  StudioSummary({
    required this.wellbeingScore,
    required this.mentalWellnessIndex,
    required this.stress,
    required this.anxiety,
    required this.depression,
    required this.analysedVideoChunks,
    required this.screenOnMinutes,
    required this.dominantMoodTrend,
    required this.moodStatus,
  });
  final int? wellbeingScore;
  final int? mentalWellnessIndex;
  final int? stress;
  final int? anxiety;
  final int? depression;
  final int analysedVideoChunks;
  final int screenOnMinutes;
  final String dominantMoodTrend;
  final String moodStatus;
  factory StudioSummary.fromJson(Map<String, dynamic> j) => StudioSummary(
        wellbeingScore: _intOrNull(j['wellbeing_score']),
        mentalWellnessIndex: _intOrNull(j['mental_wellness_index']),
        stress: _intOrNull(j['stress']),
        anxiety: _intOrNull(j['anxiety']),
        depression: _intOrNull(j['depression']),
        analysedVideoChunks: _intOrNull(j['analysed_video_chunks']) ?? 0,
        screenOnMinutes: _intOrNull(j['screen_on_minutes']) ?? 0,
        dominantMoodTrend: (j['dominant_mood_trend'] ?? '').toString(),
        moodStatus: (j['mood_status'] ?? 'No data').toString(),
      );
}

class StudioPastReport {
  StudioPastReport({
    required this.id,
    required this.weekStart,
    required this.weekEnd,
    required this.generatedAt,
  });
  final int? id;
  final String weekStart;
  final String weekEnd;
  final String generatedAt;
  factory StudioPastReport.fromJson(Map<String, dynamic> j) => StudioPastReport(
        id: _intOrNull(j['id']),
        weekStart: (j['week_start'] ?? '').toString(),
        weekEnd: (j['week_end'] ?? '').toString(),
        generatedAt: (j['generated_at'] ?? '').toString(),
      );
}

class StudioDailyMental {
  StudioDailyMental({
    required this.date,
    required this.dayLabel,
    required this.stress,
    required this.anxiety,
    required this.depression,
  });
  final String date;
  final String dayLabel;
  final int? stress;
  final int? anxiety;
  final int? depression;
  factory StudioDailyMental.fromJson(Map<String, dynamic> j) => StudioDailyMental(
        date: (j['date'] ?? '').toString(),
        dayLabel: (j['day_label'] ?? '').toString(),
        stress: _intOrNull(j['stress']),
        anxiety: _intOrNull(j['anxiety']),
        depression: _intOrNull(j['depression']),
      );
}

class StudioContentType {
  StudioContentType({required this.label, required this.count, required this.percent});
  final String label;
  final int count;
  final int percent;
  factory StudioContentType.fromJson(Map<String, dynamic> j) => StudioContentType(
        label: (j['label'] ?? 'Other').toString(),
        count: _intOrNull(j['count']) ?? 0,
        percent: _intOrNull(j['percent']) ?? 0,
      );
}

class StudioMetricCard {
  StudioMetricCard({
    required this.label,
    required this.display,
    required this.status,
    this.value,
  });
  final String label;
  final String display;
  final String status;
  final num? value;
  factory StudioMetricCard.fromJson(Map<String, dynamic> j) => StudioMetricCard(
        label: (j['label'] ?? '').toString(),
        display: (j['display'] ?? '—').toString(),
        status: (j['status'] ?? 'No Data').toString(),
        value: j['value'] as num?,
      );
}

class StudioMetricCards {
  StudioMetricCards({
    required this.avgScreen,
    required this.mood,
    required this.sleep,
    required this.wellbeing,
  });
  final StudioMetricCard avgScreen;
  final StudioMetricCard mood;
  final StudioMetricCard sleep;
  final StudioMetricCard wellbeing;
  factory StudioMetricCards.fromJson(Map<String, dynamic> j) => StudioMetricCards(
        avgScreen: StudioMetricCard.fromJson(j['avg_screen'] as Map<String, dynamic>? ?? {}),
        mood: StudioMetricCard.fromJson(j['mood'] as Map<String, dynamic>? ?? {}),
        sleep: StudioMetricCard.fromJson(j['sleep'] as Map<String, dynamic>? ?? {}),
        wellbeing: StudioMetricCard.fromJson(j['wellbeing'] as Map<String, dynamic>? ?? {}),
      );
}

class StudioUsageCategory {
  StudioUsageCategory({required this.label, required this.percent});
  final String label;
  final int percent;
  factory StudioUsageCategory.fromJson(Map<String, dynamic> j) => StudioUsageCategory(
        label: (j['label'] ?? '').toString(),
        percent: _intOrNull(j['percent']) ?? 0,
      );
}

class StudioWellbeing {
  StudioWellbeing({
    required this.score,
    required this.message,
    required this.usageCategories,
    required this.recommendation,
  });
  final int? score;
  final String message;
  final List<StudioUsageCategory> usageCategories;
  final String recommendation;
  factory StudioWellbeing.fromJson(Map<String, dynamic> j) => StudioWellbeing(
        score: _intOrNull(j['score']),
        message: (j['message'] ?? '').toString(),
        usageCategories: (j['usage_categories'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(StudioUsageCategory.fromJson)
            .toList(),
        recommendation: (j['recommendation'] ?? '').toString(),
      );
}

class StudioCharts {
  StudioCharts({
    required this.screenTimeVsMood,
    required this.dailyScreenTrend,
    required this.moodOverWeek,
  });
  final List<Map<String, dynamic>> screenTimeVsMood;
  final List<Map<String, dynamic>> dailyScreenTrend;
  final List<Map<String, dynamic>> moodOverWeek;
  factory StudioCharts.fromJson(Map<String, dynamic> j) => StudioCharts(
        screenTimeVsMood: (j['screen_time_vs_mood'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .toList(),
        dailyScreenTrend: (j['daily_screen_trend'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .toList(),
        moodOverWeek: (j['mood_over_week'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .toList(),
      );
}

class StudioSleepQuality {
  StudioSleepQuality({
    required this.score,
    required this.status,
    required this.message,
    required this.lateNightHours,
  });
  final int? score;
  final String status;
  final String message;
  final double lateNightHours;
  factory StudioSleepQuality.fromJson(Map<String, dynamic> j) => StudioSleepQuality(
        score: _intOrNull(j['score']),
        status: (j['status'] ?? 'No Data').toString(),
        message: (j['message'] ?? '').toString(),
        lateNightHours: (j['late_night_hours'] as num?)?.toDouble() ?? 0,
      );
}

class StudioRiskSummary {
  StudioRiskSummary({
    required this.hasRisk,
    required this.riskDays,
    required this.message,
    required this.alerts,
  });
  final bool hasRisk;
  final int riskDays;
  final String message;
  final List<String> alerts;
  factory StudioRiskSummary.fromJson(Map<String, dynamic> j) => StudioRiskSummary(
        hasRisk: j['has_risk'] == true,
        riskDays: _intOrNull(j['risk_days']) ?? 0,
        message: (j['message'] ?? '').toString(),
        alerts: (j['alerts'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
      );
}

class StudioAiConfidence {
  StudioAiConfidence({
    required this.emotion,
    required this.behavior,
    required this.risk,
    required this.banner,
    required this.isFallback,
  });
  final int? emotion;
  final int? behavior;
  final int? risk;
  final String banner;
  final bool isFallback;
  factory StudioAiConfidence.fromJson(Map<String, dynamic> j) => StudioAiConfidence(
        emotion: _intOrNull(j['emotion']),
        behavior: _intOrNull(j['behavior']),
        risk: _intOrNull(j['risk']),
        banner: (j['banner'] ?? '').toString(),
        isFallback: j['is_fallback'] == true,
      );
}

class StudioDailySummaryRow {
  StudioDailySummaryRow({
    required this.day,
    required this.date,
    required this.screen,
    required this.mood,
  });
  final String day;
  final String date;
  final String screen;
  final String mood;
  factory StudioDailySummaryRow.fromJson(Map<String, dynamic> j) => StudioDailySummaryRow(
        day: (j['day'] ?? '').toString(),
        date: (j['date'] ?? '').toString(),
        screen: (j['screen'] ?? 'No data').toString(),
        mood: (j['mood'] ?? 'No data').toString(),
      );
}

class StudioMetricsStatus {
  StudioMetricsStatus({
    required this.normal,
    required this.positive,
    required this.stable,
    required this.warning,
    required this.message,
  });
  final int normal;
  final int positive;
  final int stable;
  final int warning;
  final String message;
  factory StudioMetricsStatus.fromJson(Map<String, dynamic> j) => StudioMetricsStatus(
        normal: _intOrNull(j['normal']) ?? 0,
        positive: _intOrNull(j['positive']) ?? 0,
        stable: _intOrNull(j['stable']) ?? 0,
        warning: _intOrNull(j['warning']) ?? 0,
        message: (j['message'] ?? '').toString(),
      );
}

int? _intOrNull(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.round();
  return int.tryParse(v.toString());
}
