import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import 'plan_access_service.dart';

class SubscriptionPlanModel {
  final int id;
  final String name;
  final String code;
  final double priceUsd;
  final String billingCycle;
  final List<String> features;
  final bool isActive;

  const SubscriptionPlanModel({
    required this.id,
    required this.name,
    required this.code,
    required this.priceUsd,
    required this.billingCycle,
    required this.features,
    required this.isActive,
  });

  bool get isFree => code.toLowerCase() == 'free' || priceUsd <= 0;

  factory SubscriptionPlanModel.fromJson(Map<String, dynamic> json) {
    return SubscriptionPlanModel(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] ?? '').toString(),
      code: (json['code'] ?? '').toString(),
      priceUsd: double.tryParse((json['price_usd'] ?? '0').toString()) ?? 0,
      billingCycle: (json['billing_cycle'] ?? 'monthly').toString(),
      features: (json['features'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      isActive: (json['is_active'] as bool?) ?? true,
    );
  }
}

class CurrentSubscriptionModel {
  final String effectivePlanCode;
  final String status;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool autoRenew;
  final bool isActive;
  final SubscriptionPlanModel plan;

  const CurrentSubscriptionModel({
    required this.effectivePlanCode,
    required this.status,
    required this.startDate,
    required this.endDate,
    required this.autoRenew,
    required this.isActive,
    required this.plan,
  });

  factory CurrentSubscriptionModel.fromJson(Map<String, dynamic> json) {
    final planJson = (json['plan'] as Map<String, dynamic>? ?? const {});
    final subscription = (json['subscription'] as Map<String, dynamic>? ?? const {});
    return CurrentSubscriptionModel(
      effectivePlanCode: (json['effective_plan_code'] ?? 'free').toString(),
      status: (json['status'] ?? subscription['status'] ?? 'inactive').toString(),
      startDate: DateTime.tryParse((subscription['start_date'] ?? '').toString()),
      endDate: DateTime.tryParse(
        (json['end_date'] ?? subscription['end_date'] ?? '').toString(),
      ),
      autoRenew: (subscription['auto_renew'] as bool?) ?? false,
      isActive: (json['is_active'] as bool?) ?? false,
      plan: SubscriptionPlanModel.fromJson(planJson),
    );
  }
}

class ManualPaymentCreateResult {
  const ManualPaymentCreateResult({
    required this.paymentId,
    required this.message,
    required this.bankDetails,
  });

  final int paymentId;
  final String message;
  final Map<String, dynamic> bankDetails;
}

class SubscribeResult {
  final String message;
  final String paymentIntentId;
  final String clientSecret;
  final Map<String, dynamic> orderSummary;

  const SubscribeResult({
    required this.message,
    required this.paymentIntentId,
    required this.clientSecret,
    required this.orderSummary,
  });

  factory SubscribeResult.fromJson(Map<String, dynamic> json) {
    return SubscribeResult(
      message: (json['message'] ?? '').toString(),
      paymentIntentId: (json['payment_intent_id'] ?? '').toString(),
      clientSecret: (json['client_secret'] ?? '').toString(),
      orderSummary: (json['order_summary'] as Map<String, dynamic>? ?? const {}),
    );
  }
}

class SubscriptionService {
  SubscriptionService._();
  static final SubscriptionService instance = SubscriptionService._();

  Future<Map<String, String>?> _authHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth.accessToken') ?? '';
    if (token.isEmpty) return null;
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  Future<List<SubscriptionPlanModel>> getPlans() async {
    final headers = await _authHeaders();
    if (headers == null) return const [];
    final res = await http
        .get(Uri.parse('${ApiConfig.baseUrl}/api/plans/'), headers: headers)
        .timeout(const Duration(seconds: 20));
    if (res.statusCode < 200 || res.statusCode >= 300) return const [];
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) return const [];
    return (decoded['plans'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(SubscriptionPlanModel.fromJson)
        .toList();
  }

  CurrentSubscriptionModel? _cachedCurrent;
  String? _cachedUserId;

  static String _diskCacheKey(String uid) => 'subscription.raw.$uid';

  Future<void> hydrateFromCache() async {
    final uid = await _currentUserId();
    if (uid == null) {
      clearForNewUser();
      return;
    }
    if (_cachedCurrent != null && _cachedUserId == uid) return;
    await _hydrateFromDisk(uid);
  }

  Future<void> _hydrateFromDisk(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_diskCacheKey(uid));
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      _cachedCurrent = CurrentSubscriptionModel.fromJson(decoded);
      _cachedUserId = uid;
      subscription.value = _cachedCurrent;
    } catch (_) {
      // Ignore corrupt cache.
    }
  }

  Future<void> _persistRawCache(String uid, String body) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_diskCacheKey(uid), body);
    } catch (_) {
      // Ignore persistence failures.
    }
  }

  final ValueNotifier<CurrentSubscriptionModel?> subscription =
      ValueNotifier<CurrentSubscriptionModel?>(null);

  CurrentSubscriptionModel? get cachedCurrent => _cachedCurrent;

  void clearForNewUser() {
    _cachedCurrent = null;
    _cachedUserId = null;
    subscription.value = null;
  }

  Future<String?> _currentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('auth.userId') ?? prefs.getString('user_id') ?? '';
    if (uid.isEmpty) return null;
    return uid;
  }

  Future<CurrentSubscriptionModel?> getCurrentSubscription({bool forceRefresh = false}) async {
    final uid = await _currentUserId();
    if (uid == null) {
      clearForNewUser();
      return null;
    }
    if (_cachedUserId != uid || _cachedCurrent == null) {
      await _hydrateFromDisk(uid);
    }
    if (!forceRefresh &&
        _cachedCurrent != null &&
        _cachedUserId != null &&
        _cachedUserId == uid) {
      return _cachedCurrent;
    }
    _cachedUserId = uid;
    final headers = await _authHeaders();
    if (headers == null) {
      clearForNewUser();
      return null;
    }
    for (final path in [
      '/api/subscription/current/',
      '/api/current-subscription/',
    ]) {
      try {
        final res = await http
            .get(Uri.parse('${ApiConfig.baseUrl}$path'), headers: headers)
            .timeout(const Duration(seconds: 20));
        if (res.statusCode >= 200 && res.statusCode < 300) {
          final decoded = jsonDecode(res.body);
          if (decoded is Map<String, dynamic>) {
            _cachedCurrent = CurrentSubscriptionModel.fromJson(decoded);
            _cachedUserId = uid;
            subscription.value = _cachedCurrent;
            unawaited(_persistRawCache(uid, res.body));
            return _cachedCurrent;
          }
        }
      } catch (_) {
        // Backend offline / adb reverse missing — keep last cached subscription.
        break;
      }
    }
    if (_cachedCurrent != null) {
      subscription.value = _cachedCurrent;
      return _cachedCurrent;
    }
    subscription.value = null;
    return null;
  }

  Future<void> refreshCurrentSubscription() async {
    await getCurrentSubscription(forceRefresh: true);
    PlanAccessService.instance.invalidate();
    await PlanAccessService.instance.refresh(force: true);
  }

  Future<Map<String, dynamic>> getBankDetails() async {
    final headers = await _authHeaders();
    if (headers == null) return const {};
    final res = await http
        .get(
          Uri.parse('${ApiConfig.baseUrl}/api/payments/bank-details/'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode < 200 || res.statusCode >= 300) return const {};
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) return const {};
    return Map<String, dynamic>.from(
      decoded['bank_details'] as Map<String, dynamic>? ?? const {},
    );
  }

  Future<ManualPaymentCreateResult?> createManualPayment({
    required int planId,
    String paymentMethod = 'bank_transfer',
    String transactionReference = '',
  }) async {
    final headers = await _authHeaders();
    if (headers == null) return null;
    final res = await http
        .post(
          Uri.parse('${ApiConfig.baseUrl}/api/payments/create/'),
          headers: headers,
          body: jsonEncode({
            'plan_id': planId,
            'payment_method': paymentMethod,
            'transaction_reference': transactionReference,
          }),
        )
        .timeout(const Duration(seconds: 25));
    if (res.statusCode < 200 || res.statusCode >= 300) return null;
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) return null;
    final payment = decoded['payment'] as Map<String, dynamic>? ?? const {};
    return ManualPaymentCreateResult(
      paymentId: (payment['id'] as num?)?.toInt() ?? 0,
      message: (decoded['message'] ?? '').toString(),
      bankDetails: Map<String, dynamic>.from(
        decoded['bank_details'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }

  Future<bool> uploadPaymentProof({
    required int paymentId,
    String transactionReference = '',
    XFile? proofFile,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth.accessToken') ?? '';
    if (token.isEmpty) return false;

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${ApiConfig.baseUrl}/api/payments/upload-proof/'),
    );
    request.headers['Authorization'] = 'Bearer $token';
    request.fields['payment_id'] = '$paymentId';
    if (transactionReference.trim().isNotEmpty) {
      request.fields['transaction_reference'] = transactionReference.trim();
    }
    if (proofFile != null) {
      request.files.add(
        await http.MultipartFile.fromPath(
          'screenshot_proof',
          proofFile.path,
          filename: proofFile.name,
        ),
      );
    }

    final streamed = await request.send().timeout(const Duration(seconds: 60));
    final resp = await http.Response.fromStream(streamed);
    return resp.statusCode >= 200 && resp.statusCode < 300;
  }

  Future<SubscribeResult?> buyOrUpgrade({
    required int planId,
    required bool isUpgrade,
    String paymentGateway = 'stripe',
    String paymentMethod = 'card',
    String couponCode = '',
    bool autoRenew = true,
  }) async {
    final headers = await _authHeaders();
    if (headers == null) return null;
    final res = await http
        .post(
          Uri.parse('${ApiConfig.baseUrl}/api/create-payment/'),
          headers: headers,
          body: jsonEncode({
            'plan_id': planId,
            'flow': isUpgrade ? 'upgrade' : 'subscribe',
            'payment_gateway': paymentGateway,
            'payment_method': paymentMethod,
            'coupon_code': couponCode,
            'auto_renew': autoRenew,
          }),
        )
        .timeout(const Duration(seconds: 25));
    if (res.statusCode < 200 || res.statusCode >= 300) return null;
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) return null;
    return SubscribeResult.fromJson(decoded);
  }

  Future<bool> confirmPayment(String paymentIntentId) async {
    final headers = await _authHeaders();
    if (headers == null) return false;
    final res = await http
        .post(
          Uri.parse('${ApiConfig.baseUrl}/api/confirm-payment/'),
          headers: headers,
          body: jsonEncode({'payment_intent_id': paymentIntentId}),
        )
        .timeout(const Duration(seconds: 20));
    return res.statusCode >= 200 && res.statusCode < 300;
  }
}
