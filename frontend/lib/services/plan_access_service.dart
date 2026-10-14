import 'subscription_service.dart';

class PlanAccessService {
  PlanAccessService._();
  static final PlanAccessService instance = PlanAccessService._();

  CurrentSubscriptionModel? _cached;
  DateTime? _lastFetchedAt;
  static const Duration _cacheTtl = Duration(seconds: 20);

  bool get _isCacheFresh {
    if (_cached == null || _lastFetchedAt == null) return false;
    return DateTime.now().difference(_lastFetchedAt!) <= _cacheTtl;
  }

  Future<String> currentPlanCode() async {
    try {
      if (!_isCacheFresh) {
        _cached = await SubscriptionService.instance.getCurrentSubscription();
        _lastFetchedAt = DateTime.now();
      }
      return (_cached?.effectivePlanCode ?? 'free').toLowerCase();
    } catch (_) {
      return 'free';
    }
  }

  Future<void> refresh({bool force = false}) async {
    try {
      _cached = await SubscriptionService.instance.getCurrentSubscription(
        forceRefresh: force || !_isCacheFresh,
      );
      _lastFetchedAt = DateTime.now();
    } catch (_) {
      _cached = null;
      _lastFetchedAt = null;
    }
  }

  void invalidate() {
    _cached = null;
    _lastFetchedAt = null;
  }

  Future<bool> canAccessMentalHealthInsights({bool forceRefresh = false}) async {
    if (forceRefresh) {
      await refresh();
    }
    final code = await currentPlanCode();
    return code == 'basic' || code == 'premium';
  }

  Future<bool> canAccess(String featureKey, {bool forceRefresh = false}) async {
    if (forceRefresh) {
      await refresh();
    }
    final code = await currentPlanCode();
    final allowed = _featuresByPlan[code] ?? _featuresByPlan['free']!;
    return allowed.contains(featureKey);
  }

  static const Map<String, Set<String>> _featuresByPlan = {
    'free': {
      'basic_mood_tracking',
      'screen_time',
    },
    'basic': {
      'emotion_detection_limited',
      'mental_health_insights',
      'basic_mood_tracking',
      'screen_time',
      'content_monitoring',
      'analytics_day_week_month',
      'chat_realtime_psychologist',
      'ads_included',
    },
    'premium': {
      'emotion_detection_limited',
      'emotion_detection_full',
      'mental_health_insights',
      'basic_mood_tracking',
      'screen_time',
      'content_monitoring',
      'analytics_day_week_month',
      'chat_realtime_psychologist',
      'ads_included',
      'weekly_reports',
      'no_ads',
      'personalized_suggestions',
      'chat_digital_psychologist',
      'mental_health_monitoring',
      'advanced_ai_insights',
      'monthly_mental_health_reports',
      'therapist_recommendation',
      'priority_support',
      'parental_control',
      'full_app_access',
    },
    'doctor': {
      'full_app_access',
      'doctor_patient_inbox',
      'doctor_appointments',
      'doctor_patient_assist',
      'mental_health_monitoring',
      'weekly_reports',
      'advanced_ai_insights',
      'priority_support',
      'no_ads',
      'screen_time',
      'content_monitoring',
      'analytics_day_week_month',
    },
  };
}
