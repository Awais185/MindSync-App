import '../services/subscription_service.dart';

class PlanModel {
  final String id;
  final String displayName;
  final int price;
  final String currency;
  final int durationDays;
  final List<String> features;
  final int? planDbId;

  const PlanModel({
    required this.id,
    required this.displayName,
    required this.price,
    required this.currency,
    required this.durationDays,
    required this.features,
    this.planDbId,
  });

  double get priceUsd => price / 100.0;

  String get priceLabel => '\$${priceUsd.toStringAsFixed(priceUsd.truncateToDouble() == priceUsd ? 0 : 2)}';

  factory PlanModel.fromJson(Map<String, dynamic> json) {
    return PlanModel(
      id: (json['id'] ?? '').toString(),
      displayName: (json['display_name'] ?? json['name'] ?? '').toString(),
      price: (json['price'] as num?)?.toInt() ?? 0,
      currency: (json['currency'] ?? 'usd').toString(),
      durationDays: (json['duration_days'] as num?)?.toInt() ?? 30,
      features: (json['features'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      planDbId: (json['plan_db_id'] as num?)?.toInt(),
    );
  }

  factory PlanModel.fromSubscriptionPlan(SubscriptionPlanModel plan) {
    final cents = (plan.priceUsd * 100).round();
    return PlanModel(
      id: plan.code.toLowerCase(),
      displayName: plan.name,
      price: cents,
      currency: 'usd',
      durationDays: 30,
      features: plan.features,
      planDbId: plan.id,
    );
  }
}
