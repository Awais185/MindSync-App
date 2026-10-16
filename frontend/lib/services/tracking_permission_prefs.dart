import 'package:shared_preferences/shared_preferences.dart';

/// Keys for permission / tracking setup (kept separate to avoid import cycles).
abstract final class TrackingPermissionPrefs {
  static const String trackingSetupDoneKey = 'mindsync.tracking_setup_done';

  static const String usageGrantedKey = 'mindsync.perm.usage_granted';
  static const String cameraGrantedKey = 'mindsync.perm.camera_granted';
  static const String screenCaptureGrantedKey =
      'mindsync.perm.screen_capture_granted';
  static const String accessibilityGrantedKey =
      'mindsync.perm.accessibility_granted';
  static const String screenCaptureSkippedKey =
      'mindsync.perm.screen_capture_skipped';

  static String scopedKey(String base, String? userId) {
    if (userId == null || userId.isEmpty) return base;
    return '$base.$userId';
  }

  static Future<({
    bool usage,
    bool camera,
    bool screenCapture,
    bool accessibility,
    bool screenCaptureSkipped,
  })> readGrantSnapshot({String? userId}) async {
    final prefs = await SharedPreferences.getInstance();
    bool readBool(String base) {
      if (userId != null && userId.isNotEmpty) {
        final scoped = prefs.getBool(scopedKey(base, userId));
        if (scoped != null) return scoped;
      }
      return prefs.getBool(base) ?? false;
    }

    return (
      usage: readBool(usageGrantedKey),
      camera: readBool(cameraGrantedKey),
      screenCapture: readBool(screenCaptureGrantedKey),
      accessibility: readBool(accessibilityGrantedKey),
      screenCaptureSkipped: readBool(screenCaptureSkippedKey),
    );
  }

  /// Persist which steps the user completed (device + per-account on this phone).
  static Future<void> saveGrantSnapshot({
    required bool usage,
    required bool camera,
    required bool screenCapture,
    required bool accessibility,
    bool? screenCaptureSkipped,
    bool markSetupDone = true,
    String? userId,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    Future<void> writeBool(String base, bool value) async {
      await prefs.setBool(base, value);
      if (userId != null && userId.isNotEmpty) {
        await prefs.setBool(scopedKey(base, userId), value);
      }
    }

    await writeBool(usageGrantedKey, usage);
    await writeBool(cameraGrantedKey, camera);
    await writeBool(screenCaptureGrantedKey, screenCapture);
    await writeBool(accessibilityGrantedKey, accessibility);
    if (screenCaptureSkipped != null) {
      await writeBool(screenCaptureSkippedKey, screenCaptureSkipped);
    }
    if (markSetupDone) {
      await writeBool(trackingSetupDoneKey, true);
    }
  }

  static Future<void> markScreenCaptureSkipped({String? userId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(screenCaptureSkippedKey, true);
    if (userId != null && userId.isNotEmpty) {
      await prefs.setBool(scopedKey(screenCaptureSkippedKey, userId), true);
    }
  }

  static Future<bool> isScreenCaptureSkipped({String? userId}) async {
    final prefs = await SharedPreferences.getInstance();
    if (userId != null && userId.isNotEmpty) {
      final scoped = prefs.getBool(scopedKey(screenCaptureSkippedKey, userId));
      if (scoped != null) return scoped;
    }
    return prefs.getBool(screenCaptureSkippedKey) ?? false;
  }

  static Future<bool> isSetupMarkedDone([String? userId]) async {
    final prefs = await SharedPreferences.getInstance();
    if (userId != null && userId.isNotEmpty) {
      if (prefs.getBool(scopedKey(trackingSetupDoneKey, userId)) ?? false) {
        return true;
      }
    }
    return prefs.getBool(trackingSetupDoneKey) ?? false;
  }
}
