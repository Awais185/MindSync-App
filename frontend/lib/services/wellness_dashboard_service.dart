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
    this.openfaceCaptureCount = 0,
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
  final int openfaceCaptureCount;

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
      openfaceCaptureCount:
          (j['openface_capture_count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Home hero + mental health card use a shorter rolling window than reports.
const int kHomeWellnessWindowDays = 3;

/// Report + Mind Balance Index use the same 7-day wellbeing score.
const int kReportWellnessWindowDays = 7;

class EmotionalResilienceDay {
  const EmotionalResilienceDay({
    required this.date,
    required this.dayName,
    required this.emotionLabel,
    required this.resilienceFill,
    required this.samples,
    required this.tone,
  });

  final String date;
  final String dayName;
  final String emotionLabel;
  final double resilienceFill;
  final int samples;
  final String tone;

  factory EmotionalResilienceDay.fromJson(Map<String, dynamic> j) =>
      EmotionalResilienceDay(
        date: (j['date'] ?? '').toString(),
        dayName: (j['day_name'] ?? '').toString(),
        emotionLabel: (j['emotion_label'] ?? '').toString(),
        resilienceFill: (j['resilience_fill'] as num?)?.toDouble() ?? 0,
        samples: (j['samples'] as num?)?.toInt() ?? 0,
        tone: (j['tone'] ?? 'neutral').toString(),
      );
}

class WellnessDashboardData {
  const WellnessDashboardData({
    required this.windowDays,
    required this.hasWellbeingSignal,
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
    required this.emotionalResilienceDays,
    required this.openfaceCaptureCount,
    required this.latestEmotion,
  });

  final int windowDays;
  final bool hasWellbeingSignal;
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
  final List<EmotionalResilienceDay> emotionalResilienceDays;
  final int openfaceCaptureCount;
  final String latestEmotion;

  static const empty = WellnessDashboardData(
    windowDays: 7,
    hasWellbeingSignal: false,
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
    emotionalResilienceDays: [],
    openfaceCaptureCount: 0,
    latestEmotion: '',
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
    final resilience = ((j['emotional_resilience_days'] as List<dynamic>?) ??
            const [])
        .whereType<Map<String, dynamic>>()
        .map(EmotionalResilienceDay.fromJson)
        .toList();
    final openfaceCount = (j['openface_capture_count'] as num?)?.toInt() ??
        mh.openfaceCaptureCount;
    final wellbeingScore = (j['wellbeing_score'] as num?)?.toInt() ?? 0;
    final totalChunks = (j['total_chunks'] as num?)?.toInt() ?? 0;
    final hasSignal = j['has_wellbeing_signal'] == true ||
        wellbeingScore > 0 ||
        mh.hasData ||
        totalChunks > 0;
    return WellnessDashboardData(
      windowDays: (j['window_days'] as num?)?.toInt() ?? 7,
      hasWellbeingSignal: hasSignal,
      wellbeingScore: wellbeingScore,
      mentalHealthScore: (j['mental_health_score'] as num?)?.toInt() ?? 0,
      stressIndicator: (j['stress_indicator'] as num?)?.toInt() ?? 0,
      anxietyIndicator: (j['anxiety_indicator'] as num?)?.toInt() ?? 0,
      depressionIndicator: (j['depression_indicator'] as num?)?.toInt() ?? 0,
      dominantMoodWeek: (j['dominant_mood_week'] ?? 'neutral').toString(),
      moodLast7: mood,
      contentBuckets: buckets,
      totalChunks: totalChunks,
      screenMinutesWeek: (j['screen_minutes_week'] as num?)?.toInt() ?? 0,
      facetSummary: (j['facet_summary'] ?? '').toString(),
      mentalHealth: mh,
      sleepSecondsToday: (j['sleep_seconds_today'] as num?)?.toInt() ?? 0,
      lateNightSecondsToday:
          (j['late_night_seconds_today'] as num?)?.toInt() ?? 0,
      emotionalResilienceDays: resilience,
      openfaceCaptureCount: openfaceCount,
      latestEmotion: (j['latest_emotion'] ?? '').toString().trim(),
    );
  }
}

/// Last-7-days-derived scores for Home / reports (backed by Django).
class WellnessDashboardService {
  WellnessDashboardService._();
  static final WellnessDashboardService instance = WellnessDashboardService._();

  final ValueNotifier<WellnessDashboardData> dashboard =
      ValueNotifier<WellnessDashboardData>(WellnessDashboardData.empty);

  /// Last [kHomeWellnessWindowDays] rolling averages for Home UI.
  final ValueNotifier<WellnessDashboardData> homeDashboard =
      ValueNotifier<WellnessDashboardData>(WellnessDashboardData.empty);

  DateTime? _lastFetch;
  DateTime? _lastHomeFetch;
  bool _inFlight = false;
  bool _homeInFlight = false;
  String? _scopedUserId;

  void resetForNewUser() {
    _lastFetch = null;
    _lastHomeFetch = null;
    _scopedUserId = null;
    _inFlight = false;
    _homeInFlight = false;
    dashboard.value = WellnessDashboardData.empty;
    homeDashboard.value = WellnessDashboardData.empty;
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

  Future<void> refreshHome({bool force = false}) async {
    await _fetchWindow(days: kHomeWellnessWindowDays, force: force, forHome: true);
    if (force) {
      await _fetchWindow(days: kReportWellnessWindowDays, force: true, forHome: false);
    }
  }

  Future<void> refresh({bool force = false, int days = 7}) =>
      _fetchWindow(days: days, force: force, forHome: false);

  Future<void> _fetchWindow({
    required int days,
    required bool force,
    required bool forHome,
  }) async {
    if (forHome) {
      if (_homeInFlight) return;
    } else if (_inFlight) {
      return;
    }
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
    final last = forHome ? _lastHomeFetch : _lastFetch;
    if (!force &&
        last != null &&
        now.difference(last) < const Duration(minutes: 5)) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth.accessToken') ?? '';
    if (token.isEmpty) {
      resetForNewUser();
      return;
    }
    if (forHome) {
      _homeInFlight = true;
    } else {
      _inFlight = true;
    }
    try {
      final decoded = await getJsonWithRetry(
        Uri.parse('${ApiConfig.baseUrl}/api/auth/dashboard/wellness/?days=$days'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      if (forHome) {
        _lastHomeFetch = DateTime.now();
      } else {
        _lastFetch = DateTime.now();
      }
      if (decoded != null) {
        final next = WellnessDashboardData.fromJson(decoded);
        if (forHome) {
          homeDashboard.value = next;
          final reportScore = dashboard.value.wellbeingScore > 0
              ? dashboard.value.wellbeingScore
              : next.wellbeingScore;
          await _persistWellbeingDelta(reportScore);
        } else {
          dashboard.value = next;
        }
      }
    } catch (_) {
      // keep last good payload
    } finally {
      if (forHome) {
        _homeInFlight = false;
      } else {
        _inFlight = false;
      }
    }
  }
}
