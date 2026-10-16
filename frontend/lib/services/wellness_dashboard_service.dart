import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../utils/resilient_http.dart';

class MentalHealthEmotionScore {
  const MentalHealthEmotionScore({required this.score, required this.trend});

  final double score;
  final String trend;

  static const empty = MentalHealthEmotionScore(score: 0, trend: 'flat');

  factory MentalHealthEmotionScore.fromJson(Map<String, dynamic>? j) {
    if (j == null) return MentalHealthEmotionScore.empty;
    return MentalHealthEmotionScore(
      score: (j['score'] as num?)?.toDouble() ?? 0,
      trend: (j['trend'] ?? 'flat').toString(),
    );
  }
}

class MentalHealthOverall {
  const MentalHealthOverall({
    required this.score,
    required this.level,
    required this.colorHex,
  });

  final double score;
  final String level;
  final String colorHex;

  static const empty = MentalHealthOverall(
    score: 0,
    level: 'Normal',
    colorHex: '#43A047',
  );

  factory MentalHealthOverall.fromJson(Map<String, dynamic>? j) {
    if (j == null) return MentalHealthOverall.empty;
    return MentalHealthOverall(
      score: (j['score'] as num?)?.toDouble() ?? 0,
      level: (j['level'] ?? 'Normal').toString(),
      colorHex: (j['color'] ?? '#43A047').toString(),
    );
  }
}

class MentalHealthScores {
  const MentalHealthScores({
    required this.hasData,
    required this.expressionCount,
    required this.minExpressionsRequired,
    required this.stress,
    required this.anxiety,
    required this.depression,
    required this.overall,
    this.lastUpdated,
  });

  static const minExpressionsRequiredDefault = 5;

  final bool hasData;
  final int expressionCount;
  final int minExpressionsRequired;
  final MentalHealthEmotionScore stress;
  final MentalHealthEmotionScore anxiety;
  final MentalHealthEmotionScore depression;
  final MentalHealthOverall overall;
  final String? lastUpdated;

  bool get hasMinimumExpressions =>
      expressionCount >= minExpressionsRequired;

  static const empty = MentalHealthScores(
    hasData: false,
    expressionCount: 0,
    minExpressionsRequired: minExpressionsRequiredDefault,
    stress: MentalHealthEmotionScore.empty,
    anxiety: MentalHealthEmotionScore.empty,
    depression: MentalHealthEmotionScore.empty,
    overall: MentalHealthOverall.empty,
  );

  factory MentalHealthScores.fromJson(Map<String, dynamic>? j) {
    if (j == null) return MentalHealthScores.empty;
    return MentalHealthScores(
      hasData: j['has_data'] == true,
      expressionCount: (j['expression_count'] as num?)?.toInt() ?? 0,
      minExpressionsRequired:
          (j['min_expressions_required'] as num?)?.toInt() ??
          minExpressionsRequiredDefault,
      stress: MentalHealthEmotionScore.fromJson(
        j['stress'] as Map<String, dynamic>?,
      ),
      anxiety: MentalHealthEmotionScore.fromJson(
        j['anxiety'] as Map<String, dynamic>?,
      ),
      depression: MentalHealthEmotionScore.fromJson(
        j['depression'] as Map<String, dynamic>?,
      ),
      overall: MentalHealthOverall.fromJson(
        j['overall'] as Map<String, dynamic>?,
      ),
      lastUpdated: j['last_updated']?.toString(),
    );
  }
}

class WellnessDashboardData {
  const WellnessDashboardData({
    required this.wellbeingScore,
    required this.mentalHealthScore,
    required this.stressIndicator,
    required this.anxietyIndicator,
    required this.depressionIndicator,
    required this.dominantMoodWeek,
    required this.moodLast7,
    required this.contentBuckets,
    required this.totalChunks,
    required this.screenMinutesWeek,
    required this.facetSummary,
    required this.mentalHealth,
    required this.sleepSecondsToday,
    required this.lateNightSecondsToday,
  });

  final int wellbeingScore;
  final int mentalHealthScore;
  final int stressIndicator;
  final int anxietyIndicator;
  final int depressionIndicator;
  final String dominantMoodWeek;
  final List<Map<String, dynamic>> moodLast7;
  final List<Map<String, dynamic>> contentBuckets;
  final int totalChunks;
  final int screenMinutesWeek;
  final String facetSummary;
  final MentalHealthScores mentalHealth;
  final int sleepSecondsToday;
  final int lateNightSecondsToday;

  static const empty = WellnessDashboardData(
    wellbeingScore: 0,
    mentalHealthScore: 0,
    stressIndicator: 0,
    anxietyIndicator: 0,
    depressionIndicator: 0,
    dominantMoodWeek: 'neutral',
    moodLast7: [],
    contentBuckets: [],
    totalChunks: 0,
    screenMinutesWeek: 0,
    facetSummary: '',
    mentalHealth: MentalHealthScores.empty,
    sleepSecondsToday: 0,
    lateNightSecondsToday: 0,
  );

  factory WellnessDashboardData.fromJson(Map<String, dynamic> j) {
    final mood = (j['mood_last_7'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final buckets = (j['content_bucket_counts'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final mh = MentalHealthScores.fromJson(
      j['mental_health'] as Map<String, dynamic>?,
    );
    return WellnessDashboardData(
      wellbeingScore: (j['wellbeing_score'] as num?)?.toInt() ?? 0,
      mentalHealthScore: (j['mental_health_score'] as num?)?.toInt() ?? 0,
      stressIndicator: (j['stress_indicator'] as num?)?.toInt() ?? 0,
      anxietyIndicator: (j['anxiety_indicator'] as num?)?.toInt() ?? 0,
      depressionIndicator: (j['depression_indicator'] as num?)?.toInt() ?? 0,
      dominantMoodWeek: (j['dominant_mood_week'] ?? 'neutral').toString(),
      moodLast7: mood,
      contentBuckets: buckets,
      totalChunks: (j['total_chunks'] as num?)?.toInt() ?? 0,
      screenMinutesWeek: (j['screen_minutes_week'] as num?)?.toInt() ?? 0,
      facetSummary: (j['facet_summary'] ?? '').toString(),
      mentalHealth: mh,
      sleepSecondsToday: (j['sleep_seconds_today'] as num?)?.toInt() ?? 0,
      lateNightSecondsToday:
          (j['late_night_seconds_today'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Last-7-days-derived scores for Home / reports (backed by Django).
class WellnessDashboardService {
  WellnessDashboardService._();
  static final WellnessDashboardService instance = WellnessDashboardService._();

  final ValueNotifier<WellnessDashboardData> dashboard =
      ValueNotifier<WellnessDashboardData>(WellnessDashboardData.empty);

  DateTime? _lastFetch;
  bool _inFlight = false;
  String? _scopedUserId;

  void resetForNewUser() {
    _lastFetch = null;
    _scopedUserId = null;
    _inFlight = false;
    dashboard.value = WellnessDashboardData.empty;
  }

  Future<String?> _userId() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('auth.userId') ?? '';
    return uid.isEmpty ? null : uid;
  }

  static const _wellbeingDateKey = 'home.wellbeing.score_date';
  static const _wellbeingScoreKey = 'home.wellbeing.score';
  static const _wellbeingYesterdayKey = 'home.wellbeing.yesterday_score';

  final ValueNotifier<int> wellbeingDeltaPoints = ValueNotifier<int>(0);

  Future<void> _persistWellbeingDelta(int score) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final storedDate = prefs.getString(_wellbeingDateKey) ?? '';
    if (storedDate.isNotEmpty && storedDate != today) {
      final prevScore = prefs.getInt(_wellbeingScoreKey);
      if (prevScore != null) {
        await prefs.setInt(_wellbeingYesterdayKey, prevScore);
      }
    }
    final yesterday = prefs.getInt(_wellbeingYesterdayKey);
    wellbeingDeltaPoints.value =
        yesterday != null ? score - yesterday : 0;
    await prefs.setString(_wellbeingDateKey, today);
    await prefs.setInt(_wellbeingScoreKey, score);
  }

  Future<void> refresh({bool force = false, int days = 7}) async {
    if (_inFlight) return;
    final uid = await _userId();
    if (uid == null) {
      resetForNewUser();
      return;
    }
    if (_scopedUserId != null && _scopedUserId != uid) {
      dashboard.value = WellnessDashboardData.empty;
    }
    _scopedUserId = uid;

    final now = DateTime.now();
    if (!force &&
        _lastFetch != null &&
        now.difference(_lastFetch!) < const Duration(minutes: 5)) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth.accessToken') ?? '';
    if (token.isEmpty) {
      resetForNewUser();
      return;
    }
    _inFlight = true;
    try {
      final decoded = await getJsonWithRetry(
        Uri.parse('${ApiConfig.baseUrl}/api/auth/dashboard/wellness/?days=$days'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      _lastFetch = DateTime.now();
      if (decoded != null) {
        final next = WellnessDashboardData.fromJson(decoded);
        dashboard.value = next;
        await _persistWellbeingDelta(next.wellbeingScore);
      }
    } catch (_) {
      // keep last good payload
    } finally {
      _inFlight = false;
    }
  }
}
