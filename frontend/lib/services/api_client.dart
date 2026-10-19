import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'local_auth_service.dart';

/// Authenticated HTTP to the Django API (JWT refresh on 401).
class ApiClient {
  ApiClient._();

  static final ApiClient instance = ApiClient._();

  final LocalAuthService _auth = LocalAuthService.instance;

  Future<String?> _accessToken() => _auth.getAccessToken();

  Map<String, String> _jsonHeaders(String token) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  Future<http.Response?> get(
    String path, {
    Duration timeout = const Duration(seconds: 20),
    bool auth = true,
  }) async {
    if (!auth) {
      try {
        return await http
            .get(ApiConfig.uri(path))
            .timeout(timeout);
      } catch (_) {
        return null;
      }
    }

    var token = await _accessToken();
    if (token == null || token.isEmpty) return null;

    try {
      var response = await http
          .get(ApiConfig.uri(path), headers: _jsonHeaders(token))
          .timeout(timeout);
      if (response.statusCode == 401 && await _auth.tryRefreshAccessToken()) {
        token = await _accessToken();
        if (token == null || token.isEmpty) return response;
        response = await http
            .get(ApiConfig.uri(path), headers: _jsonHeaders(token))
            .timeout(timeout);
      }
      return response;
    } catch (_) {
      return null;
    }
  }

  Future<http.Response?> post(
    String path, {
    required Object body,
    Duration timeout = const Duration(seconds: 20),
    bool auth = true,
  }) async {
    final encoded = body is String ? body : jsonEncode(body);

    if (!auth) {
      try {
        return await http
            .post(
              ApiConfig.uri(path),
              headers: {'Content-Type': 'application/json'},
              body: encoded,
            )
            .timeout(timeout);
      } catch (_) {
        return null;
      }
    }

    var token = await _accessToken();
    if (token == null || token.isEmpty) return null;

    try {
      var response = await http
          .post(
            ApiConfig.uri(path),
            headers: _jsonHeaders(token),
            body: encoded,
          )
          .timeout(timeout);
      if (response.statusCode == 401 && await _auth.tryRefreshAccessToken()) {
        token = await _accessToken();
        if (token == null || token.isEmpty) return response;
        response = await http
            .post(
              ApiConfig.uri(path),
              headers: _jsonHeaders(token),
              body: encoded,
            )
            .timeout(timeout);
      }
      return response;
    } catch (_) {
      return null;
    }
  }

  Future<http.Response?> put(
    String path, {
    required Object body,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final encoded = body is String ? body : jsonEncode(body);
    var token = await _accessToken();
    if (token == null || token.isEmpty) return null;

    try {
      var response = await http
          .put(
            ApiConfig.uri(path),
            headers: _jsonHeaders(token),
            body: encoded,
          )
          .timeout(timeout);
      if (response.statusCode == 401 && await _auth.tryRefreshAccessToken()) {
        token = await _accessToken();
        if (token == null || token.isEmpty) return response;
        response = await http
            .put(
              ApiConfig.uri(path),
              headers: _jsonHeaders(token),
              body: encoded,
            )
            .timeout(timeout);
      }
      return response;
    } catch (_) {
      return null;
    }
  }

  Future<http.Response?> delete(
    String path, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    var token = await _accessToken();
    if (token == null || token.isEmpty) return null;

    try {
      var response = await http
          .delete(ApiConfig.uri(path), headers: _jsonHeaders(token))
          .timeout(timeout);
      if (response.statusCode == 401 && await _auth.tryRefreshAccessToken()) {
        token = await _accessToken();
        if (token == null || token.isEmpty) return response;
        response = await http
            .delete(ApiConfig.uri(path), headers: _jsonHeaders(token))
            .timeout(timeout);
      }
      return response;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> getJson(String path) async {
    final response = await get(path);
    if (response == null) return null;
    if (response.statusCode < 200 || response.statusCode >= 300) return null;
    try {
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
