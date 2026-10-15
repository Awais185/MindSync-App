import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';

/// Preloads server-side emotion + face-mesh models while the user is on the camera screen.
Future<void> warmupBehaviorAnalysisModels() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth.accessToken') ?? '';
    if (token.isEmpty) return;
    await http
        .post(
          Uri.parse('${ApiConfig.baseUrl}/api/face/behavior/warmup/'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 20));
  } catch (_) {
    // Non-fatal; analyze will warm models on first request.
  }
}
