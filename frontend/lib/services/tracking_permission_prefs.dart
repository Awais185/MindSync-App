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

  /// Persist which steps the user completed during onboarding (for skip on reopen).
  static Future<void> saveGrantSnapshot({
    required bool usage,
    required bool camera,
    required bool screenCapture,
    required bool accessibility,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(usageGrantedKey, usage);
    await prefs.setBool(cameraGrantedKey, camera);
    await prefs.setBool(screenCaptureGrantedKey, screenCapture);
    await prefs.setBool(accessibilityGrantedKey, accessibility);
    await prefs.setBool(trackingSetupDoneKey, true);
  }

  static Future<bool> isSetupMarkedDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(trackingSetupDoneKey) ?? false;
  }
}
