import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../utils/resilient_http.dart';
import '../widgets/behavioral_insights_modules.dart';

class AnalyticsPayload {
  const AnalyticsPayload({
    required this.topCategories,
    required this.moodFrequency,
    required this.dominantMood,
    required this.verificationRatePercent,
    required this.topContentDaily,
    required this.dominantMoodDaily,
    required this.stressDaily,
    this.totalAnalyzedChunks = 0,
    this.hasCategoryData = false,
    this.topCategoryName,
    this.topCategoryPercent = 0,
    this.contentPreferenceTop3 = const [],
    this.contentPreferenceHasData = false,
    this.behaviourInsightMessage = '',
    this.behaviourInsightHasData = false,
    this.behaviourStudy = BehaviourStudyData.empty,
    this.facialExpressionStudy = FacialExpressionStudyData.empty,
    this.contentTypeAnalysis = ContentTypeAnalysisData.empty,
  });

  final List<Map<String, dynamic>> topCategories;
  final List<Map<String, dynamic>> moodFrequency;
  final String dominantMood;
  final double verificationRatePercent;
  final List<Map<String, dynamic>> topContentDaily;
  final List<Map<String, dynamic>> dominantMoodDaily;
  final List<Map<String, dynamic>> stressDaily;
  final int totalAnalyzedChunks;
  final bool hasCategoryData;
  final String? topCategoryName;
  final double topCategoryPercent;
  final List<Map<String, dynamic>> contentPreferenceTop3;
  final bool contentPreferenceHasData;
  final String behaviourInsightMessage;
  final bool behaviourInsightHasData;
  final BehaviourStudyData behaviourStudy;
  final FacialExpressionStudyData facialExpressionStudy;
  final ContentTypeAnalysisData contentTypeAnalysis;
}

class AnalyticsDataService {
  AnalyticsDataService._();
  static final AnalyticsDataService instance = AnalyticsDataService._();

  Future<AnalyticsPayload> fetch(String selected) async {
    const empty = AnalyticsPayload(
      topCategories: [],
      moodFrequency: [],
      dominantMood: 'neutral',
      verificationRatePercent: 0,
      topContentDaily: [],
      dominantMoodDaily: [],
      stressDaily: [],
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth.accessToken') ?? '';
      if (token.isEmpty) {
        return empty;
      }

      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

      final behavioral = await getJsonWithRetry(
        Uri.parse('${ApiConfig.baseUrl}/api/analytics/behavioral/?range=$selected'),
        headers: headers,
      );
      final verification = await getJsonWithRetry(
        Uri.parse(
          '${ApiConfig.baseUrl}/api/face-verification/analytics/?range=$selected',
        ),
        headers: headers,
      );

      final themedRows =
          (behavioral?['theme_content_categories'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(
                (row) => {
                  'category': (row['category'] ?? row['label'] ?? 'other').toString(),
                  'count': (row['count'] as num?)?.toDouble() ?? 0.0,
                  'percent': (row['percent'] as num?)?.toDouble() ?? 0.0,
                },
              )
              .toList();

      final sessionRaw = behavioral?['category_session'];
      final sessionCategories =
          (sessionRaw is Map<String, dynamic>
                  ? sessionRaw['categories']
                  : null) as List<dynamic>? ??
              const [];
      final categoryRows = sessionCategories
          .whereType<Map<String, dynamic>>()
          .map(
            (row) => {
              'category': (row['category'] ?? 'Other').toString(),
              'count': (row['count'] as num?)?.toInt() ?? 0,
              'percent': (row['percent'] as num?)?.toDouble() ?? 0.0,
            },
          )
          .toList();

      final legacyCats =
          (behavioral?['top_content_categories'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .toList();

      final resolvedCategories = categoryRows.isNotEmpty
          ? categoryRows
          : (legacyCats.isNotEmpty ? legacyCats : themedRows);

      final hasCategoryData = sessionRaw is Map<String, dynamic>
          ? (sessionRaw['has_data'] as bool?) ?? categoryRows.isNotEmpty
          : categoryRows.isNotEmpty;

      final contentPrefRaw = behavioral?['content_preference'];
      final contentPrefItems =
          (contentPrefRaw is Map<String, dynamic>
                  ? contentPrefRaw['items']
                  : null) as List<dynamic>? ??
              const [];
      final contentPreferenceTop3 = contentPrefItems
          .whereType<Map<String, dynamic>>()
          .map(
            (row) => {
              'category': (row['category'] ?? row['label'] ?? 'Other').toString(),
              'count': (row['count'] as num?)?.toInt() ?? 0,
              'percent': (row['percent'] as num?)?.toDouble() ?? 0.0,
            },
          )
          .take(3)
          .toList();
      final contentPreferenceHasData = contentPrefRaw is Map<String, dynamic>
          ? (contentPrefRaw['has_data'] as bool?) ??
              contentPreferenceTop3.isNotEmpty
          : contentPreferenceTop3.isNotEmpty;

      final behaviourRaw = behavioral?['behaviour_insight'];
      final behaviourInsightMessage = behaviourRaw is Map<String, dynamic>
          ? (behaviourRaw['message'] as String? ?? '')
          : '';
      final behaviourInsightHasData = behaviourRaw is Map<String, dynamic>
          ? (behaviourRaw['has_data'] as bool?) ?? false
          : false;

      return AnalyticsPayload(
        topCategories: resolvedCategories,
        moodFrequency:
            (behavioral?['mood_frequency'] as List<dynamic>? ?? const [])
                .whereType<Map<String, dynamic>>()
                .toList(),
        dominantMood: (behavioral?['dominant_mood'] as String? ?? 'neutral'),
        verificationRatePercent:
            (verification?['verification_rate_percent'] as num?)?.toDouble() ?? 0,
        topContentDaily:
            (behavioral?['top_content_daily'] as List<dynamic>? ?? const [])
                .whereType<Map<String, dynamic>>()
                .toList(),
        dominantMoodDaily:
            (behavioral?['dominant_mood_daily'] as List<dynamic>? ?? const [])
                .whereType<Map<String, dynamic>>()
                .toList(),
        stressDaily:
            (verification?['daily_verification'] as List<dynamic>? ?? const [])
                .whereType<Map<String, dynamic>>()
                .toList(),
        totalAnalyzedChunks:
            (behavioral?['total_analyzed_chunks'] as num?)?.toInt() ??
            (sessionRaw is Map<String, dynamic>
                ? (sessionRaw['total_chunks'] as num?)?.toInt()
                : null) ??
            0,
        hasCategoryData: hasCategoryData,
        topCategoryName: sessionRaw is Map<String, dynamic>
            ? sessionRaw['top_category']?.toString()
            : (resolvedCategories.isNotEmpty
                ? resolvedCategories.first['category']?.toString()
                : null),
        topCategoryPercent: sessionRaw is Map<String, dynamic>
            ? (sessionRaw['top_category_percent'] as num?)?.toDouble() ?? 0
            : (resolvedCategories.isNotEmpty
                ? (resolvedCategories.first['percent'] as num?)?.toDouble() ?? 0
                : 0),
        contentPreferenceTop3: contentPreferenceTop3,
        contentPreferenceHasData: contentPreferenceHasData,
        behaviourInsightMessage: behaviourInsightMessage,
        behaviourInsightHasData: behaviourInsightHasData,
        behaviourStudy: BehaviourStudyData.fromJson(
          behavioral?['behaviour_study'] as Map<String, dynamic>?,
        ),
        facialExpressionStudy: FacialExpressionStudyData.fromJson(
          behavioral?['facial_expression_study'] as Map<String, dynamic>?,
        ),
        contentTypeAnalysis: ContentTypeAnalysisData.fromJson(
          behavioral?['content_type_analysis'] as Map<String, dynamic>?,
        ),
      );
    } catch (_) {
      return empty;
    }
  }
}
