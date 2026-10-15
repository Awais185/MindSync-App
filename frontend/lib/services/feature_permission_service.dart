import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'screen_time_service.dart';
import 'tracking_permission_prefs.dart';

/// Opens the real system screen for a permission when a feature needs it (post-login).
abstract final class FeaturePermissionService {
  static const _accent = Color(0xFF6F39E8);

  static Future<bool> _confirmThen(
    BuildContext context, {
    required String title,
    required String message,
    required Future<void> Function() openSettings,
  }) async {
    if (!context.mounted) return false;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: _accent),
            child: const Text('Open settings'),
          ),
        ],
      ),
    );
    if (go != true) return false;
    await openSettings();
    return true;
  }

  static Future<void> _persistCamera(bool granted) async {
    final prefs = await TrackingPermissionPrefs.readGrantSnapshot();
    await TrackingPermissionPrefs.saveGrantSnapshot(
      usage: prefs.usage,
      camera: granted || prefs.camera,
      screenCapture: prefs.screenCapture,
      accessibility: prefs.accessibility,
      screenCaptureSkipped: prefs.screenCaptureSkipped,
      markSetupDone: await TrackingPermissionPrefs.isSetupMarkedDone(),
    );
  }

  static Future<bool> ensureUsageAccess(BuildContext context) async {
    if (kIsWeb) return true;
    if (await ScreenTimeService.instance.hasUsageAccess()) return true;
    await _confirmThen(
      context,
      title: 'Usage access',
      message:
          'MindSync will open Android usage access settings. Turn on access for MindSync, then return to the app.',
      openSettings: ScreenTimeService.instance.openUsageSettings,
    );
    return await ScreenTimeService.instance.hasUsageAccess();
  }

  static Future<bool> ensureCamera(BuildContext context) async {
    if (kIsWeb) return true;
    var status = await Permission.camera.status;
    if (status.isGranted) {
      await _persistCamera(true);
      return true;
    }
    if (status.isDenied || status.isLimited) {
      status = await Permission.camera.request();
      if (status.isGranted) {
        await _persistCamera(true);
        return true;
      }
    }
    await _confirmThen(
      context,
      title: 'Camera',
      message:
          'Open MindSync app permissions and allow Camera, then return here.',
      openSettings: openAppSettings,
    );
    final ok = (await Permission.camera.status).isGranted;
    if (ok) await _persistCamera(true);
    return ok;
  }

  static Future<bool> ensureMicrophone(BuildContext context) async {
    if (kIsWeb) return true;
    var status = await Permission.microphone.status;
    if (status.isGranted) return true;
    if (status.isDenied || status.isLimited) {
      status = await Permission.microphone.request();
      if (status.isGranted) return true;
    }
    await _confirmThen(
      context,
      title: 'Microphone',
      message:
          'Open MindSync app permissions and allow Microphone, then return here.',
      openSettings: openAppSettings,
    );
    return (await Permission.microphone.status).isGranted;
  }

  static Future<bool> ensureScreenCapture(BuildContext context) async {
    if (kIsWeb) return false;
    if (await ScreenTimeService.instance.hasScreenCapturePermission()) {
      return true;
    }
    if (!context.mounted) return false;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Screen recording'),
        content: const Text(
          'Android will show a system screen-capture prompt (not App info). '
          'Tap Start or Allow on that dialog to record short wellness clips.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: _accent),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (go != true) return false;
    await ScreenTimeService.instance.launchScreenCaptureConsent();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final ok = await ScreenTimeService.instance.hasScreenCapturePermission();
    if (ok) {
      final prefs = await TrackingPermissionPrefs.readGrantSnapshot();
      await TrackingPermissionPrefs.saveGrantSnapshot(
        usage: prefs.usage,
        camera: prefs.camera,
        screenCapture: true,
        accessibility: prefs.accessibility,
        screenCaptureSkipped: false,
        markSetupDone: await TrackingPermissionPrefs.isSetupMarkedDone(),
      );
    }
    return ok;
  }

  static Future<bool> ensureAccessibility(BuildContext context) async {
    if (kIsWeb) return true;
    if (await ScreenTimeService.instance.hasAccessibilityService()) return true;
    await _confirmThen(
      context,
      title: 'Accessibility',
      message:
          'Open accessibility settings, find MindSync, and turn the service on.',
      openSettings: ScreenTimeService.instance.openAccessibilitySettings,
    );
    return await ScreenTimeService.instance.hasAccessibilityService();
  }

  static Future<bool> ensureOverlay(BuildContext context) async {
    if (kIsWeb) return true;
    if (!Platform.isAndroid && !Platform.isIOS) return true;
    if (await ScreenTimeService.instance.hasOverlayPermission()) return true;
    await _confirmThen(
      context,
      title: 'Display over other apps',
      message: 'Allow MindSync to display over other apps for parental blocking.',
      openSettings: ScreenTimeService.instance.openManageOverlaySettings,
    );
    return await ScreenTimeService.instance.hasOverlayPermission();
  }
}
