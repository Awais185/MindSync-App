import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../screens/auth/permission_onboarding_screen.dart';
import 'local_auth_service.dart';
import 'screen_time_service.dart';
import 'tracking_permission_prefs.dart';

/// Screen time depends on usage access only. Other permissions are requested just-in-time.
class TrackingPermissionsGate {
  TrackingPermissionsGate._();

  static const trackingSetupDoneKey = TrackingPermissionPrefs.trackingSetupDoneKey;

  static Future<bool> isUsageAccessGranted() async {
    if (kIsWeb) return true;
    return await ScreenTimeService.instance.hasUsageAccess();
  }

  /// Usage access — required before starting [ScreenTimeService].
  static Future<bool> isCoreTrackingGranted() => isUsageAccessGranted();

  /// Starts polling / sync only when usage access is granted (no-op otherwise).
  static Future<void> startScreenTimeIfPermitted() async {
    if (kIsWeb) {
      ScreenTimeService.instance.start();
      return;
    }
    if (!await isUsageAccessGranted()) return;
    await ScreenTimeService.instance.syncScreenCaptureGrant();
    ScreenTimeService.instance.start();
  }

  /// True after this account finished permission onboarding, or usage access is on device.
  static Future<bool> isFullyGranted([String? userId]) async {
    if (await TrackingPermissionPrefs.isSetupMarkedDone(userId)) {
      return true;
    }
    if (!kIsWeb && await isUsageAccessGranted()) {
      return true;
    }
    return false;
  }

  /// After username/password succeeds. Skips UI if onboarding was already completed or skipped.
  static Future<bool> runMandatoryAfterAuthenticatedSession(
    BuildContext context,
    LocalAuthService auth,
  ) async {
    final userId = await auth.getStoredUserId();
    await ScreenTimeService.instance.persistDevicePermissionGrants(userId: userId);
    if (await isFullyGranted(userId)) return true;
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

    return true;
  }
}
