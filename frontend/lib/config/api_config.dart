import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kDebugMode, kIsWeb;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Central dev API settings — saved for USB tether + physical phone (May 2026).
abstract final class ApiConfig {
  ApiConfig._();

  /// PC USB tether IPv4 — update if `ipconfig` shows a different address.
  static const String laptopHostIp = '172.24.168.80';

  static const int backendPort = 8000;

  /// Physical phone uses this URL (adb reverse maps phone 127.0.0.1 → PC :8000).
  static const String physicalPhoneBaseUrl =
      'http://127.0.0.1:$backendPort';

  static String get defaultPhysicalBaseUrl =>
      'http://$laptopHostIp:$backendPort';

  static const String _androidEmulator = 'http://10.0.2.2:8000';

  /// Optional override: LAN host
  static const String _lanHostOverride = String.fromEnvironment(
    'DEV_LAN_HOST',
    defaultValue: '',
  );

  /// Web API override
  static const String _webApiOverride = String.fromEnvironment(
    'WEB_API_BASE_URL',
    defaultValue: '',
  );

  static const String _defineBackend = String.fromEnvironment(
    'BACKEND_BASE_URL',
    defaultValue: '',
  );

  static const String _defineApiUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  static const String _useUsbBackend = String.fromEnvironment(
    'USE_USB_BACKEND',
    defaultValue: 'true',
  );

  static late final String baseUrl;

  static Future<void> initialize() async {
    baseUrl = await _resolve();
    await _pushBaseUrlToNativeIfAndroid();

    if (kDebugMode) {
      // ignore: avoid_print
      print('MindSync API baseUrl: $baseUrl');
      unawaited(_debugVerifyBackendReachable());
    }
  }

  static Future<void> _debugVerifyBackendReachable() async {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final android = await DeviceInfoPlugin().androidInfo;
      if (!android.isPhysicalDevice) return;
    } catch (_) {
      return;
    }

    try {
      final probe = uri('/api/auth/login/');
      final response =
          await http.get(probe).timeout(const Duration(seconds: 4));
      if (response.statusCode >= 200 && response.statusCode < 500) {
        // ignore: avoid_print
        print('MindSync: backend reachable at $baseUrl');
        return;
      }
    } catch (_) {
      // fall through to help text
    }

    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('*** MindSync: backend NOT reachable at $baseUrl ***');
    // ignore: avoid_print
    print('  1) Start backend: MindSync\\backend\\runserver.bat');
    // ignore: avoid_print
    print('  2) USB + debugging on, then: adb reverse tcp:8000 tcp:8000');
    // ignore: avoid_print
    print('  3) Phone Chrome test: $baseUrl/admin/');
    // ignore: avoid_print
    print('  Easiest: MindSync\\connect_phone.bat  OR  frontend\\run.bat run');
    // ignore: avoid_print
    print('');
  }

  static Future<String> _resolve() async {
    // 1. Hard overrides first
    for (final raw in [_defineBackend, _defineApiUrl]) {
      final t = raw.trim();
      if (t.isNotEmpty) {
        return _stripTrailingSlash(t);
      }
    }

    // 2. Web
    if (kIsWeb) {
      final webOverride = _webApiOverride.trim();
      if (webOverride.isNotEmpty) {
        return _stripTrailingSlash(webOverride);
      }
      return _webBackendUrl();
    }

    // 3. Mobile / Desktop
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        final android = await DeviceInfoPlugin().androidInfo;
        if (!android.isPhysicalDevice) {
          return _androidEmulator;
        }
        return _resolveAndroidPhysicalUrl();

      case TargetPlatform.iOS:
        final ios = await DeviceInfoPlugin().iosInfo;
        if (!ios.isPhysicalDevice) {
          return 'http://localhost:$backendPort';
        }
        return defaultPhysicalBaseUrl;

      default:
        return 'http://localhost:$backendPort';
    }
  }

  static String _webBackendUrl() {
    try {
      final page = Uri.base;
      final host = page.host.trim();

      if (host.isEmpty ||
          host == 'localhost' ||
          host == '127.0.0.1' ||
          host == '[::1]') {
        return 'http://localhost:$backendPort';
      }

      return 'http://$host:$backendPort';
    } catch (_) {
      return 'http://localhost:$backendPort';
    }
  }

  static bool get _preferUsbAdbReverse {
    final v = _useUsbBackend.trim().toLowerCase();
    return v != 'false' && v != '0' && v != 'no';
  }

  /// Always returns 127.0.0.1 when USE_USB_BACKEND=true (default).
  /// No probing — adb reverse tcp:8000 tcp:8000 must be run before flutter run.
  static Future<String> _resolveAndroidPhysicalUrl() async {
    // LAN override takes priority if explicitly set
    final override = _lanHostOverride.trim();
    if (override.isNotEmpty &&
        override != '127.0.0.1' &&
        !override.contains('localhost')) {
      return 'http://$override:$backendPort';
    }

    // USB adb reverse — always trust 127.0.0.1, no probe needed
    if (_preferUsbAdbReverse) {
      return physicalPhoneBaseUrl; // http://127.0.0.1:8000
    }

    // Fallback: LAN IP
    return defaultPhysicalBaseUrl;
  }

  static Future<void> _pushBaseUrlToNativeIfAndroid() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    try {
      final android = await DeviceInfoPlugin().androidInfo;
      if (!android.isPhysicalDevice) return;
    } catch (_) {
      return;
    }

    try {
      const channel = MethodChannel('mindsync/screen_time');
      await channel.invokeMethod<void>('configureTracker', {
        'baseUrl': baseUrl,
        'token': '',
        'userId': '',
        'faceVerified': false,
        'faceMatchPercent': 50.0,
      });
    } catch (_) {
      // ignore
    }
  }

  static String _stripTrailingSlash(String url) {
    if (url.endsWith('/')) {
      return url.substring(0, url.length - 1);
    }
    return url;
  }

  static Uri uri(String path) {
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$baseUrl$p');
  }
}