import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/local_auth_service.dart';
import '../../services/screen_time_service.dart';
import '../../services/tracking_permissions_gate.dart';
import '../../services/tracking_permission_prefs.dart';
import '../../widgets/permission_setup_panel.dart';

/// Post-login permission onboarding. Usage access is the only required permission.
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

class _PermissionOnboardingScreenState extends State<PermissionOnboardingScreen> {
  final GlobalKey<PermissionSetupPanelState> _panelKey =
      GlobalKey<PermissionSetupPanelState>();
  bool _refreshing = false;
  bool _usageOk = false;

  static const _accent = PermissionSetupPanelState.accent;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_completeSuccess()));
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_bootstrap()));
  }

  Future<void> _bootstrap() async {
    final userId = await widget.auth.getStoredUserId();
    await ScreenTimeService.instance.persistDevicePermissionGrants(userId: userId);
    if (await TrackingPermissionsGate.isFullyGranted(userId)) {
      if (!mounted) return;
      if (widget.embeddedInAppBootstrap) {
        widget.onBootstrapGranted?.call();
      } else {
        Navigator.of(context).pop(true);
      }
    }
  }

  Future<void> _completeSuccess() async {
    if (kIsWeb) {
      await TrackingPermissionPrefs.saveGrantSnapshot(
        usage: true,
        camera: true,
        screenCapture: false,
        accessibility: false,
        markSetupDone: true,
      );
    } else {
      await _panelKey.currentState?.persistGrantSnapshot(markSetupDone: true);
    }

    if (widget.embeddedInAppBootstrap) {
      widget.onBootstrapGranted?.call();
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _skipToHome() async {
    await _panelKey.currentState?.persistGrantSnapshot(markSetupDone: true);
    await _completeSuccess();
  }

  Future<void> _abandon() async {
    if (widget.embeddedInAppBootstrap) {
      widget.onBootstrapAbandon?.call();
      return;
    }
    if (mounted) Navigator.of(context).pop(false);
  }

  Future<void> _verifyAndContinue() async {
    await _panelKey.currentState?.refreshAll();
    final panel = _panelKey.currentState;
    if (panel == null) return;

    if (!panel.usageOk) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Turn on Usage access to track screen time, or tap Skip to continue without it.',
          ),
        ),
      );
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

    final canContinue = _usageOk;

    return PopScope(
      canPop: !widget.embeddedInAppBootstrap,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Leave setup?'),
            content: const Text(
              'You can finish permissions later from More → Permissions. '
              'Screen time needs usage access when you are ready.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Stay'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Skip for now'),
              ),
            ],
          ),
        );
        if (leave == true && mounted) await _skipToHome();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F4FA),
        appBar: AppBar(
          title: const Text('App permissions'),
          backgroundColor: const Color(0xFFF3F4FA),
          automaticallyImplyLeading: !widget.embeddedInAppBootstrap,
          actions: [
            TextButton(
              onPressed: _skipToHome,
              child: const Text(
                'Skip',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _accent,
                ),
              ),
            ),
            if (_refreshing)
              const Padding(
                padding: EdgeInsets.only(right: 8),
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
                onPressed: () => _panelKey.currentState?.refreshAll(),
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Refresh status',
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            PermissionSetupPanel(
              key: _panelKey,
              onRefreshingChanged: (v) {
                if (mounted) setState(() => _refreshing = v);
              },
              onPermissionsChanged: () {
                if (!mounted) return;
                setState(() {
                  _usageOk = _panelKey.currentState?.usageOk ?? false;
                });
              },
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: canContinue ? _verifyAndContinue : null,
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text('Continue to MindSync'),
            ),
            if (!canContinue) ...[
              const SizedBox(height: 8),
              Text(
                'Usage access enables screen time tracking. Use Skip to open the app without it.',
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
