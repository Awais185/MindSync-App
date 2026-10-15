import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/local_auth_service.dart';
import '../../services/screen_time_service.dart';
import '../../services/tracking_permissions_gate.dart';
import '../../services/tracking_permission_prefs.dart';

/// All MindSync permissions on one screen; toggles reflect real OS state after settings.
class PermissionOnboardingScreen extends StatefulWidget {
  const PermissionOnboardingScreen({
    super.key,
    required this.auth,
    this.embeddedInAppBootstrap = false,
    this.onBootstrapGranted,
    this.onBootstrapAbandon,
  });

  final LocalAuthService auth;
  final bool embeddedInAppBootstrap;
  final VoidCallback? onBootstrapGranted;
  final VoidCallback? onBootstrapAbandon;

  @override
  State<PermissionOnboardingScreen> createState() =>
      _PermissionOnboardingScreenState();
}

class _PermissionRowData {
  const _PermissionRowData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.granted,
    required this.onEnable,
    this.required = true,
    this.onSkip,
    this.skipLabel,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool granted;
  final Future<void> Function() onEnable;
  final bool required;
  final Future<void> Function()? onSkip;
  final String? skipLabel;
}

class _PermissionOnboardingScreenState extends State<PermissionOnboardingScreen>
    with WidgetsBindingObserver {
  bool _usageOk = false;
  bool _cameraOk = false;
  bool _micOk = false;
  bool _screenCaptureOk = false;
  bool _accessibilityOk = false;
  bool _overlayOk = false;
  bool _screenCaptureSkipped = false;
  bool _refreshing = false;

  static const _accent = Color(0xFF6F39E8);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_completeSuccess()));
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_bootstrap()));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshAll());
    }
  }

  Future<void> _bootstrap() async {
    if (await TrackingPermissionsGate.isFullyGranted()) {
      if (!mounted) return;
      if (widget.embeddedInAppBootstrap) {
        widget.onBootstrapGranted?.call();
      } else {
        Navigator.of(context).pop(true);
      }
      return;
    }
    _screenCaptureSkipped =
        await TrackingPermissionPrefs.isScreenCaptureSkipped();
    await _refreshAll();
  }

  Future<void> _refreshAll() async {
    if (kIsWeb) return;
    setState(() => _refreshing = true);
    try {
      final usage = await ScreenTimeService.instance.hasUsageAccess();
      final cam = await Permission.camera.status;
      final mic = await Permission.microphone.status;
      final capture = await ScreenTimeService.instance.hasScreenCapturePermission();
      final a11y = await ScreenTimeService.instance.hasAccessibilityService();
      final overlay = await ScreenTimeService.instance.hasOverlayPermission();
      if (!mounted) return;
      setState(() {
        _usageOk = usage;
        _cameraOk = cam.isGranted;
        _micOk = mic.isGranted;
        _screenCaptureOk = capture;
        _accessibilityOk = a11y;
        _overlayOk = overlay;
      });
      if (capture) {
        await _persistPartialGrant(screenCapture: true);
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _openUsage() async {
    await ScreenTimeService.instance.openUsageSettings();
  }

  Future<void> _openAppPermissions() async {
    await openAppSettings();
  }

  Future<void> _openScreenCapture() async {
    if (!mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Screen recording'),
        content: const Text(
          'This is not in App permissions. Android will show a separate '
          'system dialog — tap Start now or Allow to enable short wellness clips.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: _accent),
            child: const Text('Open system prompt'),
          ),
        ],
      ),
    );
    if (go != true) return;
    await ScreenTimeService.instance.launchScreenCaptureConsent();
  }

  Future<void> _skipScreenCapture() async {
    await TrackingPermissionPrefs.markScreenCaptureSkipped();
    if (!mounted) return;
    setState(() => _screenCaptureSkipped = true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Screen recording skipped — you can enable it later from Home or when a feature needs it.',
          ),
        ),
      );
    }
  }

  Future<void> _openAccessibility() async {
    await ScreenTimeService.instance.openAccessibilitySettings();
  }

  Future<void> _openOverlay() async {
    await ScreenTimeService.instance.openManageOverlaySettings();
  }

  Future<void> _persistPartialGrant({
    bool? usage,
    bool? camera,
    bool? screenCapture,
    bool? accessibility,
  }) async {
    final cam = await Permission.camera.status;
    await TrackingPermissionPrefs.saveGrantSnapshot(
      usage: usage ?? _usageOk,
      camera: camera ?? cam.isGranted,
      screenCapture:
          screenCapture ??
          _screenCaptureOk ||
              await ScreenTimeService.instance.hasScreenCapturePermission(),
      accessibility: accessibility ?? _accessibilityOk,
    );
  }

  Future<void> _completeSuccess() async {
    final cam = await Permission.camera.status;
    await TrackingPermissionPrefs.saveGrantSnapshot(
      usage: _usageOk || await ScreenTimeService.instance.hasUsageAccess(),
      camera: cam.isGranted,
      screenCapture: _screenCaptureOk ||
          await ScreenTimeService.instance.hasScreenCapturePermission(),
      accessibility: _accessibilityOk ||
          await ScreenTimeService.instance.hasAccessibilityService(),
      screenCaptureSkipped: _screenCaptureSkipped,
    );

    if (widget.embeddedInAppBootstrap) {
      widget.onBootstrapGranted?.call();
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _abandon() async {
    if (widget.embeddedInAppBootstrap) {
      widget.onBootstrapAbandon?.call();
      return;
    }
    if (mounted) Navigator.of(context).pop(false);
  }

  bool _requiredSatisfied() =>
      _usageOk &&
      _cameraOk &&
      _accessibilityOk &&
      (_screenCaptureOk || _screenCaptureSkipped);

  Future<void> _verifyAndFinish() async {
    await _refreshAll();
    if (!_usageOk || !_cameraOk) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Turn on Usage access and Camera to continue.'),
        ),
      );
      return;
    }
    if (!_screenCaptureOk && !_screenCaptureSkipped) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enable screen recording or tap Skip on that row to continue without it.',
          ),
        ),
      );
      return;
    }
    if (!_accessibilityOk) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enable the MindSync accessibility service in Settings.',
          ),
        ),
      );
      return;
    }
    if (!_micOk && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Microphone is recommended for video scans — you can enable it later in app settings.',
          ),
        ),
      );
    }
    await _completeSuccess();
  }

  List<_PermissionRowData> _rows() {
    return [
      _PermissionRowData(
        title: 'Usage access',
        subtitle: 'Real screen time and per-app usage from Android',
        icon: Icons.hourglass_bottom_rounded,
        granted: _usageOk,
        onEnable: _openUsage,
        required: true,
      ),
      _PermissionRowData(
        title: 'Camera',
        subtitle: 'Face scan, mood capture, and unlock verification',
        icon: Icons.camera_alt_outlined,
        granted: _cameraOk,
        onEnable: _openAppPermissions,
        required: true,
      ),
      _PermissionRowData(
        title: 'Microphone',
        subtitle: 'Audio when recording face videos',
        icon: Icons.mic_none_rounded,
        granted: _micOk,
        onEnable: _openAppPermissions,
        required: false,
      ),
      _PermissionRowData(
        title: 'Screen recording',
        subtitle:
            'Optional — system screen-capture prompt (Start now), not App info',
        icon: Icons.screen_share_outlined,
        granted: _screenCaptureOk,
        onEnable: _openScreenCapture,
        required: false,
        onSkip: _screenCaptureOk ? null : _skipScreenCapture,
        skipLabel: 'Skip for now',
      ),
      _PermissionRowData(
        title: 'Accessibility',
        subtitle: 'Detect video apps and optional parent blocking',
        icon: Icons.accessibility_new_rounded,
        granted: _accessibilityOk,
        onEnable: _openAccessibility,
        required: true,
      ),
      if (Platform.isAndroid || Platform.isIOS)
        _PermissionRowData(
          title: 'Display over other apps',
          subtitle: 'Optional — block overlay when parent control is on',
          icon: Icons.layers_outlined,
          granted: _overlayOk,
          onEnable: _openOverlay,
          required: false,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final rows = _rows();

    return PopScope(
      canPop: !widget.embeddedInAppBootstrap,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Leave setup?'),
            content: const Text(
              'MindSync needs these permissions for screen time, video capture, and wellness features.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Stay'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Leave'),
              ),
            ],
          ),
        );
        if (leave == true && mounted) await _abandon();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F4FA),
        appBar: AppBar(
          title: const Text('App permissions'),
          backgroundColor: const Color(0xFFF3F4FA),
          automaticallyImplyLeading: !widget.embeddedInAppBootstrap,
          actions: [
            if (_refreshing)
              const Padding(
                padding: EdgeInsets.only(right: 16),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              IconButton(
                onPressed: _refreshAll,
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Refresh status',
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
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
                    'Tap a toggle to open the matching setting on your phone. '
                    'When you allow access there, the toggle turns on here.',
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
            ...rows.map((row) => _PermissionToggleTile(
                  data: row,
                  accent: _accent,
                  onToggle: () async {
                    await row.onEnable();
                  },
                )),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _requiredSatisfied() ? _verifyAndFinish : null,
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text('Continue to MindSync'),
            ),
            if (!_requiredSatisfied()) ...[
              const SizedBox(height: 8),
              Text(
                'Required: usage access, camera, and accessibility. Screen recording is optional.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
            if (widget.embeddedInAppBootstrap) ...[
              const SizedBox(height: 20),
              Center(
                child: TextButton(
                  onPressed: _abandon,
                  child: const Text('Sign out'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PermissionToggleTile extends StatelessWidget {
  const _PermissionToggleTile({
    required this.data,
    required this.accent,
    required this.onToggle,
  });

  final _PermissionRowData data;
  final Color accent;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
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
                          if (data.required)
                            Text(
                              'Required',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: accent.withValues(alpha: 0.85),
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
                      if (data.onSkip != null && data.skipLabel != null) ...[
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () => data.onSkip!(),
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              data.skipLabel!,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: accent,
                              ),
                            ),
                          ),
                        ),
                      ],
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
