class SubscriptionModel {
  final String planName;
  final String planDisplayName;
  final int amountPaid;
  final String currency;
  final String status;
  final DateTime? startedAt;
  final DateTime? expiresAt;
  final bool isActive;

  const SubscriptionModel({
    required this.planName,
    required this.planDisplayName,
    required this.amountPaid,
    required this.currency,
    required this.status,
    required this.startedAt,
    required this.expiresAt,
    required this.isActive,
  });

  bool get isExpired =>
      !isActive &&
      (status == 'expired' || status == 'cancelled');

  factory SubscriptionModel.fromJson(Map<String, dynamic> json) {
    return SubscriptionModel(
      planName: (json['plan_name'] ?? '').toString(),
      planDisplayName: (json['plan_display_name'] ?? '').toString(),
      amountPaid: (json['amount_paid'] as num?)?.toInt() ?? 0,
      currency: (json['currency'] ?? 'usd').toString(),
      status: (json['status'] ?? '').toString(),
      startedAt: DateTime.tryParse((json['started_at'] ?? '').toString()),
      expiresAt: DateTime.tryParse((json['expires_at'] ?? '').toString()),
      isActive: (json['is_active'] as bool?) ?? false,
    );
  }
}
