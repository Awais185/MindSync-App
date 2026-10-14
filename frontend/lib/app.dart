import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'route_observers.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/permission_onboarding_screen.dart';
import 'screens/auth/disclaimer_screen.dart';
import 'screens/auth/welcome_screen.dart';
import 'screens/main_shell_screen.dart';
import 'services/app_public_service.dart';
import 'services/local_auth_service.dart';
import 'services/plan_access_service.dart';
import 'services/screen_time_service.dart';
import 'services/subscription_service.dart';
import 'services/user_session_cache.dart';
import 'services/tracking_permissions_gate.dart';

class MindSyncScrollBehavior extends MaterialScrollBehavior {
  const MindSyncScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  }

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.unknown,
  };
}

enum _LaunchTarget { splash, welcome, disclaimer, login, permissionSetup, main }

class MindSyncApp extends StatefulWidget {
  const MindSyncApp({super.key});

  @override
  State<MindSyncApp> createState() => _MindSyncAppState();
}

class _MindSyncAppState extends State<MindSyncApp> with WidgetsBindingObserver {
  static const _kOnboardingDone = 'mindsync.onboarding_complete';
  static const _kDisclaimerAccepted = 'mindsync.disclaimer_accepted';

  _LaunchTarget _target = _LaunchTarget.splash;
  final LocalAuthService _auth = LocalAuthService();
  AuthProfile? _pendingProfile;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppPublicService.instance.loadBranding();
    AppPublicService.instance.loadSubscriptionPlans();
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_target != _LaunchTarget.main) return;
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_syncSessionAfterResume());
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        unawaited(_ensureBackgroundTrackingOnBackground());
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Keep native trackers running when the user switches to another app.
  Future<void> _ensureBackgroundTrackingOnBackground() async {
    try {
      await ScreenTimeService.instance.keepAliveForBackground();
    } catch (_) {}
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final onboardingDone = prefs.getBool(_kOnboardingDone) ?? false;
    final disclaimerAccepted = prefs.getBool(_kDisclaimerAccepted) ?? false;

    final profile = await _auth.restoreSessionIfPossible();

    if (!mounted) return;

    if (profile != null) {
      await _applyAuthenticatedProfile(profile);
      await SubscriptionService.instance.hydrateFromCache();
      await PlanAccessService.instance.refresh();
      setState(() => _target = _LaunchTarget.main);
      return;
    }

    setState(() {
      if (!onboardingDone) {
        _target = _LaunchTarget.welcome;
      } else if (!disclaimerAccepted) {
        _target = _LaunchTarget.disclaimer;
      } else {
        _target = _LaunchTarget.login;
      }
    });
  }

  Future<void> _applyAuthenticatedProfile(AuthProfile profile) async {
    try {
      await _auth.tryRefreshAccessToken();
    } catch (_) {
      // Offline / transient — keep local session and still enable tracking if permitted.
    }
    await SubscriptionService.instance.hydrateFromCache();
    ScreenTimeService.instance.setFaceVerified(profile.faceEnrolled);
    ScreenTimeService.instance.setFaceMatchPercent(50);
    final userId = await _auth.getStoredUserId();
    await ScreenTimeService.instance.setTrackingUser(userId);
    await TrackingPermissionsGate.startScreenTimeIfPermitted();
    await ScreenTimeService.instance.flushMidnightScreenTimePending();
    unawaited(UserSessionCache.onUserSessionReady());
  }

  Future<void> _finishPermissionBootstrap(AuthProfile profile) async {
    await _applyAuthenticatedProfile(profile);
    if (!mounted) return;
    setState(() {
      _pendingProfile = null;
      _target = _LaunchTarget.main;
    });
  }

  Future<void> _abandonPermissionBootstrap() async {
    await _auth.logout();
    ScreenTimeService.instance.stop();
    await ScreenTimeService.instance.clearTrackingUser();
    ScreenTimeService.instance.setFaceVerified(false);
    if (!mounted) return;
    setState(() {
      _pendingProfile = null;
      _target = _LaunchTarget.login;
    });
  }

  Future<void> _syncSessionAfterResume() async {
    // Do not reset navigation to home/login on resume — only refresh session + trackers.
    try {
      await _auth.tryRefreshAccessToken();
    } catch (_) {}
    final profile = await _auth.fetchCurrentUserProfile();
    if (!mounted) return;
    if (profile != null) {
      ScreenTimeService.instance.setFaceVerified(profile.faceEnrolled);
      ScreenTimeService.instance.setFaceMatchPercent(50);
      await ScreenTimeService.instance.setTrackingUser(await _auth.getStoredUserId());
    }
    await TrackingPermissionsGate.startScreenTimeIfPermitted();
    await ScreenTimeService.instance.flushMidnightScreenTimePending();
    await ScreenTimeService.instance.resumeFromBackground();
    unawaited(UserSessionCache.onUserSessionReady());
  }

  Future<void> _completeWelcome() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOnboardingDone, true);
    if (mounted) {
      setState(() => _target = _LaunchTarget.disclaimer);
    }
  }

  Future<void> _acceptDisclaimer() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDisclaimerAccepted, true);
    if (mounted) {
      setState(() => _target = _LaunchTarget.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget home = const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );

    switch (_target) {
      case _LaunchTarget.splash:
        break;
      case _LaunchTarget.welcome:
        home = WelcomeScreen(
          onGetStarted: () {
            unawaited(_completeWelcome());
          },
        );
        break;
      case _LaunchTarget.disclaimer:
        home = DisclaimerScreen(
          onAccepted: () {
            unawaited(_acceptDisclaimer());
          },
        );
        break;
      case _LaunchTarget.login:
        home = const LoginScreen();
        break;
      case _LaunchTarget.permissionSetup:
        home = PermissionOnboardingScreen(
          auth: _auth,
          embeddedInAppBootstrap: true,
          onBootstrapGranted: () {
            final p = _pendingProfile;
            if (p == null || !mounted) return;
            unawaited(_finishPermissionBootstrap(p));
          },
          onBootstrapAbandon: () {
            if (!mounted) return;
            unawaited(_abandonPermissionBootstrap());
          },
        );
        break;
      case _LaunchTarget.main:
        home = const MainShellScreen();
        break;
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MindSync',
      restorationScopeId: 'mindsync_app',
      navigatorObservers: [mindSyncRouteObserver],
      scrollBehavior: const MindSyncScrollBehavior(),
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF6F6FA),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6F39E8)),
        fontFamily: 'Roboto',
        textTheme: ThemeData.light().textTheme.apply(
          bodyColor: const Color(0xFF1F2330),
          displayColor: const Color(0xFF1F2330),
        ),
        dividerColor: const Color(0xFFDADDE7),
        useMaterial3: true,
      ),
      home: home,
    );
  }
}
