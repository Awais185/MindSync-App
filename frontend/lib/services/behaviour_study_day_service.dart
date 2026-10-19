import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../utils/resilient_http.dart' show getWithRetry;

class BehaviourDaySummaryCard {
  const BehaviourDaySummaryCard({
    required this.key,
    required this.label,
    required this.count,
  });

  final String key;
  final String label;
  final int count;

  factory BehaviourDaySummaryCard.fromJson(Map<String, dynamic> j) =>
      BehaviourDaySummaryCard(
        key: (j['key'] ?? '').toString(),
        label: (j['label'] ?? '').toString(),
        count: (j['count'] as num?)?.toInt() ?? 0,
      );
}

class BehaviourDayFacialScan {
  const BehaviourDayFacialScan({
    required this.id,
    required this.time,
    required this.outcome,
    required this.outcomeLabel,
    required this.emotion,
    required this.stressScore,
    required this.depressionScore,
    required this.status,
    required this.sourceApp,
    required this.durationSeconds,
  });

  final int id;
  final String time;
  final String outcome;
  final String outcomeLabel;
  final String emotion;
  final int stressScore;
  final int depressionScore;
  final String status;
  final String sourceApp;
  final int durationSeconds;

  factory BehaviourDayFacialScan.fromJson(Map<String, dynamic> j) =>
      BehaviourDayFacialScan(
        id: (j['id'] as num?)?.toInt() ?? 0,
        time: (j['time'] ?? '').toString(),
        outcome: (j['outcome'] ?? '').toString(),
        outcomeLabel: (j['outcome_label'] ?? '').toString(),
        emotion: (j['emotion'] ?? '').toString(),
        stressScore: (j['stress_score'] as num?)?.toInt() ?? 0,
        depressionScore: (j['depression_score'] as num?)?.toInt() ?? 0,
        status: (j['status'] ?? '').toString(),
        sourceApp: (j['source_app'] ?? '').toString(),
        durationSeconds: (j['duration_seconds'] as num?)?.toInt() ?? 0,
      );
}

class BehaviourStudyDayData {
  const BehaviourStudyDayData({
    required this.hasData,
    required this.date,
    required this.windowLabel,
    required this.facialScanCount,
    required this.videoChunkSignals,
    required this.summary,
    required this.facialScans,
  });

  final bool hasData;
  final String date;
  final String windowLabel;
  final int facialScanCount;
  final int videoChunkSignals;
  final List<BehaviourDaySummaryCard> summary;
  final List<BehaviourDayFacialScan> facialScans;

  static const empty = BehaviourStudyDayData(
    hasData: false,
    date: '',
    windowLabel: 'Today',
    facialScanCount: 0,
    videoChunkSignals: 0,
    summary: [],
    facialScans: [],
  );

  factory BehaviourStudyDayData.fromJson(Map<String, dynamic> j) =>
      BehaviourStudyDayData(
        hasData: j['has_data'] == true,
        date: (j['date'] ?? '').toString(),
        windowLabel: (j['window_label'] ?? 'Today').toString(),
        facialScanCount: (j['facial_scan_count'] as num?)?.toInt() ?? 0,
        videoChunkSignals: (j['video_chunk_signals'] as num?)?.toInt() ?? 0,
        summary: (j['summary'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(BehaviourDaySummaryCard.fromJson)
            .toList(),
        facialScans: (j['facial_scans'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(BehaviourDayFacialScan.fromJson)
            .toList(),
      );
}

class BehaviourStudyDayService {
  BehaviourStudyDayService._();
  static final BehaviourStudyDayService instance = BehaviourStudyDayService._();

  Future<BehaviourStudyDayData> fetch() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth.accessToken') ?? '';
    if (token.isEmpty) return BehaviourStudyDayData.empty;

    final res = await getWithRetry(
      Uri.parse('${ApiConfig.baseUrl}/api/auth/analytics/behaviour-study/day/'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      timeout: const Duration(seconds: 25),
    );
    if (res == null || res.statusCode < 200 || res.statusCode >= 300) {
      return BehaviourStudyDayData.empty;
    }
    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) {
      return BehaviourStudyDayData.fromJson(decoded);
    }
    return BehaviourStudyDayData.empty;
  }
}
