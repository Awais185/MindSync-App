import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../utils/resilient_http.dart' show getWithRetry;

class ContentTypeWatchItem {
  const ContentTypeWatchItem({
    required this.label,
    required this.count,
    required this.percent,
    required this.isPlaceholder,
    required this.hasWatchData,
  });

  final String label;
  final int count;
  final double percent;
  final bool isPlaceholder;
  final bool hasWatchData;

  factory ContentTypeWatchItem.fromJson(Map<String, dynamic> j) =>
      ContentTypeWatchItem(
        label: (j['label'] ?? '').toString(),
        count: (j['count'] as num?)?.toInt() ?? 0,
        percent: ((j['percent'] as num?) ?? 0).toDouble(),
        isPlaceholder: j['is_placeholder'] == true,
        hasWatchData: j['has_watch_data'] == true,
      );
}

class ContentTypeRecentWatch {
  const ContentTypeRecentWatch({
    required this.time,
    required this.date,
    required this.category,
    required this.platform,
    required this.durationSeconds,
    required this.summary,
  });

  final String time;
  final String date;
  final String category;
  final String platform;
  final int durationSeconds;
  final String summary;

  factory ContentTypeRecentWatch.fromJson(Map<String, dynamic> j) =>
      ContentTypeRecentWatch(
        time: (j['time'] ?? '').toString(),
        date: (j['date'] ?? '').toString(),
        category: (j['category'] ?? '').toString(),
        platform: (j['platform'] ?? '').toString(),
        durationSeconds: (j['duration_seconds'] as num?)?.toInt() ?? 0,
        summary: (j['summary'] ?? '').toString(),
      );
}

class ContentTypeWatchData {
  const ContentTypeWatchData({
    required this.hasData,
    required this.period,
    required this.windowLabel,
    required this.startDate,
    required this.endDate,
    required this.totalChunks,
    required this.topCategory,
    required this.topPercent,
    required this.items,
    required this.recentWatches,
  });

  final bool hasData;
  final String period;
  final String windowLabel;
  final String startDate;
  final String endDate;
  final int totalChunks;
  final String? topCategory;
  final double topPercent;
  final List<ContentTypeWatchItem> items;
  final List<ContentTypeRecentWatch> recentWatches;

  static const empty = ContentTypeWatchData(
    hasData: false,
    period: 'week',
    windowLabel: 'Last 7 days',
    startDate: '',
    endDate: '',
    totalChunks: 0,
    topCategory: null,
    topPercent: 0,
    items: [],
    recentWatches: [],
  );

  factory ContentTypeWatchData.fromJson(Map<String, dynamic> j) =>
      ContentTypeWatchData(
        hasData: j['has_data'] == true,
        period: (j['period'] ?? 'week').toString(),
        windowLabel: (j['window_label'] ?? 'Last 7 days').toString(),
        startDate: (j['start_date'] ?? '').toString(),
        endDate: (j['end_date'] ?? '').toString(),
        totalChunks: (j['total_chunks'] as num?)?.toInt() ?? 0,
        topCategory: j['top_category']?.toString(),
        topPercent: ((j['top_percent'] as num?) ?? 0).toDouble(),
        items: (j['items'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ContentTypeWatchItem.fromJson)
            .toList(),
        recentWatches: (j['recent_watches'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ContentTypeRecentWatch.fromJson)
            .toList(),
      );
}

class ContentTypeWatchService {
  ContentTypeWatchService._();
  static final ContentTypeWatchService instance = ContentTypeWatchService._();

  Future<ContentTypeWatchData> fetch({String period = 'week'}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth.accessToken') ?? '';
    if (token.isEmpty) return ContentTypeWatchData.empty;

    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/api/auth/analytics/content-type/',
    ).replace(queryParameters: {'period': period});

    final res = await getWithRetry(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      timeout: const Duration(seconds: 25),
    );
    if (res == null || res.statusCode < 200 || res.statusCode >= 300) {
      return ContentTypeWatchData.empty;
    }
    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) {
      return ContentTypeWatchData.fromJson(decoded);
    }
    return ContentTypeWatchData.empty;
  }
}
