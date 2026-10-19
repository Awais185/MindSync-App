import '../services/subscription_service.dart';

/// Public pricing page — subscriptions are purchased on the web, not in-app.
const String mindSyncPricingUrl = 'https://mindsyncai.vercel.app/pricing';

/// Built-in plans so the upgrade screen works without the API.
abstract final class UpgradePlanCatalog {
  static List<SubscriptionPlanModel> bundledPlans() => const [
        SubscriptionPlanModel(
          id: 0,
          name: 'Free',
          code: 'free',
          priceUsd: 0,
          billingCycle: 'monthly',
          features: [
            'basic_mood_tracking',
            'screen_time',
          ],
          isActive: true,
        ),
        SubscriptionPlanModel(
          id: 1,
          name: 'Basic',
          code: 'basic',
          priceUsd: 3,
          billingCycle: 'monthly',
          features: [
            'emotion_detection_limited',
            'basic_mood_tracking',
            'screen_time',
            'chat_realtime_psychologist',
            'content_monitoring',
            'analytics_day_week_month',
            'ads_included',
          ],
          isActive: true,
        ),
        SubscriptionPlanModel(
          id: 2,
          name: 'Premium',
          code: 'premium',
          priceUsd: 6,
          billingCycle: 'monthly',
          features: [
            'emotion_detection_full',
            'mental_health_insights',
            'weekly_reports',
            'no_ads',
            'personalized_suggestions',
            'chat_digital_psychologist',
            'advanced_ai_insights',
            'parental_control',
            'priority_support',
            'full_app_access',
          ],
          isActive: true,
        ),
      ];

  static SubscriptionPlanModel freePlan() => bundledPlans().first;

  static List<SubscriptionPlanModel> mergeWithRemote(
    List<SubscriptionPlanModel> remote,
  ) {
    final bundled = bundledPlans();
    if (remote.isEmpty) return bundled;

    final byCode = <String, SubscriptionPlanModel>{
      for (final p in bundled) p.code.toLowerCase(): p,
    };
    for (final p in remote) {
      final code = p.code.toLowerCase();
      if (!{'free', 'basic', 'premium'}.contains(code)) continue;
      byCode[code] = p;
    }
    const order = ['free', 'basic', 'premium'];
    return order
        .map((c) => byCode[c])
        .whereType<SubscriptionPlanModel>()
        .toList();
  }

  static CurrentSubscriptionModel offlineFreeSubscription() {
    final free = freePlan();
    return CurrentSubscriptionModel(
      effectivePlanCode: 'free',
      status: 'inactive',
      startDate: null,
      endDate: null,
      autoRenew: false,
      isActive: false,
      plan: free,
    );
  }
}
