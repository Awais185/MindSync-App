import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';

/// Talks to Django REST API, which reads/writes `backend/db.sqlite3` (auth_user table).
/// No Firebase — server SQL is the source of truth for accounts.
class DatabaseAuthService {
  DatabaseAuthService._();
  static final DatabaseAuthService instance = DatabaseAuthService._();

  /// Returns JWT payload on success, null if credentials invalid, throws if server unreachable.
  Future<Map<String, dynamic>?> login({
    required String emailOrUsername,
    required String password,
  }) async {
    final identifier = emailOrUsername.trim();
    http.Response response;
    try {
      response = await http
          .post(
            ApiConfig.uri('/api/auth/login/'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'username_or_email': identifier,
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 20));
    } on Exception catch (e) {
      debugPrint('DatabaseAuthService: connection failed — $e');
      throw Exception(
        'Cannot reach MindSync server. Start backend: '
        'python manage.py runserver 0.0.0.0:8000',
      );
    }

    debugPrint(
      'DatabaseAuthService: login ${response.statusCode} for $identifier',
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    if (response.statusCode >= 500) {
      throw Exception('Server error. Please try again.');
    }

    return null;
  }

  Future<void> signupMultipart(http.MultipartRequest request) async {
    http.Response response;
    try {
      final streamed = await request.send().timeout(
        const Duration(seconds: 30),
      );
      response = await http.Response.fromStream(streamed);
    } on Exception {
      throw Exception(
        'Cannot reach MindSync server. Start backend: '
        'python manage.py runserver 0.0.0.0:8000',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractError(response.body));
    }
  }

  String _extractError(String body) {
    try {
      final parsed = jsonDecode(body);
      if (parsed is Map<String, dynamic>) {
        for (final value in parsed.values) {
          if (value is List && value.isNotEmpty) return value.first.toString();
          if (value is String && value.isNotEmpty) return value;
        }
        final detail = parsed['detail'];
        if (detail is String) return detail;
      }
    } catch (_) {}
    return 'Registration failed. Please check your details.';
  }
}
