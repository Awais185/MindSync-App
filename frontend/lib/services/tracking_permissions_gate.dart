import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../screens/auth/permission_onboarding_screen.dart';
import 'local_auth_service.dart';
import 'screen_time_service.dart';
import 'tracking_permission_prefs.dart';

/// Usage access + Camera (critical). Screen capture is optional (native flow).
class TrackingPermissionsGate {
  TrackingPermissionsGate._();

  static const trackingSetupDoneKey = TrackingPermissionPrefs.trackingSetupDoneKey;

  static Future<bool> _coreTrackingGranted() async {
    final usage = await ScreenTimeService.instance.hasUsageAccess();
    if (!usage) return false;
    return true;
  }

  /// Usage — required before starting [ScreenTimeService].
  static Future<bool> isCoreTrackingGranted() => _coreTrackingGranted();

  /// Starts polling / sync only when core OS permissions are granted (no-op otherwise).
  static Future<void> startScreenTimeIfPermitted() async {
    if (kIsWeb) {
      ScreenTimeService.instance.start();
      return;
    }
    if (!await _coreTrackingGranted()) return;
    await ScreenTimeService.instance.syncScreenCaptureGrant();
    ScreenTimeService.instance.start();
  }

  /// True when core OS permissions are granted (auto-heals stale setup flags).
  static Future<bool> isFullyGranted() async {
    if (!await _coreTrackingGranted()) {
      return false;
    }
    if (!await TrackingPermissionPrefs.isSetupMarkedDone()) {
      final cam = await Permission.camera.status;
      final usage = await ScreenTimeService.instance.hasUsageAccess();
      final screenCapture =
          await ScreenTimeService.instance.hasScreenCapturePermission();
      final accessibility =
          await ScreenTimeService.instance.hasAccessibilityService();
      await TrackingPermissionPrefs.saveGrantSnapshot(
        usage: usage,
        camera: cam.isGranted,
        screenCapture: screenCapture,
        accessibility: accessibility,
      );
    }
    return true;
  }

  /// After username/password succeeds. Skips UI if setup was already saved.
  static Future<bool> runMandatoryAfterAuthenticatedSession(
    BuildContext context,
    LocalAuthService auth,
  ) async {
    if (await isFullyGranted()) return true;
    if (!context.mounted) return false;

    final ok = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => PermissionOnboardingScreen(auth: auth),
          ),
        ) ??
        false;

    if (!ok) {
      await auth.logout();
      return false;
    }

    if (!await _coreTrackingGranted()) {
      await auth.logout();
      return false;
    }

    return true;
  }
}
