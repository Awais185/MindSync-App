import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';

String _resolvedAssetUrl(String baseUrl, Object? rawUrl) {
  final u = rawUrl?.toString().trim() ?? '';
  if (u.isEmpty) return '';
  if (u.startsWith('http://') || u.startsWith('https://')) return u;
  final base =
      baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
  final path = u.startsWith('/') ? u.substring(1) : u;
  return '$base/$path';
}

class AppBrandingData {
  const AppBrandingData({
    required this.appName,
    required this.welcomeTagline,
    required this.logoUrl,
  });

  final String appName;
  final String welcomeTagline;
  final String logoUrl;

  static const fallback = AppBrandingData(
    appName: 'MindSync',
    welcomeTagline: 'AI-Powered Emotional Wellness',
    logoUrl: '',
  );
}

class SubscriptionPlanData {
  const SubscriptionPlanData({
    required this.slug,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.priceMonthly,
    required this.features,
    required this.buttonLabel,
    required this.badge,
    required this.isFeatured,
    required this.sortOrder,
  });

  final String slug;
  final String title;
  final String subtitle;
  final String description;
  final double priceMonthly;
  final List<String> features;
  final String buttonLabel;
  final String badge;
  final bool isFeatured;
  final int sortOrder;
}

class AppPublicService {
  AppPublicService._();

  static final AppPublicService instance = AppPublicService._();

  final ValueNotifier<AppBrandingData> branding =
      ValueNotifier<AppBrandingData>(AppBrandingData.fallback);
  final ValueNotifier<List<SubscriptionPlanData>> plans =
      ValueNotifier<List<SubscriptionPlanData>>(const []);

  bool _brandingLoading = false;
  bool _plansLoading = false;

  String get _baseUrl => ApiConfig.baseUrl;

  Future<void> loadBranding({bool forceRefresh = false}) async {
    if (_brandingLoading) return;
    if (!forceRefresh && branding.value.logoUrl.isNotEmpty) return;
    _brandingLoading = true;
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/public/branding/'))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) return;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return;
      branding.value = AppBrandingData(
        appName: (decoded['app_name'] ?? 'MindSync').toString(),
        welcomeTagline: (decoded['welcome_tagline'] ?? 'AI-Powered Emotional Wellness')
            .toString(),
        logoUrl: _resolvedAssetUrl(_baseUrl, decoded['logo_url']),
      );
    } catch (_) {
      // Keep fallback branding.
    } finally {
      _brandingLoading = false;
    }
  }

  Future<void> loadSubscriptionPlans({bool forceRefresh = false}) async {
    if (_plansLoading) return;
    if (!forceRefresh && plans.value.isNotEmpty) return;
    _plansLoading = true;
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/public/subscription-plans/'))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) return;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return;
      final items = (decoded['results'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(
            (item) => SubscriptionPlanData(
              slug: (item['slug'] ?? '').toString(),
              title: (item['title'] ?? '').toString(),
              subtitle: (item['subtitle'] ?? '').toString(),
              description: (item['description'] ?? '').toString(),
              priceMonthly: (item['price_monthly'] as num?)?.toDouble() ?? 0,
              features: (item['features'] as List<dynamic>? ?? const [])
                  .map((feature) => feature.toString())
                  .where((feature) => feature.trim().isNotEmpty)
                  .toList(),
              buttonLabel: (item['button_label'] ?? 'Choose Plan').toString(),
              badge: (item['badge'] ?? '').toString(),
              isFeatured: (item['is_featured'] as bool?) ?? false,
              sortOrder: (item['sort_order'] as num?)?.toInt() ?? 0,
            ),
          )
          .toList();
      if (items.isNotEmpty) {
        plans.value = items;
      }
    } catch (_) {
      // Keep current plans if loading fails.
    } finally {
      _plansLoading = false;
    }
  }
}
