import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/feature_permission_service.dart';
import '../services/screen_time_service.dart';
import '../services/tracking_permission_prefs.dart';

/// Shared permission list used on onboarding and in More → Permissions.
class PermissionSetupPanel extends StatefulWidget {
  const PermissionSetupPanel({
    super.key,
    this.showHero = true,
    this.onRefreshingChanged,
    this.onPermissionsChanged,
  });

  final bool showHero;
  final ValueChanged<bool>? onRefreshingChanged;
  final VoidCallback? onPermissionsChanged;

  @override
  State<PermissionSetupPanel> createState() => PermissionSetupPanelState();
}

class PermissionSetupPanelState extends State<PermissionSetupPanel>
    with WidgetsBindingObserver {
  bool usageOk = false;
  bool cameraOk = false;
  bool screenCaptureOk = false;
  bool accessibilityOk = false;
  bool overlayOk = false;
  bool refreshing = false;

  static const accent = Color(0xFF6F39E8);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(refreshAll()));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(refreshAll());
    }
  }

  Future<void> refreshAll() async {
    if (kIsWeb) return;
    setState(() => refreshing = true);
    widget.onRefreshingChanged?.call(true);
    try {
      final usage = await ScreenTimeService.instance.hasUsageAccess();
      final cam = await Permission.camera.status;
      final capture =
          await ScreenTimeService.instance.hasScreenCapturePermission();
      final a11y = await ScreenTimeService.instance.hasAccessibilityService();
      final overlay = await ScreenTimeService.instance.hasOverlayPermission();
      if (!mounted) return;
      setState(() {
        usageOk = usage;
        cameraOk = cam.isGranted;
        screenCaptureOk = capture;
        accessibilityOk = a11y;
        overlayOk = overlay;
      });
      widget.onPermissionsChanged?.call();
      if (usageOk || cameraOk || screenCaptureOk || accessibilityOk) {
        unawaited(persistGrantSnapshot(markSetupDone: true));
      }
    } finally {
      if (mounted) {
        setState(() => refreshing = false);
        widget.onRefreshingChanged?.call(false);
      }
    }
  }

  Future<void> openUsage() async {
    await ScreenTimeService.instance.openUsageSettings();
  }

  Future<void> openAppPermissions() async {
    await openAppSettings();
  }

  Future<void> openScreenCapture() async {
    await FeaturePermissionService.openScreenRecordingSettings();
  }

  Future<void> openAccessibility() async {
    await ScreenTimeService.instance.openAccessibilitySettings();
  }

  Future<void> openOverlay() async {
    await FeaturePermissionService.openOverlaySettings();
  }

  Future<void> persistGrantSnapshot({bool markSetupDone = true}) async {
    await ScreenTimeService.instance.persistDevicePermissionGrants(
      markSetupDone: markSetupDone,
    );
  }

  List<PermissionRowData> buildRows() {
    return [
      PermissionRowData(
        title: 'Usage access',
        subtitle: 'Screen time and per-app usage from your device',
        icon: Icons.hourglass_bottom_rounded,
        granted: usageOk,
        onEnable: openUsage,
      ),
      PermissionRowData(
        title: 'Camera',
        subtitle: 'Face scan, mood capture, and unlock verification',
        icon: Icons.camera_alt_outlined,
        granted: cameraOk,
        onEnable: openAppPermissions,
      ),
      PermissionRowData(
        title: 'Screen recording',
        subtitle: 'Opens system app settings to allow screen capture access',
        icon: Icons.screen_share_outlined,
        granted: screenCaptureOk,
        onEnable: openScreenCapture,
      ),
      PermissionRowData(
        title: 'Accessibility',
        subtitle: 'Detect video apps and optional parent blocking',
        icon: Icons.accessibility_new_rounded,
        granted: accessibilityOk,
        onEnable: openAccessibility,
      ),
      if (Platform.isAndroid || Platform.isIOS)
        PermissionRowData(
          title: 'Display over other apps',
          subtitle: 'Optional — block overlay when parent control is on',
          icon: Icons.layers_outlined,
          granted: overlayOk,
          onEnable: openOverlay,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const Center(child: Text('Permissions are managed on mobile.'));
    }

    final rows = buildRows();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showHero) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6F39E8), Color(0xFF4B2AAD)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Allow MindSync to work in the background',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Only usage access is required for screen time. '
                  'Tap a toggle to open the matching system setting — '
                  'when access is allowed there, the toggle turns on here.',
                  style: TextStyle(
                    color: Color(0xFFE8DDFF),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        ...rows.map(
          (row) => PermissionToggleTile(
            data: row,
            accent: accent,
            onToggle: () async => await row.onEnable(),
          ),
        ),
      ],
    );
  }
}

class PermissionRowData {
  const PermissionRowData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.granted,
    required this.onEnable,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool granted;
  final Future<void> Function() onEnable;
}

class PermissionToggleTile extends StatelessWidget {
  const PermissionToggleTile({
    super.key,
    required this.data,
    required this.accent,
    required this.onToggle,
  });

  final PermissionRowData data;
  final Color accent;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final statusLabel = data.granted ? 'Allowed' : 'Not allowed';
    final statusColor =
        data.granted ? const Color(0xFF16A34A) : const Color(0xFF9CA3AF);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(
              children: [
                Icon(data.icon, color: accent, size: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              data.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          Text(
                            statusLabel,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        data.subtitle,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6E7381),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: data.granted,
                  activeTrackColor: accent,
                  activeThumbColor: Colors.white,
                  onChanged: (_) => onToggle(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
