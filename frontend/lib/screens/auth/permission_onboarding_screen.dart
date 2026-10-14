import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/local_auth_service.dart';
import '../../services/screen_time_service.dart';
import '../../services/tracking_permissions_gate.dart';
import '../../services/tracking_permission_prefs.dart';

/// Step-by-step permission setup before tracking can run.
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

class _PermissionOnboardingScreenState extends State<PermissionOnboardingScreen>
    with WidgetsBindingObserver {
  static const _totalSteps = 5;

  int _step = 0;
  bool _usageOk = false;
  bool _screenCaptureOk = false;
  bool _accessibilityOk = false;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_completeSuccess()));
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_bootstrapPermissions()));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_onAppResumed());
    }
  }

  Future<void> _onAppResumed() async {
    await _refreshChecks();
  }

  /// Skip the flow when permissions were saved earlier; otherwise open the first missing step.
  Future<void> _bootstrapPermissions() async {
    if (await TrackingPermissionsGate.isFullyGranted()) {
      if (!mounted) return;
      if (widget.embeddedInAppBootstrap) {
        widget.onBootstrapGranted?.call();
      } else {
        Navigator.of(context).pop(true);
      }
      return;
    }
    await _refreshChecks();
    if (!mounted) return;
    final cam = await Permission.camera.status;
    var step = 0;
    if (_usageOk) {
      step = cam.isGranted ? 2 : 1;
      if (cam.isGranted && _screenCaptureOk) {
        step = _accessibilityOk ? 4 : 3;
      }
    }
    setState(() => _step = step);
  }

  Future<void> _refreshChecks() async {
    final usage = await ScreenTimeService.instance.hasUsageAccess();
    final capture = await ScreenTimeService.instance.hasScreenCapturePermission();
    final a11y = await ScreenTimeService.instance.hasAccessibilityService();
    if (!mounted) return;
    setState(() {
      _usageOk = usage;
      _screenCaptureOk = capture;
      _accessibilityOk = a11y;
    });
    if (capture) {
      await _persistPartialGrant(screenCapture: true);
    }
  }

  Future<void> _openUsageSettings() async {
    await ScreenTimeService.instance.openUsageSettings();
  }

  Future<void> _requestRuntimeMediaBatch() async {
    setState(() => _busy = true);
    try {
      if (Platform.isAndroid) {
        final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
        final perms = <Permission>[
          Permission.camera,
          Permission.microphone,
        ];
        if (sdk >= 33) {
          perms.add(Permission.photos);
          perms.add(Permission.videos);
          perms.add(Permission.notification);
        } else {
          perms.add(Permission.storage);
        }
        final pending = <Permission>[];
        for (final perm in perms) {
          if (!(await perm.status).isGranted) {
            pending.add(perm);
          }
        }
        if (pending.isNotEmpty) {
          await pending.request();
        }
      } else if (Platform.isIOS) {
        final iosPerms = [
          Permission.camera,
          Permission.microphone,
          Permission.photos,
        ];
        final pending = <Permission>[];
        for (final perm in iosPerms) {
          if (!(await perm.status).isGranted) {
            pending.add(perm);
          }
        }
        if (pending.isNotEmpty) {
          await pending.request();
        }
      } else {
        if (!(await Permission.camera.status).isGranted) {
          await Permission.camera.request();
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestScreenCapture() async {
    setState(() => _busy = true);
    try {
      final ok = await ScreenTimeService.instance.ensureScreenCapturePermission();
      if (!mounted) return;
      setState(() => _screenCaptureOk = ok);
      if (ok) {
        await _persistPartialGrant(screenCapture: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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

  Future<void> _openAccessibility() async {
    await ScreenTimeService.instance.openAccessibilitySettings();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await _refreshChecks();
  }

  Future<void> _maybeOpenOverlaySettings() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (await ScreenTimeService.instance.hasOverlayPermission()) return;
    if (!mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Display over other apps'),
        content: const Text(
          'Optional: lets MindSync show a block screen when you actively restrict an app. '
          'This does not block apps by itself. You can skip and enable it later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Skip'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Open settings'),
          ),
        ],
      ),
    );
    if (go == true && mounted) {
      await ScreenTimeService.instance.openManageOverlaySettings();
    }
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

  Future<void> _verifyAndFinish() async {
    await _refreshChecks();
    final usage = await ScreenTimeService.instance.hasUsageAccess();
    final cam = await Permission.camera.status;
    if (!mounted) return;
    if (!usage || !cam.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Usage access and Camera are required.'),
        ),
      );
      setState(() => _step = 0);
      return;
    }
    var screenOk = _screenCaptureOk ||
        await ScreenTimeService.instance.hasScreenCapturePermission();
    if (!screenOk) {
      final granted =
          await ScreenTimeService.instance.ensureScreenCapturePermission();
      screenOk = granted;
      if (mounted) setState(() => _screenCaptureOk = granted);
      if (granted) {
        await _persistPartialGrant(screenCapture: true);
      }
    }
    if (!screenOk) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Tap "Allow screen recording" and choose Start now on the system dialog.',
          ),
        ),
      );
      setState(() => _step = 2);
      return;
    }
    if (!_accessibilityOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enable the MindSync accessibility service to detect video apps automatically.',
          ),
        ),
      );
      setState(() => _step = 3);
      return;
    }
    await _completeSuccess();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

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
        appBar: AppBar(
          title: const Text('Allow permissions'),
          automaticallyImplyLeading: !widget.embeddedInAppBootstrap,
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Step ${_step + 1} of $_totalSteps',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 12),
            if (_step == 0) ...[
              Text('Usage access', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text(
                'Required for real screen time and per-app usage from Android (not estimated in-app).',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _openUsageSettings,
                icon: const Icon(Icons.settings),
                label: const Text('Open usage access settings'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _refreshChecks,
                icon: const Icon(Icons.refresh),
                label: Text(_usageOk ? 'Usage access: granted' : 'I enabled it — refresh'),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: (!_usageOk || _busy) ? null : () => setState(() => _step = 1),
                child: const Text('Continue'),
              ),
            ],
            if (_step == 1) ...[
              Text('Camera & microphone', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text(
                'Used for mood capture, face wellness clips, and optional background analysis.',
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () async {
                        await _requestRuntimeMediaBatch();
                        if (!mounted) return;
                        setState(() => _step = 2);
                      },
                child: _busy
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Allow app permissions'),
              ),
            ],
            if (_step == 2) ...[
              Text('Screen recording', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text(
                'Android will show a system dialog (not in App settings). '
                'Tap Allow below, then choose Start now or Allow on that popup. '
                'This is required to save 30-second video clips while you use social apps.',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _requestScreenCapture,
                icon: const Icon(Icons.screen_share),
                label: Text(
                  _screenCaptureOk
                      ? 'Screen recording: granted'
                      : 'Allow screen recording',
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _refreshChecks,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh status'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => ScreenTimeService.instance.openAppInfoSettings(),
                child: const Text('Open MindSync app info (optional)'),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: (!_screenCaptureOk || _busy)
                    ? null
                    : () => setState(() => _step = 3),
                child: const Text('Continue'),
              ),
            ],
            if (_step == 3) ...[
              Text('Video app detection & app blocking', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text(
                'Turn on the MindSync accessibility service so video apps can be detected '
                'for monitoring. App blocking only runs when you enable it in Parent Control.',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _openAccessibility,
                icon: const Icon(Icons.accessibility_new),
                label: Text(
                  _accessibilityOk
                      ? 'Accessibility: enabled'
                      : 'Open accessibility settings',
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _refreshChecks,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh status'),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: (!_accessibilityOk || _busy)
                    ? null
                    : () => setState(() => _step = 4),
                child: const Text('Continue'),
              ),
            ],
            if (_step == 4) ...[
              Text('Optional: overlay', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text(
                'Optional. Only used when you turn on app blocking in Parent Control — '
                'social apps work normally until then.',
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        try {
                          await _maybeOpenOverlaySettings();
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      },
                child: const Text('Configure overlay (optional)'),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _verifyAndFinish,
                child: const Text('Finish & start MindSync'),
              ),
            ],
            if (widget.embeddedInAppBootstrap) ...[
              const SizedBox(height: 32),
              Center(
                child: TextButton(
                  onPressed: _busy ? null : _abandon,
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
