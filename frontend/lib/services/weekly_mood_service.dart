import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../utils/resilient_http.dart' show getWithRetry;
import 'wellness_dashboard_service.dart';

class MoodDayMedia {
  const MoodDayMedia({required this.type, required this.url, this.id});

  final String type;
  final String url;
  final int? id;

  factory MoodDayMedia.fromJson(Map<String, dynamic> j) => MoodDayMedia(
        type: (j['type'] ?? 'image').toString(),
        url: (j['url'] ?? '').toString(),
        id: (j['id'] as num?)?.toInt(),
      );
}

class MoodDayEntry {
  const MoodDayEntry({
    required this.date,
    required this.label,
    required this.graphLabel,
    required this.moodScore,
    required this.moodCategory,
    required this.entries,
    required this.media,
  });

  final String date;
  final String label;
  final String graphLabel;
  final double? moodScore;
  final String moodCategory;
  final int entries;
  final List<MoodDayMedia> media;

  MoodDayMedia? get previewMedia => media.isNotEmpty ? media.first : null;

  factory MoodDayEntry.fromJson(Map<String, dynamic> j) {
    final media = ((j['media'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(MoodDayMedia.fromJson)
        .toList();
    return MoodDayEntry(
      date: (j['date'] ?? '').toString(),
      label: (j['label'] ?? '').toString(),
      graphLabel: (j['graph_label'] ?? j['label'] ?? '').toString(),
      moodScore: (j['mood_score'] as num?)?.toDouble(),
      moodCategory: (j['mood_category'] ?? '').toString(),
      entries: (j['entries'] as num?)?.toInt() ?? 0,
      media: media.take(1).toList(),
    );
  }
}

class OverallMoodSummary {
  const OverallMoodSummary({
    required this.label,
    required this.rawLabel,
    required this.score,
    required this.category,
  });

  final String label;
  final String rawLabel;
  final double? score;
  final String category;

  static const empty = OverallMoodSummary(
    label: '',
    rawLabel: '',
    score: null,
    category: '',
  );

  factory OverallMoodSummary.fromJson(Map<String, dynamic>? j) {
    if (j == null) return OverallMoodSummary.empty;
    return OverallMoodSummary(
      label: (j['label'] ?? '').toString(),
      rawLabel: (j['raw_label'] ?? '').toString(),
      score: (j['score'] as num?)?.toDouble(),
      category: (j['category'] ?? '').toString(),
    );
  }
}

class MoodDistributionItem {
  const MoodDistributionItem({
    required this.mood,
    required this.label,
    required this.count,
    required this.percent,
  });

  final String mood;
  final String label;
  final int count;
  final double percent;

  factory MoodDistributionItem.fromJson(Map<String, dynamic> j) =>
      MoodDistributionItem(
        mood: (j['mood'] ?? '').toString(),
        label: (j['label'] ?? '').toString(),
        count: (j['count'] as num?)?.toInt() ?? 0,
        percent: (j['percent'] as num?)?.toDouble() ?? 0,
      );
}

class RecentMoodEntry {
  const RecentMoodEntry({
    required this.id,
    required this.label,
    required this.time,
    required this.media,
  });

  final int? id;
  final String label;
  final String time;
  final List<MoodDayMedia> media;

  MoodDayMedia? get preview => media.isNotEmpty ? media.first : null;

  factory RecentMoodEntry.fromJson(Map<String, dynamic> j) {
    final media = ((j['media'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(MoodDayMedia.fromJson)
        .toList();
    return RecentMoodEntry(
      id: (j['id'] as num?)?.toInt(),
      label: (j['label'] ?? '').toString(),
      time: (j['time'] ?? '').toString(),
      media: media,
    );
  }
}

class WeeklyMoodLiveData {
  const WeeklyMoodLiveData({
    required this.hasSummary,
    required this.placeholder,
    required this.dominantMood,
    required this.overallMood,
    required this.moodDistribution,
    required this.entryCount,
    required this.days,
    required this.recentEntries,
    required this.insights,
    this.updatedAt,
  });

  final bool hasSummary;
  final String? placeholder;
  final String dominantMood;
  final OverallMoodSummary overallMood;
  final List<MoodDistributionItem> moodDistribution;
  final int entryCount;
  final List<MoodDayEntry> days;
  final List<RecentMoodEntry> recentEntries;
  final Map<String, dynamic> insights;
  final String? updatedAt;

  static const empty = WeeklyMoodLiveData(
    hasSummary: false,
    placeholder: 'Not enough data yet',
    dominantMood: '',
    overallMood: OverallMoodSummary.empty,
    moodDistribution: [],
    entryCount: 0,
    days: [],
    recentEntries: [],
    insights: {},
  );

  factory WeeklyMoodLiveData.fromJson(Map<String, dynamic> j) => WeeklyMoodLiveData(
        hasSummary: j['has_summary'] == true,
        placeholder: j['placeholder']?.toString(),
        dominantMood: (j['dominant_mood'] ?? '').toString(),
        overallMood: OverallMoodSummary.fromJson(
          j['overall_mood'] as Map<String, dynamic>?,
        ),
        moodDistribution: ((j['mood_distribution'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(MoodDistributionItem.fromJson)
            .toList(),
        entryCount: (j['entry_count'] as num?)?.toInt() ?? 0,
        days: ((j['days'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(MoodDayEntry.fromJson)
            .toList(),
        recentEntries: ((j['recent_entries'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(RecentMoodEntry.fromJson)
            .toList(),
        insights: (j['insights'] as Map<String, dynamic>?) ?? const {},
        updatedAt: j['updated_at']?.toString(),
      );
}

/// Polls live weekly mood data; refreshes wellness dashboard on each tick.
class WeeklyMoodService {
  WeeklyMoodService._();
  static final WeeklyMoodService instance = WeeklyMoodService._();

  final ValueNotifier<WeeklyMoodLiveData> live = ValueNotifier(WeeklyMoodLiveData.empty);

  Timer? _pollTimer;
  bool _busy = false;

  void startPolling({Duration interval = const Duration(seconds: 12)}) {
    _pollTimer?.cancel();
    unawaited(refresh());
    _pollTimer = Timer.periodic(interval, (_) => unawaited(refresh()));
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void resetForNewUser() {
    stopPolling();
    live.value = WeeklyMoodLiveData.empty;
    _busy = false;
  }

  Future<void> refresh() async {
    if (_busy) return;
    _busy = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth.accessToken') ?? '';
      if (token.isEmpty) return;

      final res = await getWithRetry(
        Uri.parse('${ApiConfig.baseUrl}/api/auth/mood/weekly/'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        timeout: const Duration(seconds: 18),
      );
      if (res == null || res.statusCode < 200 || res.statusCode >= 300) return;
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) {
        live.value = WeeklyMoodLiveData.fromJson(decoded);
      }
      unawaited(WellnessDashboardService.instance.refresh(force: true));
    } catch (_) {
      // Keep last good value.
    } finally {
      _busy = false;
    }
  }
}
