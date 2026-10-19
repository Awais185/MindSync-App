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
    await ScreenTimeService.instance.persistDevicePermissionGrants(
      cameraOverride: granted,
    );
  }

  static Future<void> _persistAfterGrant() async {
    await ScreenTimeService.instance.persistDevicePermissionGrants();
  }

  static Future<bool> ensureUsageAccess(BuildContext context) async {
    if (kIsWeb) return true;
    if (await ScreenTimeService.instance.hasUsageAccess()) {
      await _persistAfterGrant();
      return true;
    }
    await _confirmThen(
      context,
      title: 'Usage access',
      message:
          'MindSync will open Android usage access settings. Turn on access for MindSync, then return to the app.',
      openSettings: ScreenTimeService.instance.openUsageSettings,
    );
    final ok = await ScreenTimeService.instance.hasUsageAccess();
    if (ok) await _persistAfterGrant();
    return ok;
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
    await ScreenTimeService.instance.openScreenRecordingOsSettings();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final ok = await ScreenTimeService.instance.hasScreenCapturePermission();
    if (ok) await _persistAfterGrant();
    return ok;
  }

  /// Permission UI: jump straight to OS settings (no MindSync alert dialog).
  static Future<void> openScreenRecordingSettings() async {
    if (kIsWeb) return;
    await ScreenTimeService.instance.openScreenRecordingOsSettings();
  }

  /// Display-over-other-apps / overlay — system settings only.
  static Future<void> openOverlaySettings() async {
    if (kIsWeb) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await ScreenTimeService.instance.openManageOverlaySettings();
  }

  static Future<bool> ensureAccessibility(BuildContext context) async {
    if (kIsWeb) return true;
    if (await ScreenTimeService.instance.hasAccessibilityService()) {
      await _persistAfterGrant();
      return true;
    }
    await _confirmThen(
      context,
      title: 'Accessibility',
      message:
          'Open accessibility settings, find MindSync, and turn the service on.',
      openSettings: ScreenTimeService.instance.openAccessibilitySettings,
    );
    final ok = await ScreenTimeService.instance.hasAccessibilityService();
    if (ok) await _persistAfterGrant();
    return ok;
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
