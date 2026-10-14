import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// GET with short retries for transient browser errors (e.g. ERR_NETWORK_CHANGED).
Future<http.Response?> getWithRetry(
  Uri uri, {
  Map<String, String>? headers,
  Duration timeout = const Duration(seconds: 12),
  int maxAttempts = 3,
}) async {
  Object? lastError;
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    try {
      final response = await http.get(uri, headers: headers).timeout(timeout);
      return response;
    } on Exception catch (e) {
      lastError = e;
      if (attempt >= maxAttempts - 1) break;
      await Future<void>.delayed(Duration(milliseconds: 250 * (attempt + 1)));
    }
  }
  if (kDebugMode && lastError != null) {
    debugPrint('GET $uri failed after $maxAttempts attempts: $lastError');
  }
  return null;
}

Future<Map<String, dynamic>?> getJsonWithRetry(
  Uri uri, {
  Map<String, String>? headers,
}) async {
  final response = await getWithRetry(uri, headers: headers);
  if (response == null) return null;
  if (response.statusCode < 200 || response.statusCode >= 300) return null;
  try {
    final decoded = jsonDecode(response.body);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}
