import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../utils/resilient_http.dart' show getWithRetry;
import 'plan_access_service.dart';

class RecommendationAction {
  final String type;
  final String label;

  const RecommendationAction({required this.type, required this.label});

  factory RecommendationAction.fromJson(Map<String, dynamic> json) {
    return RecommendationAction(
      type: (json['type'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
    );
  }
}

class RecommendationCard {
  final String title;
  final String description;
  final String category;
  final String priority;
  final RecommendationAction action;

  const RecommendationCard({
    required this.title,
    required this.description,
    required this.category,
    required this.priority,
    required this.action,
  });

  factory RecommendationCard.fromJson(Map<String, dynamic> json) {
    return RecommendationCard(
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      category: (json['category'] ?? '').toString(),
      priority: (json['priority'] ?? 'Low').toString(),
      action: RecommendationAction.fromJson(
        (json['action'] as Map<String, dynamic>? ?? const {}),
      ),
    );
  }
}

class WellnessRecommendationResponse {
  final String riskLevel;
  final List<String> mainIssues;
  final Map<String, List<String>> recommendations;
  final List<RecommendationCard> cards;
  final List<String> summaryLines;
  final String summaryText;
  final bool cached;
  final String source;

  const WellnessRecommendationResponse({
    required this.riskLevel,
    required this.mainIssues,
    required this.recommendations,
    required this.cards,
    required this.summaryLines,
    required this.summaryText,
    required this.cached,
    required this.source,
  });

  static const empty = WellnessRecommendationResponse(
    riskLevel: 'unknown',
    mainIssues: <String>[],
    recommendations: <String, List<String>>{},
    cards: <RecommendationCard>[],
    summaryLines: <String>[],
    summaryText: '',
    cached: false,
    source: '',
  );

  bool get hasSummary => summaryLines.isNotEmpty || summaryText.trim().isNotEmpty;
}

class RecommendationsService {
  RecommendationsService._();
  static final RecommendationsService instance = RecommendationsService._();

  Future<WellnessRecommendationResponse> fetchRecommendations({
    String range = 'week',
    bool forceRefresh = false,
    int timeoutSeconds = 45,
  }) async {
    final allowed = await PlanAccessService.instance.canAccess(
      'personalized_suggestions',
      forceRefresh: true,
    );
    if (!allowed) return WellnessRecommendationResponse.empty;

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth.accessToken') ?? '';
    if (token.isEmpty) return WellnessRecommendationResponse.empty;

    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/api/auth/recommendations/ai/',
    ).replace(
      queryParameters: forceRefresh ? {'refresh': '1'} : null,
    );

    try {
      final response = await getWithRetry(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        timeout: Duration(seconds: timeoutSeconds),
      );
      if (response == null ||
          response.statusCode < 200 ||
          response.statusCode >= 300) {
        return WellnessRecommendationResponse.empty;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return WellnessRecommendationResponse.empty;
      }
      return _fromApiPayload(decoded);
    } catch (_) {
      return WellnessRecommendationResponse.empty;
    }
  }

  WellnessRecommendationResponse _fromApiPayload(Map<String, dynamic> payload) {
    final lines = (payload['lines'] as List<dynamic>? ?? const [])
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final summaryText = (payload['summary_text'] ?? '').toString().trim();
    final risk = (payload['risk_level'] ?? 'unknown').toString().toLowerCase();
    final issues = (payload['main_issues'] as List<dynamic>? ?? const [])
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final effectiveLines = lines.isNotEmpty
        ? lines
        : summaryText
            .split(RegExp(r'\n\s*\n'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();

    final cards = _cardsFromSummaryLines(
      lines: effectiveLines,
      riskLevel: risk,
    );

    return WellnessRecommendationResponse(
      riskLevel: risk,
      mainIssues: issues,
      recommendations: const {},
      cards: cards,
      summaryLines: effectiveLines,
      summaryText: summaryText.isNotEmpty
          ? summaryText
          : effectiveLines.join('\n\n'),
      cached: payload['cached'] == true,
      source: (payload['source'] ?? '').toString(),
    );
  }

  List<RecommendationCard> _cardsFromSummaryLines({
    required List<String> lines,
    required String riskLevel,
  }) {
    if (lines.isEmpty) return const [];
    final priority = switch (riskLevel) {
      'high' => 'High',
      'moderate' => 'Medium',
      _ => 'Low',
    };
    return [
      RecommendationCard(
        title: 'Your AI wellness plan',
        description: lines.join(' '),
        category: 'Personalized',
        priority: priority,
        action: const RecommendationAction(
          type: 'generic',
          label: 'Review tips',
        ),
      ),
    ];
  }
}
