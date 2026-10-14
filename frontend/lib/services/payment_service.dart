import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../models/plan_model.dart';
import '../models/subscription_model.dart';

class PaymentIntentResult {
  const PaymentIntentResult({
    required this.clientSecret,
    required this.publishableKey,
    required this.paymentIntentId,
    required this.plan,
  });

  final String clientSecret;
  final String publishableKey;
  final String paymentIntentId;
  final PlanModel plan;
}

class PaymentService {
  PaymentService._();
  static final PaymentService instance = PaymentService._();

  Future<Map<String, String>?> _authHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth.accessToken') ?? '';
    if (token.isEmpty) return null;
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  Future<List<PlanModel>> fetchPlans() async {
    final res = await http
        .get(Uri.parse('${ApiConfig.baseUrl}/api/payments/plans/'))
        .timeout(const Duration(seconds: 20));
    if (res.statusCode < 200 || res.statusCode >= 300) return const [];
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) return const [];
    return (decoded['plans'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(PlanModel.fromJson)
        .toList();
  }

  Future<PaymentIntentResult?> createPaymentIntent(String planId) async {
    final headers = await _authHeaders();
    if (headers == null) return null;
    final res = await http
        .post(
          Uri.parse('${ApiConfig.baseUrl}/api/payments/create-payment-intent/'),
          headers: headers,
          body: jsonEncode({'plan_id': planId}),
        )
        .timeout(const Duration(seconds: 25));
    if (res.statusCode < 200 || res.statusCode >= 300) return null;
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) return null;
    final planJson = decoded['plan'] as Map<String, dynamic>? ?? const {};
    return PaymentIntentResult(
      clientSecret: (decoded['client_secret'] ?? '').toString(),
      publishableKey: (decoded['publishable_key'] ?? '').toString(),
      paymentIntentId: (decoded['payment_intent_id'] ?? '').toString(),
      plan: PlanModel.fromJson(planJson),
    );
  }

  Future<SubscriptionModel?> confirmSubscription({
    required String paymentIntentId,
    required String planId,
  }) async {
    final headers = await _authHeaders();
    if (headers == null) return null;
    final res = await http
        .post(
          Uri.parse('${ApiConfig.baseUrl}/api/payments/confirm-subscription/'),
          headers: headers,
          body: jsonEncode({
            'payment_intent_id': paymentIntentId,
            'plan_id': planId,
          }),
        )
        .timeout(const Duration(seconds: 25));
    if (res.statusCode < 200 || res.statusCode >= 300) return null;
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) return null;
    final sub = decoded['subscription'] as Map<String, dynamic>?;
    if (sub == null) return null;
    return SubscriptionModel.fromJson(sub);
  }

  Future<List<Map<String, dynamic>>> fetchPaymentHistory() async {
    final headers = await _authHeaders();
    if (headers == null) return const [];
    final res = await http
        .get(
          Uri.parse('${ApiConfig.baseUrl}/api/payments/history/'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode < 200 || res.statusCode >= 300) return const [];
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) return const [];
    return (decoded['results'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
  }
}
