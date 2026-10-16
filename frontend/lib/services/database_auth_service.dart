import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'auth_api_exception.dart';

/// Talks to Django REST API (PostgreSQL `auth_user` and related tables).
class DatabaseAuthService {
  DatabaseAuthService._();
  static final DatabaseAuthService instance = DatabaseAuthService._();

  static String _normalizeLoginIdentifier(String emailOrUsername) {
    final trimmed = emailOrUsername.trim();
    if (trimmed.contains('@')) {
      return trimmed.toLowerCase();
    }
    return trimmed;
  }

  /// Returns JWT payload on success. Throws [AuthApiException] on auth/HTTP errors.
  Future<Map<String, dynamic>> login({
    required String emailOrUsername,
    required String password,
  }) async {
    final identifier = _normalizeLoginIdentifier(emailOrUsername);
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
      throw AuthApiException(
        'Cannot reach MindSync server at ${ApiConfig.baseUrl}. '
        'Start the backend (runserver 0.0.0.0:8000) and, on a physical phone, '
        'run: adb reverse tcp:8000 tcp:8000',
      );
    }

    debugPrint(
      'DatabaseAuthService: login ${response.statusCode} for $identifier',
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw AuthApiException(
          'Unexpected login response from server.',
          statusCode: response.statusCode,
        );
      }
      final access = decoded['access']?.toString();
      final refresh = decoded['refresh']?.toString();
      final user = decoded['user'];
      if (access == null ||
          access.isEmpty ||
          refresh == null ||
          refresh.isEmpty ||
          user is! Map) {
        debugPrint(
          'DatabaseAuthService: malformed login body keys=${decoded.keys}',
        );
        throw AuthApiException(
          'Login succeeded but the server response was incomplete. '
          'Check API /api/auth/login/ returns access, refresh, and user.',
          statusCode: response.statusCode,
        );
      }
      return decoded;
    }

    if (response.statusCode == 404) {
      throw AuthApiException(
        'Login API not found at ${ApiConfig.baseUrl}/api/auth/login/. '
        'Check BACKEND_BASE_URL / DEV_LAN_HOST.',
        statusCode: 404,
      );
    }

    if (response.statusCode >= 500) {
      throw AuthApiException(
        'Server error (${response.statusCode}). Please try again.',
        statusCode: response.statusCode,
      );
    }

    final message = _extractError(response.body);
    final invalid = response.statusCode == 400 &&
        (message.toLowerCase().contains('invalid') ||
            message.toLowerCase().contains('credential'));
    throw AuthApiException(
      invalid
          ? 'Invalid email or password. Use the email or username registered '
              'on this server (${ApiConfig.baseUrl}).'
          : message,
      statusCode: response.statusCode,
      isInvalidCredentials: invalid,
    );
  }

  Future<void> signupMultipart(http.MultipartRequest request) async {
    http.Response response;
    try {
      final streamed = await request.send().timeout(
        const Duration(seconds: 30),
      );
      response = await http.Response.fromStream(streamed);
    } on Exception {
      throw AuthApiException(
        'Cannot reach MindSync server at ${ApiConfig.baseUrl}. '
        'Start backend and check USB/Wi‑Fi connection.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthApiException(_extractError(response.body));
    }
  }

  String _extractError(String body) {
    try {
      final parsed = jsonDecode(body);
      if (parsed is Map<String, dynamic>) {
        final nonField = parsed['non_field_errors'];
        if (nonField is List && nonField.isNotEmpty) {
          return nonField.first.toString();
        }
        for (final value in parsed.values) {
          if (value is List && value.isNotEmpty) return value.first.toString();
          if (value is String && value.isNotEmpty) return value;
        }
        final detail = parsed['detail'];
        if (detail is String) return detail;
        final message = parsed['message'];
        if (message is String) return message;
      }
    } catch (_) {}
    return 'Request failed. Please check your details and try again.';
  }
}
