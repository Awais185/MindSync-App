import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../models/late_night_sleep_snapshot.dart';

/// Pushes device sleep / late-night metrics to Django `ScreenTime` for today.
class HomeSleepSyncService {
  HomeSleepSyncService._();
  static final HomeSleepSyncService instance = HomeSleepSyncService._();

  DateTime? _lastPush;
  String? _lastSignature;

  Future<void> syncFromDeviceSnapshot(LateNightSleepSnapshot sleep) async {
    if (kIsWeb) return;
    final sleepSec = sleep.sleepTonightMinutes * 60;
    final lateSec = sleep.lateNightTonightMinutes * 60;
    if (sleepSec <= 0 && lateSec <= 0) return;

    final signature = '$sleepSec:$lateSec';
    final now = DateTime.now();
    if (_lastSignature == signature &&
        _lastPush != null &&
        now.difference(_lastPush!) < const Duration(minutes: 2)) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth.accessToken') ?? '';
    if (token.isEmpty) return;

    try {
      final response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/api/screen-time/update/'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'mode': 'sleep_absolute',
              'sleep_time': sleepSec,
              'late_night_activity': lateSec,
            }),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        _lastPush = now;
        _lastSignature = signature;
      }
    } catch (e) {
      debugPrint('HomeSleepSyncService: $e');
    }
  }
}
