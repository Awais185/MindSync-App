import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'analytics_data_service.dart';
import '../config/api_config.dart';
import 'plan_access_service.dart';
import 'screen_time_service.dart';

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

  const WellnessRecommendationResponse({
    required this.riskLevel,
    required this.mainIssues,
    required this.recommendations,
    required this.cards,
  });

  static const empty = WellnessRecommendationResponse(
    riskLevel: 'unknown',
    mainIssues: <String>[],
    recommendations: <String, List<String>>{},
    cards: <RecommendationCard>[],
  );
}

class RecommendationsService {
  RecommendationsService._();
  static final RecommendationsService instance = RecommendationsService._();

  Future<WellnessRecommendationResponse> fetchRecommendations({
    String range = 'week',
    int timeoutSeconds = 20,
  }) async {
    final allowed = await PlanAccessService.instance.canAccess(
      'personalized_suggestions',
      forceRefresh: true,
    );
    if (!allowed) return WellnessRecommendationResponse.empty;

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth.accessToken') ?? '';
    if (token.isEmpty) return WellnessRecommendationResponse.empty;

    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };

    try {
      final analytics = await AnalyticsDataService.instance.fetch(range);
      final snapshot = ScreenTimeService.instance.snapshot.value;
      final payload = _privacySafeBehaviorPayload(
        analytics: analytics,
        snapshot: snapshot,
      );
      final prompt = _buildRecommendationPrompt(payload);

      final response = await http
          .post(
            ApiConfig.uri('/api/chat/'),
            headers: headers,
            body: jsonEncode({
              'message': prompt,
              'history': const <Map<String, String>>[],
            }),
          )
          .timeout(Duration(seconds: timeoutSeconds));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return WellnessRecommendationResponse.empty;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return WellnessRecommendationResponse.empty;
      }
      final reply = (decoded['reply'] ?? '').toString();
      return _parseLlmResponse(reply);
    } catch (_) {
      return WellnessRecommendationResponse.empty;
    }
  }

  String _buildRecommendationPrompt(Map<String, dynamic> data) {
    return '''
You are a mental wellness recommendation engine.
Analyze the behavioral JSON and return only a valid JSON object with this exact schema:
{
  "risk_level": "low|moderate|high",
  "main_issues": ["issue 1", "issue 2"],
  "recommendations": {
    "physical_activity": ["..."],
    "sleep": ["..."],
    "mental_health": ["..."],
    "social_life": ["..."],
    "digital_detox": ["..."],
    "productivity": ["..."],
    "hobbies_balance": ["..."],
    "professional_help": ["..."]
  }
}
Rules:
- Do not ask follow-up questions.
- Keep recommendations actionable and concise.
- Include professional_help only when risk is high or symptoms are severe/persistent.
- Return JSON only, no markdown.
Behavioral data:
${jsonEncode(data)}
''';
  }

  Map<String, dynamic> _privacySafeBehaviorPayload({
    required AnalyticsPayload analytics,
    required ScreenTimeSnapshot snapshot,
  }) {
    final screenHours = snapshot.daySeconds / 3600;
    final socialHours = snapshot.socialSeconds / 3600;
    final moods = analytics.moodFrequency
        .map((entry) => (entry['mood'] ?? '').toString().trim().toLowerCase())
        .where((m) => m.isNotEmpty)
        .toList();
    final topCategories = analytics.topCategories
        .map((entry) => (entry['category'] ?? '').toString().trim())
        .where((c) => c.isNotEmpty)
        .take(4)
        .toList();
    final stressScore = (100 - analytics.verificationRatePercent)
        .clamp(0, 100)
        .toInt();
    final sleepHoursEstimate = (8 - (screenHours / 2)).clamp(3, 9).toDouble();

    final raw = <String, dynamic>{
      'screen_time_hours': double.parse(screenHours.toStringAsFixed(1)),
      'social_media_usage_hours': double.parse(socialHours.toStringAsFixed(1)),
      'content_consumption_type': topCategories,
      'sleep_hours': double.parse(sleepHoursEstimate.toStringAsFixed(1)),
      'physical_activity_level': _estimatePhysicalActivity(screenHours),
      'emotion_analysis': {
        'stress_score': stressScore,
        'anxiety_score': _estimateAnxietyScore(moods),
        'depression_score': _estimateDepressionScore(moods),
        'sadness_level': _containsAny(moods, const ['sad', 'stressed', 'anxious'])
            ? 'high'
            : 'low',
        'anger_level': _containsAny(moods, const ['angry']) ? 'high' : 'low',
        'happiness_level':
            _containsAny(moods, const ['happy', 'calm']) ? 'high' : 'low',
      },
      'facial_analysis': {
        'eye_contact': analytics.verificationRatePercent < 60 ? 'low' : 'normal',
        'fatigue_detected': sleepHoursEstimate < 6,
        'stress_expression_detected': stressScore > 70,
      },
      'behavior_patterns': {
        'late_night_phone_usage': screenHours > 7,
        'isolation_behavior': _containsAny(
          topCategories.map((c) => c.toLowerCase()).toList(),
          const ['gaming', 'negative'],
        ),
        'irregular_sleep_schedule': sleepHoursEstimate < 6.5,
        'gaming_addiction_signs': _containsAny(
          topCategories.map((c) => c.toLowerCase()).toList(),
          const ['gaming'],
        ),
        'doom_scrolling_behavior': screenHours > 8 || socialHours > 4,
      },
      'weekly_mood_logs': moods.take(7).toList(),
    };

    return _stripPii(raw);
  }

  Map<String, dynamic> _stripPii(Map<String, dynamic> input) {
    const piiKeys = <String>{
      'name',
      'email',
      'phone',
      'address',
      'location',
      'password',
      'message',
      'private_message',
    };

    dynamic sanitize(dynamic value) {
      if (value is Map) {
        final result = <String, dynamic>{};
        value.forEach((k, v) {
          final key = k.toString();
          final normalized = key.toLowerCase().replaceAll('_', '');
          if (piiKeys.any((pii) => normalized.contains(pii))) {
            return;
          }
          result[key] = sanitize(v);
        });
        return result;
      }
      if (value is List) {
        return value.map(sanitize).toList();
      }
      return value;
    }

    return (sanitize(input) as Map<String, dynamic>);
  }

  WellnessRecommendationResponse _parseLlmResponse(String reply) {
    final payload = _extractJson(reply);
    if (payload == null) return WellnessRecommendationResponse.empty;

    final risk = (payload['risk_level'] ?? 'unknown').toString().toLowerCase();
    final issues = (payload['main_issues'] as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .where((e) => e.trim().isNotEmpty)
        .toList();

    final recsRaw = payload['recommendations'];
    final normalized = <String, List<String>>{};
    if (recsRaw is Map<String, dynamic>) {
      recsRaw.forEach((key, value) {
        final list = (value as List<dynamic>? ?? const [])
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
        if (list.isNotEmpty) normalized[key] = list;
      });
    }

    final cards = _cardsFromStructuredRecommendations(
      riskLevel: risk,
      recommendations: normalized,
    );
    return WellnessRecommendationResponse(
      riskLevel: risk,
      mainIssues: issues,
      recommendations: normalized,
      cards: cards,
    );
  }

  Map<String, dynamic>? _extractJson(String text) {
    final direct = _tryDecodeJson(text);
    if (direct != null) return direct;
    final match = RegExp(r'\{[\s\S]*\}').firstMatch(text);
    if (match == null) return null;
    return _tryDecodeJson(match.group(0) ?? '');
  }

  Map<String, dynamic>? _tryDecodeJson(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }

  List<RecommendationCard> _cardsFromStructuredRecommendations({
    required String riskLevel,
    required Map<String, List<String>> recommendations,
  }) {
    final cards = <RecommendationCard>[];
    recommendations.forEach((category, items) {
      if (items.isEmpty) return;
      cards.add(
        RecommendationCard(
          title: _titleForCategory(category),
          description: items.join(' '),
          category: _prettyCategory(category),
          priority: _priorityForCategory(riskLevel, category),
          action: RecommendationAction(
            type: _actionTypeForCategory(category),
            label: _actionLabelForCategory(category),
          ),
        ),
      );
    });
    return cards;
  }

  String _estimatePhysicalActivity(double screenHours) {
    if (screenHours >= 8) return 'low';
    if (screenHours >= 5) return 'moderate';
    return 'high';
  }

  int _estimateAnxietyScore(List<String> moods) {
    if (_containsAny(moods, const ['anxious', 'stressed'])) return 75;
    if (_containsAny(moods, const ['tired', 'sad'])) return 55;
    return 35;
  }

  int _estimateDepressionScore(List<String> moods) {
    if (_containsAny(moods, const ['sad', 'empty', 'hopeless'])) return 70;
    if (_containsAny(moods, const ['tired', 'anxious'])) return 50;
    return 30;
  }

  bool _containsAny(List<String> values, List<String> probes) {
    for (final value in values) {
      for (final probe in probes) {
        if (value.contains(probe)) return true;
      }
    }
    return false;
  }

  String _prettyCategory(String category) {
    return category
        .replaceAll('_', ' ')
        .split(' ')
        .where((s) => s.isNotEmpty)
        .map((s) => s[0].toUpperCase() + s.substring(1))
        .join(' ');
  }

  String _titleForCategory(String category) {
    return switch (category) {
      'physical_activity' => 'Move to Reset Your Mood',
      'sleep' => 'Sleep Recovery Plan',
      'mental_health' => 'Mind Calm Routine',
      'social_life' => 'Social Reconnection',
      'digital_detox' => 'Digital Detox Routine',
      'productivity' => 'Focus and Productivity',
      'hobbies_balance' => 'Healthy Hobbies Balance',
      'professional_help' => 'Professional Support',
      _ => _prettyCategory(category),
    };
  }

  String _actionTypeForCategory(String category) {
    return switch (category) {
      'sleep' => 'digital_detox',
      'mental_health' => 'breathing_exercise',
      'digital_detox' => 'set_app_limits',
      'professional_help' => 'contact_support',
      _ => 'generic',
    };
  }

  String _actionLabelForCategory(String category) {
    return switch (category) {
      'sleep' => 'Start Sleep Reset',
      'mental_health' => 'Start Calm Exercise',
      'digital_detox' => 'Set App Limits',
      'professional_help' => 'Find Help Options',
      _ => 'Use This Tip',
    };
  }

  String _priorityForCategory(String riskLevel, String category) {
    if (riskLevel == 'high' &&
        (category == 'professional_help' ||
            category == 'sleep' ||
            category == 'mental_health')) {
      return 'High';
    }
    if (riskLevel == 'moderate') return 'Medium';
    return 'Low';
  }
}
