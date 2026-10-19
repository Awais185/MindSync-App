import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../models/late_night_sleep_snapshot.dart';
import '../utils/resilient_http.dart';
import 'parental_control_service.dart';
import 'tracking_permission_prefs.dart';
import 'web_tab_screen_time.dart';
import 'home_sleep_sync_service.dart';
import 'wellness_dashboard_service.dart';

class AppUsageItem {
  const AppUsageItem({
    required this.packageName,
    required this.appName,
    required this.durationSeconds,
    this.iconPngBase64,
    this.totalForegroundMs,
  });

  final String packageName;
  final String appName;
  final int durationSeconds;
  final String? iconPngBase64;

  /// When set (e.g. from native rolling usage), used for ordering and smoother totals.
  final int? totalForegroundMs;

  int get sortKeyMs => totalForegroundMs ?? (durationSeconds * 1000);
}

class ScreenTimeSnapshot {
  const ScreenTimeSnapshot({
    required this.daySeconds,
    required this.weekSeconds,
    required this.monthSeconds,
    required this.socialSeconds,
    required this.videoSeconds,
    required this.topApps,
    required this.recordingActive,
    required this.activeVideoPlatform,
    required this.lastVideoUploadError,
    required this.screenCaptureGranted,
    required this.foregroundAppName,
    required this.foregroundPackage,
    required this.foregroundAppTodaySeconds,
    required this.foregroundIconPngBase64,
    required this.analyticsDayBarHeights,
    required this.analyticsWeekBarHeights,
    required this.analyticsMonthBarHeights,
    required this.usageStatsGranted,
    required this.nativeTrackerConfigured,
    required this.faceReactionRecording,
    required this.faceReactionCooldownUntilMs,
    required this.faceReactionLastError,
    this.lateNightWeekSeconds = 0,
    this.lateNightOpensWeek = 0,
    this.lateNightByDaySeconds = _lateNightByDayEmpty,
    this.lateNightTopApps = const <AppUsageItem>[],
    this.lateNightSleep = LateNightSleepSnapshot.empty,
  });

  final int daySeconds;
  final int weekSeconds;
  final int monthSeconds;
  final int socialSeconds;
  final int videoSeconds;
  final List<AppUsageItem> topApps;
  final bool recordingActive;
  final String activeVideoPlatform;
  final String lastVideoUploadError;
  final bool screenCaptureGranted;
  /// Last reported foreground app from backend / native.
  final String foregroundAppName;
  final String foregroundPackage;
  final int foregroundAppTodaySeconds;
  /// Raw PNG base64 (Android) for current foreground app icon.
  final String foregroundIconPngBase64;
  final List<double> analyticsDayBarHeights;
  final List<double> analyticsWeekBarHeights;
  final List<double> analyticsMonthBarHeights;

  /// Android Usage Access granted; [daySeconds] / week / month come from the OS.
  final bool usageStatsGranted;

  /// Native tracker has token + user id (device-side sync enabled).
  final bool nativeTrackerConfigured;

  /// Front-camera OpenFace clip (Android background tracker).
  final bool faceReactionRecording;

  /// Epoch ms after which another face clip may start (30 min cooldown).
  final int faceReactionCooldownUntilMs;

  /// Last face-reaction pipeline error (JSON or plain text).
  final String faceReactionLastError;

  /// Screen time between 22:00–06:00 local (last 7 calendar days), from Android UsageEvents.
  final int lateNightWeekSeconds;

  /// Approximate foreground opens / app switches during late-night windows (7 days).
  final int lateNightOpensWeek;

  /// Late-night seconds per calendar day (oldest → newest), length 7.
  final List<int> lateNightByDaySeconds;

  /// Top apps by late-night foreground time (7 days).
  final List<AppUsageItem> lateNightTopApps;

  /// Screen-on late-night activity & estimated sleep (22:00–06:00), device tracker.
  final LateNightSleepSnapshot lateNightSleep;

  static const List<int> _lateNightByDayEmpty = <int>[
    0,
    0,
    0,
    0,
    0,
    0,
    0,
  ];

  /// Neutral bar heights when there is no real distribution data (not decorative).
  static final List<double> analyticsBarsNoData =
      List<double>.unmodifiable(List<double>.filled(7, 8.0));

  static const empty = ScreenTimeSnapshot(
    daySeconds: 0,
    weekSeconds: 0,
    monthSeconds: 0,
    socialSeconds: 0,
    videoSeconds: 0,
    topApps: <AppUsageItem>[],
    recordingActive: false,
    activeVideoPlatform: '',
    lastVideoUploadError: '',
    screenCaptureGranted: false,
    foregroundAppName: '',
    foregroundPackage: '',
    foregroundAppTodaySeconds: 0,
    foregroundIconPngBase64: '',
    analyticsDayBarHeights: [],
    analyticsWeekBarHeights: [],
    analyticsMonthBarHeights: [],
    usageStatsGranted: false,
    nativeTrackerConfigured: false,
    faceReactionRecording: false,
    faceReactionCooldownUntilMs: 0,
    faceReactionLastError: '',
    lateNightWeekSeconds: 0,
    lateNightOpensWeek: 0,
    lateNightByDaySeconds: _lateNightByDayEmpty,
    lateNightTopApps: <AppUsageItem>[],
    lateNightSleep: LateNightSleepSnapshot.empty,
  );

  ScreenTimeSnapshot copyWith({
    int? daySeconds,
    int? weekSeconds,
    int? monthSeconds,
    int? socialSeconds,
    int? videoSeconds,
    List<AppUsageItem>? topApps,
    bool? recordingActive,
    String? activeVideoPlatform,
    String? lastVideoUploadError,
    bool? screenCaptureGranted,
    String? foregroundAppName,
    String? foregroundPackage,
    int? foregroundAppTodaySeconds,
    String? foregroundIconPngBase64,
    List<double>? analyticsDayBarHeights,
    List<double>? analyticsWeekBarHeights,
    List<double>? analyticsMonthBarHeights,
    bool? usageStatsGranted,
    bool? nativeTrackerConfigured,
    bool? faceReactionRecording,
    int? faceReactionCooldownUntilMs,
    String? faceReactionLastError,
    int? lateNightWeekSeconds,
    int? lateNightOpensWeek,
    List<int>? lateNightByDaySeconds,
    List<AppUsageItem>? lateNightTopApps,
    LateNightSleepSnapshot? lateNightSleep,
  }) {
    return ScreenTimeSnapshot(
      daySeconds: daySeconds ?? this.daySeconds,
      weekSeconds: weekSeconds ?? this.weekSeconds,
      monthSeconds: monthSeconds ?? this.monthSeconds,
      socialSeconds: socialSeconds ?? this.socialSeconds,
      videoSeconds: videoSeconds ?? this.videoSeconds,
      topApps: topApps ?? this.topApps,
      recordingActive: recordingActive ?? this.recordingActive,
      activeVideoPlatform: activeVideoPlatform ?? this.activeVideoPlatform,
      lastVideoUploadError: lastVideoUploadError ?? this.lastVideoUploadError,
      screenCaptureGranted: screenCaptureGranted ?? this.screenCaptureGranted,
      foregroundAppName: foregroundAppName ?? this.foregroundAppName,
      foregroundPackage: foregroundPackage ?? this.foregroundPackage,
      foregroundAppTodaySeconds:
          foregroundAppTodaySeconds ?? this.foregroundAppTodaySeconds,
      foregroundIconPngBase64:
          foregroundIconPngBase64 ?? this.foregroundIconPngBase64,
      analyticsDayBarHeights:
          analyticsDayBarHeights ?? this.analyticsDayBarHeights,
      analyticsWeekBarHeights:
          analyticsWeekBarHeights ?? this.analyticsWeekBarHeights,
      analyticsMonthBarHeights:
          analyticsMonthBarHeights ?? this.analyticsMonthBarHeights,
      usageStatsGranted: usageStatsGranted ?? this.usageStatsGranted,
      nativeTrackerConfigured:
          nativeTrackerConfigured ?? this.nativeTrackerConfigured,
      faceReactionRecording: faceReactionRecording ?? this.faceReactionRecording,
      faceReactionCooldownUntilMs:
          faceReactionCooldownUntilMs ?? this.faceReactionCooldownUntilMs,
      faceReactionLastError: faceReactionLastError ?? this.faceReactionLastError,
      lateNightWeekSeconds: lateNightWeekSeconds ?? this.lateNightWeekSeconds,
      lateNightOpensWeek: lateNightOpensWeek ?? this.lateNightOpensWeek,
      lateNightByDaySeconds:
          lateNightByDaySeconds ?? this.lateNightByDaySeconds,
      lateNightTopApps: lateNightTopApps ?? this.lateNightTopApps,
      lateNightSleep: lateNightSleep ?? this.lateNightSleep,
    );
  }
}

class ScreenTimeService {
  ScreenTimeService._() {
    _ensureLifecycleObserver();
  }

  static final ScreenTimeService instance = ScreenTimeService._();
  static const MethodChannel _channel = MethodChannel('mindsync/screen_time');

  final ValueNotifier<ScreenTimeSnapshot> snapshot =
      ValueNotifier<ScreenTimeSnapshot>(ScreenTimeSnapshot.empty);
  /// Smoothed “today” seconds: OS anchor from [getTodayScreenTimeMs] plus elapsed wall time between polls.
  final ValueNotifier<int> todayLiveDisplaySeconds = ValueNotifier<int>(0);
  /// Per-login session total from native (starts at 0 on each login).
  final ValueNotifier<int> sessionDisplaySeconds = ValueNotifier<int>(0);
  final ValueNotifier<List<AppUsageItem>> rollingAppUsage =
      ValueNotifier<List<AppUsageItem>>(const <AppUsageItem>[]);
  final Map<String, AppUsageItem> _rollingMerged = <String, AppUsageItem>{};
  final ValueNotifier<bool> faceVerified = ValueNotifier<bool>(false);
  final ValueNotifier<double> faceMatchPercent = ValueNotifier<double>(0);

  /// Populated from `/api/auth/usage/daily/` and `/api/screen-time/today/` for Home.
  int homeYesterdayDaySeconds = 0;
  int homeBackendSleepSeconds = 0;
  int homeBackendLateNightSeconds = 0;

  Timer? _backendTimer;
  Timer? _osTodayTimer;
  Timer? _smoothTicker;
  Timer? _rollingPoll;
  Timer? _sessionPollTimer;
  Timer? _backgroundMonitorTimer;
  bool _running = false;
  bool _appInBackground = false;
  bool _stickyMonitoringActive = false;
  bool _lifecycleAttached = false;
  ScreenTimeSnapshot? _lastGoodSnapshot;
  String? _currentUserId;
  DateTime? _osTodayAnchorAt;
  int _osTodayAnchorSeconds = 0;
  int _sessionAnchorSeconds = 0;
  DateTime? _sessionAnchorWallAt;
  int _backendDayAnchorSeconds = 0;
  DateTime? _backendDayAnchorAt;

  String get _baseUrl => ApiConfig.baseUrl;

  void _ensureLifecycleObserver() {
    if (_lifecycleAttached || kIsWeb) return;
    _lifecycleAttached = true;
    WidgetsBinding.instance.addObserver(_ScreenTimeLifecycleObserver(this));
  }

  void _onAppLifecycle(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _appInBackground = false;
        _backgroundMonitorTimer?.cancel();
        _backgroundMonitorTimer = null;
        unawaited(resumeFromBackground());
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _appInBackground = true;
        unawaited(keepAliveForBackground());
        _startBackgroundMonitorPoll();
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  bool get isMonitoringActive {
    final data = snapshot.value;
    return data.usageStatsGranted && data.nativeTrackerConfigured;
  }

  ScreenTimeSnapshot _withStableMonitoring(ScreenTimeSnapshot next) {
    final prev = _lastGoodSnapshot ?? snapshot.value;
    final loggedIn = _currentUserId != null && _currentUserId!.isNotEmpty;
    if (!loggedIn) return next;

    final usageGranted = next.usageStatsGranted || prev.usageStatsGranted;
    var nativeConfigured = next.nativeTrackerConfigured ||
        prev.nativeTrackerConfigured ||
        _stickyMonitoringActive;

    if (usageGranted && (nativeConfigured || _appInBackground)) {
      _stickyMonitoringActive = true;
      nativeConfigured = true;
    }

    final stable = next.copyWith(
      usageStatsGranted: usageGranted,
      nativeTrackerConfigured: nativeConfigured,
    );
    if (stable.usageStatsGranted && stable.nativeTrackerConfigured) {
      _lastGoodSnapshot = stable;
    }
    return stable;
  }

  ScreenTimeSnapshot _mergeWithCachedNativeFields(ScreenTimeSnapshot current) {
    final cached = _lastGoodSnapshot ?? snapshot.value;
    if (cached == ScreenTimeSnapshot.empty) return current;
    return current.copyWith(
      usageStatsGranted: current.usageStatsGranted || cached.usageStatsGranted,
      nativeTrackerConfigured:
          current.nativeTrackerConfigured || cached.nativeTrackerConfigured,
      foregroundAppName: current.foregroundAppName.isNotEmpty
          ? current.foregroundAppName
          : cached.foregroundAppName,
      foregroundPackage: current.foregroundPackage.isNotEmpty
          ? current.foregroundPackage
          : cached.foregroundPackage,
      foregroundAppTodaySeconds: current.foregroundAppTodaySeconds > 0
          ? current.foregroundAppTodaySeconds
          : cached.foregroundAppTodaySeconds,
      foregroundIconPngBase64: current.foregroundIconPngBase64.isNotEmpty
          ? current.foregroundIconPngBase64
          : cached.foregroundIconPngBase64,
      topApps: current.topApps.isNotEmpty ? current.topApps : cached.topApps,
      analyticsWeekBarHeights: current.analyticsWeekBarHeights.length >= 7
          ? current.analyticsWeekBarHeights
          : cached.analyticsWeekBarHeights,
    );
  }

  void start() {
    if (_running) return;
    _running = true;
    _syncTrackerContext();
    unawaited(_refresh());
    _backendTimer?.cancel();
    final backendInterval =
        kIsWeb ? const Duration(seconds: 30) : const Duration(seconds: 15);
    _backendTimer = Timer.periodic(
      backendInterval,
      (_) => unawaited(_refresh()),
    );
    _osTodayTimer?.cancel();
    _osTodayTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_refreshOsTodayAnchor()),
    );
    unawaited(_refreshOsTodayAnchor());
    _smoothTicker?.cancel();
    _smoothTicker = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        _tickSessionDisplay();
        _tickTodayLiveDisplay();
      },
    );
    _sessionPollTimer?.cancel();
    _sessionPollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_currentUserId != null && _currentUserId!.isNotEmpty) {
        unawaited(refreshSessionDisplaySeconds());
      }
    });
    if (_currentUserId != null && _currentUserId!.isNotEmpty) {
      unawaited(refreshSessionDisplaySeconds());
    }
    _rollingPoll?.cancel();
    _rollingPoll = Timer.periodic(
      const Duration(seconds: 60),
      (_) => unawaited(refreshRollingAppUsage()),
    );
    unawaited(refreshRollingAppUsage());
    if (kIsWeb) {
      WebTabScreenTime.start((seconds) {
        _webTabSeconds = seconds;
        _tickTodayLiveDisplay();
      });
      _webFlushTimer?.cancel();
      _webFlushTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => unawaited(_flushWebTabSecondsToBackend()),
      );
    }
  }

  /// Called when app returns from background — keeps polling + native service alive.
  Future<void> resumeFromBackground() async {
    await syncScreenCaptureGrant();
    _appInBackground = false;
    if (_currentUserId != null && _currentUserId!.isNotEmpty) {
      if (!_running) {
        start();
      }
      try {
        await _channel.invokeMethod('pingTracker');
      } catch (_) {}
      await _syncTrackerContext();
      await refreshNow();
      await flushMidnightScreenTimePending();
    }
  }

  /// Before MindSync goes to background: push JWT to native + start foreground service.
  Future<void> keepAliveForBackground() async {
    if (kIsWeb) return;
    if (_currentUserId == null || _currentUserId!.isEmpty) return;
    _appInBackground = true;
    if (!_running) {
      start();
    }
    try {
      await _channel.invokeMethod('pingTracker');
    } catch (_) {}
    await _syncTrackerContext();
    await refreshMonitoringStateFromNative();
    _startBackgroundMonitorPoll();
    try {
      await _channel.invokeMethod('pingTracker');
    } catch (_) {}
    _stickyMonitoringActive = true;
    snapshot.value = _withStableMonitoring(snapshot.value);
    try {
      final native = await _pullNativeSnapshot();
      if (native != null) {
        final backend = await _fetchUsageFromBackend();
        var merged = backend != null
            ? _mergeSnapshots(backend, native)
            : native;
        merged = _withStableMonitoring(merged);
        snapshot.value = merged;
        _tickTodayLiveDisplay();
      }
    } catch (_) {
      snapshot.value = _withStableMonitoring(snapshot.value);
    }
  }

  /// Pull native + backend immediately (e.g. after granting permissions or app resume).
  Future<void> refreshNow() => _refresh();

  void stop() {
    _running = false;
    if (kIsWeb) {
      WebTabScreenTime.stop();
      _webFlushTimer?.cancel();
      _webFlushTimer = null;
    }
    _backendTimer?.cancel();
    _backendTimer = null;
    _osTodayTimer?.cancel();
    _osTodayTimer = null;
    _smoothTicker?.cancel();
    _smoothTicker = null;
    _rollingPoll?.cancel();
    _rollingPoll = null;
    _sessionPollTimer?.cancel();
    _sessionPollTimer = null;
    _backgroundMonitorTimer?.cancel();
    _backgroundMonitorTimer = null;
    _sessionAnchorSeconds = 0;
    _sessionAnchorWallAt = null;
  }

  void _startBackgroundMonitorPoll() {
    if (kIsWeb) return;
    _backgroundMonitorTimer?.cancel();
    _backgroundMonitorTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => unawaited(refreshMonitoringStateFromNative()),
    );
    unawaited(refreshMonitoringStateFromNative());
  }

  /// Lightweight read of native FGS state (no backend) while MindSync UI is in background.
  Future<void> refreshMonitoringStateFromNative() async {
    if (kIsWeb) return;
    try {
      final state = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getMonitoringState',
      );
      if (state == null) return;
      final serviceRunning = state['serviceRunning'] == true;
      final trackingConfigured = state['trackingConfigured'] == true;
      final monitoredApp = (state['monitoredAppName'] ?? '').toString();
      final monitoredPkg = (state['monitoredPackage'] ?? '').toString();
      final recordingActive = state['recordingActive'] == true;
      final prev = _lastGoodSnapshot ?? snapshot.value;
      snapshot.value = _withStableMonitoring(
        prev.copyWith(
          nativeTrackerConfigured: serviceRunning || trackingConfigured || prev.nativeTrackerConfigured,
          usageStatsGranted: (state['hasUsageAccess'] == true) || prev.usageStatsGranted,
          recordingActive: recordingActive || prev.recordingActive,
          foregroundAppName: monitoredApp.isNotEmpty
              ? monitoredApp
              : prev.foregroundAppName,
          foregroundPackage: monitoredPkg.isNotEmpty
              ? monitoredPkg
              : prev.foregroundPackage,
        ),
      );
    } catch (_) {}
  }

  /// Home / shell: start polling + native session when permissions and user id exist.
  Future<void> ensureMonitoringForUser(String? userId) async {
    if (!_running) {
      start();
    }
    if (userId != null && userId.isNotEmpty) {
      _currentUserId = userId;
      if (!kIsWeb) {
        await startTrackingSession(userId);
      }
    }
    await _syncTrackerContext();
    if (!kIsWeb) {
      unawaited(refreshSessionDisplaySeconds());
      unawaited(refreshRollingAppUsage());
    }
    unawaited(refreshNow());
    unawaited(persistDevicePermissionGrants(userId: userId));
  }

  /// Saves OS permission state for the logged-in account (per-user keys on device).
  Future<void> persistDevicePermissionGrants({
    String? userId,
    bool? cameraOverride,
    bool markSetupDone = true,
  }) async {
    final id = userId ?? _currentUserId;
    if (kIsWeb) {
      await TrackingPermissionPrefs.saveGrantSnapshot(
        usage: true,
        camera: true,
        screenCapture: false,
        accessibility: false,
        markSetupDone: markSetupDone,
        userId: id,
      );
      return;
    }
    final usage = await hasUsageAccess();
    final camStatus = await Permission.camera.status;
    final camera = cameraOverride ?? camStatus.isGranted;
    final screenCapture = await hasScreenCapturePermission();
    final accessibility = await hasAccessibilityService();
    final setupDone = markSetupDone &&
        (usage ||
            await TrackingPermissionPrefs.isSetupMarkedDone(id) ||
            await TrackingPermissionPrefs.isSetupMarkedDone());
    await TrackingPermissionPrefs.saveGrantSnapshot(
      usage: usage,
      camera: camera,
      screenCapture: screenCapture,
      accessibility: accessibility,
      markSetupDone: setupDone,
      userId: id,
    );
  }

  Future<bool> hasUsageAccess() async {
    if (kIsWeb) return true;
    try {
      final allowed = await _channel.invokeMethod<bool>('hasUsageAccess');
      return allowed ?? false;
    } on MissingPluginException {
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> ensureUsagePermission() async {
    final allowed = await hasUsageAccess();
    if (allowed) return true;
    await openUsageSettings();
    return false;
  }

  /// Reload persisted MediaProjection grant from disk (no system dialog).
  Future<bool> syncScreenCaptureGrant() async {
    if (kIsWeb) return false;
    try {
      final allowed = await _channel.invokeMethod<bool>(
        'syncScreenCaptureGrant',
      );
      final ok = allowed ?? false;
      if (ok) {
        await _notifyNativeScreenCaptureGranted();
      }
      return ok;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Wakes native ScreenRecordingService after a persisted MediaProjection grant loads.
  Future<void> _notifyNativeScreenCaptureGranted() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('notifyScreenCaptureGranted');
    } on MissingPluginException {
      return;
    } catch (_) {}
  }

  Future<bool> hasScreenCapturePermission() async {
    if (kIsWeb) return false;
    try {
      final allowed = await _channel.invokeMethod<bool>(
        'hasScreenCapturePermission',
      );
      return allowed ?? false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Launches the system MediaProjection consent (dedicated activity, not App info).
  Future<void> launchScreenCaptureConsent() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<bool>('launchScreenCaptureConsentActivity');
    } on MissingPluginException {
      return;
    } catch (_) {}
  }

  /// Opens the OS settings screen for screen capture / special access (no in-app dialog).
  Future<void> openScreenRecordingOsSettings() async {
    if (kIsWeb) return;
    try {
      if (Platform.isAndroid) {
        await _channel.invokeMethod('openAppInfoSettings');
      } else if (Platform.isIOS) {
        await openAppSettings();
      }
    } on MissingPluginException {
      await openAppSettings();
    } catch (_) {
      await openAppSettings();
    }
  }

  Future<bool> ensureScreenCapturePermission() async {
    if (kIsWeb) return false;
    if (await hasScreenCapturePermission()) return true;
    await launchScreenCaptureConsent();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await _refresh();
    final ok = await hasScreenCapturePermission();
    if (ok) {
      await _notifyNativeScreenCaptureGranted();
    }
    return ok;
  }

  /// Opens OS settings for screen capture (no in-app consent activity).
  Future<bool> openScreenCaptureSettings() async {
    if (kIsWeb) return false;
    if (await hasScreenCapturePermission()) return true;
    await openScreenRecordingOsSettings();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await _refresh();
    return await hasScreenCapturePermission();
  }

  /// App info only — does not grant screen recording.
  Future<void> openAppInfoSettings() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('openAppInfoSettings');
    } on MissingPluginException {
      return;
    } catch (_) {}
  }

  Future<void> openUsageSettings() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('openUsageAccessSettings');
    } on MissingPluginException {
      return;
    }
  }

  void setFaceVerified(bool verified) {
    faceVerified.value = verified;
    if (verified && faceMatchPercent.value <= 0) {
      faceMatchPercent.value = 80;
    }
    _syncTrackerContext();
    _refresh();
  }

  void setFaceMatchPercent(double percent) {
    faceMatchPercent.value = percent.clamp(0, 100);
    _syncTrackerContext();
  }

  Future<void> _refresh() async {
    try {
      final backendData = await _fetchUsageFromBackend();
      ScreenTimeSnapshot? native;

      if (!kIsWeb) {
        try {
          native = await _pullNativeSnapshot();
        } catch (_) {
          native = null;
        }
      }

      ScreenTimeSnapshot? merged = backendData;
      if (native != null) {
        if (backendData != null) {
          merged = _mergeSnapshots(backendData, native);
        } else {
          merged = native;
        }
      } else if (_appInBackground && merged != null) {
        merged = _mergeWithCachedNativeFields(merged);
      }

      if (merged != null) {
        merged = _withStableMonitoring(merged);
        snapshot.value = merged;
        _maybeSeedOsAnchorFromSnapshot(merged);
        _tickTodayLiveDisplay();
        if (!kIsWeb) {
          await HomeSleepSyncService.instance
              .syncFromDeviceSnapshot(merged.lateNightSleep);
        }
      } else if (_appInBackground && _stickyMonitoringActive) {
        snapshot.value = _withStableMonitoring(snapshot.value);
      }

      if (!kIsWeb || _backendRefreshCount % 2 == 0) {
        await WellnessDashboardService.instance.refreshHome();
      }
      if (!kIsWeb) {
        await flushMidnightScreenTimePending();
        _todayBackendSyncTick++;
        if (_todayBackendSyncTick % 4 == 0) {
          await syncTodayScreenTimeToBackend();
        }
      }
      _backendRefreshCount++;
    } catch (_) {
      if (_stickyMonitoringActive || _appInBackground) {
        snapshot.value = _withStableMonitoring(snapshot.value);
      }
    }
  }

  int _backendRefreshCount = 0;
  int _todayBackendSyncTick = 0;
  int _webTabSeconds = 0;
  int _lastWebFlushSeconds = 0;
  Timer? _webFlushTimer;

  List<double> _sevenBars(List<double> primary, List<double> secondary) {
    if (primary.length >= 7) return List<double>.from(primary.take(7));
    if (secondary.length >= 7) return List<double>.from(secondary.take(7));
    return List<double>.from(ScreenTimeSnapshot.analyticsBarsNoData);
  }

  List<double> _sevenBarsSingle(List<double> v) =>
      _sevenBars(v, const <double>[]);

  ScreenTimeSnapshot _mergeSnapshots(ScreenTimeSnapshot b, ScreenTimeSnapshot n) {
    /// Per-user totals come from Django (JWT-scoped). Device UsageStats are
    /// shared across Android profiles and must not override logged-in totals.
    final trusted = n.usageStatsGranted;
    final useBackendTotals =
        _currentUserId != null && _currentUserId!.isNotEmpty;

    final icons = <String, String?>{};
    for (final a in n.topApps) {
      icons[a.packageName] = a.iconPngBase64;
    }

    List<AppUsageItem> mergedTop;
    if (useBackendTotals && b.topApps.isNotEmpty) {
      mergedTop = b.topApps;
    } else if (trusted && n.topApps.isNotEmpty) {
      mergedTop = n.topApps;
    } else {
      mergedTop = b.topApps
          .map(
            (a) => AppUsageItem(
              packageName: a.packageName,
              appName: a.appName,
              durationSeconds: a.durationSeconds,
              iconPngBase64: icons[a.packageName] ?? a.iconPngBase64,
            ),
          )
          .toList();
      if (mergedTop.isEmpty && n.topApps.isNotEmpty) {
        mergedTop = n.topApps;
      }
    }

    // Logged-in totals come from Django (events + finalized days). Native per-app
    // bars/icons only; do not let device-wide UsageStats override JWT-scoped totals.
    final nativeHasLive = trusted && n.nativeTrackerConfigured;
    final nativeDay = nativeHasLive ? n.daySeconds : 0;
    final daySeconds = useBackendTotals
        ? (b.daySeconds >= nativeDay ? b.daySeconds : nativeDay)
        : (nativeDay > 0 ? nativeDay : n.daySeconds);
    final weekSeconds = useBackendTotals && b.weekSeconds > 0
        ? b.weekSeconds
        : (nativeHasLive ? n.weekSeconds : n.weekSeconds);
    final monthSeconds = useBackendTotals && b.monthSeconds > 0
        ? b.monthSeconds
        : (nativeHasLive ? n.monthSeconds : n.monthSeconds);

    final fgToday = trusted
        ? n.foregroundAppTodaySeconds
        : b.foregroundAppTodaySeconds;

    final lateNightWeekSeconds =
        trusted ? n.lateNightWeekSeconds : b.lateNightWeekSeconds;
    final lateNightOpensWeek =
        trusted ? n.lateNightOpensWeek : b.lateNightOpensWeek;
    final lateNightByDay = trusted && n.lateNightByDaySeconds.length >= 7
        ? List<int>.from(n.lateNightByDaySeconds.take(7))
        : (b.lateNightByDaySeconds.length >= 7
            ? List<int>.from(b.lateNightByDaySeconds.take(7))
            : List<int>.from(ScreenTimeSnapshot._lateNightByDayEmpty));
    final lateNightTop =
        trusted ? n.lateNightTopApps : b.lateNightTopApps;
    final lateNightSleep = trusted ? n.lateNightSleep : b.lateNightSleep;

    return ScreenTimeSnapshot(
      daySeconds: daySeconds,
      weekSeconds: weekSeconds,
      monthSeconds: monthSeconds,
      socialSeconds: b.socialSeconds > 0 ? b.socialSeconds : n.socialSeconds,
      videoSeconds: b.videoSeconds > 0 ? b.videoSeconds : n.videoSeconds,
      topApps: mergedTop.isNotEmpty ? mergedTop : n.topApps,
      recordingActive: b.recordingActive || n.recordingActive,
      activeVideoPlatform:
          n.activeVideoPlatform.isNotEmpty ? n.activeVideoPlatform : b.activeVideoPlatform,
      lastVideoUploadError:
          n.lastVideoUploadError.isNotEmpty ? n.lastVideoUploadError : b.lastVideoUploadError,
      screenCaptureGranted: b.screenCaptureGranted || n.screenCaptureGranted,
      foregroundAppName:
          n.foregroundAppName.isNotEmpty ? n.foregroundAppName : b.foregroundAppName,
      foregroundPackage:
          n.foregroundPackage.isNotEmpty ? n.foregroundPackage : b.foregroundPackage,
      foregroundAppTodaySeconds: fgToday,
      foregroundIconPngBase64: n.foregroundIconPngBase64.isNotEmpty
          ? n.foregroundIconPngBase64
          : b.foregroundIconPngBase64,
      analyticsDayBarHeights:
          _sevenBars(b.analyticsDayBarHeights, n.analyticsDayBarHeights),
      analyticsWeekBarHeights: n.analyticsWeekBarHeights.length >= 7
          ? n.analyticsWeekBarHeights
          : _sevenBars(b.analyticsWeekBarHeights, n.analyticsWeekBarHeights),
      analyticsMonthBarHeights:
          _sevenBars(b.analyticsMonthBarHeights, n.analyticsMonthBarHeights),
      usageStatsGranted: trusted || b.usageStatsGranted,
      nativeTrackerConfigured:
          n.nativeTrackerConfigured || b.nativeTrackerConfigured,
      faceReactionRecording: b.faceReactionRecording || n.faceReactionRecording,
      faceReactionCooldownUntilMs:
          n.faceReactionCooldownUntilMs > b.faceReactionCooldownUntilMs
              ? n.faceReactionCooldownUntilMs
              : b.faceReactionCooldownUntilMs,
      faceReactionLastError:
          n.faceReactionLastError.isNotEmpty
              ? n.faceReactionLastError
              : b.faceReactionLastError,
      lateNightWeekSeconds: lateNightWeekSeconds,
      lateNightOpensWeek: lateNightOpensWeek,
      lateNightByDaySeconds: lateNightByDay,
      lateNightTopApps: lateNightTop,
      lateNightSleep: lateNightSleep,
    );
  }

  List<int> _coerceLateNightByDay(dynamic raw) {
    if (raw is! List) {
      return List<int>.from(ScreenTimeSnapshot._lateNightByDayEmpty);
    }
    final out = <int>[];
    for (final e in raw) {
      if (out.length >= 7) break;
      out.add((e as num?)?.toInt() ?? 0);
    }
    while (out.length < 7) {
      out.add(0);
    }
    return out;
  }

  List<AppUsageItem> _coerceLateNightTopApps(dynamic raw) {
    if (raw is! List) return const <AppUsageItem>[];
    final out = <AppUsageItem>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final m = entry;
      final sec = (m['durationSeconds'] as num?)?.toInt() ?? 0;
      if (sec <= 0) continue;
      out.add(
        AppUsageItem(
          packageName: (m['packageName'] ?? '').toString(),
          appName: (m['appName'] ?? 'Unknown').toString(),
          durationSeconds: sec,
          iconPngBase64: _optionalIconBase64(m),
        ),
      );
    }
    return out;
  }

  Future<ScreenTimeSnapshot?> _pullNativeSnapshot() async {
    final Map<dynamic, dynamic>? raw = await _channel
        .invokeMethod<Map<dynamic, dynamic>>('getUsageSnapshot');
    if (raw == null) return null;

    final topAppsRaw = (raw['topApps'] as List<dynamic>? ?? const []);
    final topApps = topAppsRaw
        .map((entry) => entry as Map<dynamic, dynamic>)
        .map(
          (m) => AppUsageItem(
            packageName: (m['packageName'] ?? '').toString(),
            appName: (m['appName'] ?? 'Unknown').toString(),
            durationSeconds: (m['durationSeconds'] as num?)?.toInt() ?? 0,
            iconPngBase64: _optionalIconBase64(m),
          ),
        )
        .where((app) => app.durationSeconds > 0)
        .toList();

    final trackerStatus = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'getTrackerStatus',
    );

    final granted = raw['hasUsageAccess'] == true;
    final trackingConfigured = (trackerStatus?['trackingConfigured'] as bool?) ?? false;
    final serviceRunning = (trackerStatus?['serviceRunning'] as bool?) ?? false;
    final nativeTrackerConfigured = trackingConfigured || serviceRunning;
    final faceReactionRecording =
        (trackerStatus?['faceReactionRecording'] as bool?) ?? false;
    final faceReactionCooldownUntilMs =
        (trackerStatus?['faceReactionCooldownUntilMs'] as num?)?.toInt() ?? 0;
    final faceReactionLastError =
        (trackerStatus?['faceReactionLastError'] ?? '').toString();

    final weekBarRaw = raw['weekBarSeconds'] as List<dynamic>?;
    final weekBarSecs = weekBarRaw
            ?.map((e) => (e as num?)?.toInt() ?? 0)
            .toList() ??
        const <int>[];

    return ScreenTimeSnapshot(
      daySeconds: (raw['daySeconds'] as num?)?.toInt() ?? 0,
      weekSeconds: (raw['weekSeconds'] as num?)?.toInt() ?? 0,
      monthSeconds: (raw['monthSeconds'] as num?)?.toInt() ?? 0,
      socialSeconds: 0,
      videoSeconds: 0,
      topApps: topApps,
      recordingActive: (trackerStatus?['recordingActive'] as bool?) ?? false,
      activeVideoPlatform:
          (trackerStatus?['lastVideoPlatform'] ?? '').toString(),
      lastVideoUploadError:
          (trackerStatus?['lastVideoUploadError'] ?? '').toString(),
      screenCaptureGranted:
          (trackerStatus?['screenCaptureGranted'] as bool?) ?? false,
      foregroundAppName: (raw['foregroundAppName'] ?? '').toString(),
      foregroundPackage: (raw['foregroundPackage'] ?? '').toString(),
      foregroundAppTodaySeconds:
          (raw['foregroundTodaySeconds'] as num?)?.toInt() ?? 0,
      foregroundIconPngBase64:
          (raw['foregroundIconPngBase64'] ?? '').toString(),
      analyticsDayBarHeights: const [],
      analyticsWeekBarHeights:
          weekBarSecs.length >= 7 ? _barsFromSecondList(weekBarSecs) : const [],
      analyticsMonthBarHeights: const [],
      usageStatsGranted: granted,
      nativeTrackerConfigured: nativeTrackerConfigured,
      faceReactionRecording: faceReactionRecording,
      faceReactionCooldownUntilMs: faceReactionCooldownUntilMs,
      faceReactionLastError: faceReactionLastError,
      lateNightWeekSeconds: (raw['lateNightWeekSeconds'] as num?)?.toInt() ?? 0,
      lateNightOpensWeek: (raw['lateNightOpensWeek'] as num?)?.toInt() ?? 0,
      lateNightByDaySeconds: _coerceLateNightByDay(raw['lateNightByDaySeconds']),
      lateNightTopApps: _coerceLateNightTopApps(raw['lateNightTopApps']),
      lateNightSleep: LateNightSleepSnapshot.fromMap(
        Map<String, dynamic>.from(raw),
      ),
    );
  }

  /// Native `daily_records` archive + merged week app seconds (Android only).
  Future<Map<String, dynamic>?> fetchUsageArchive() async {
    if (kIsWeb) return null;
    try {
      final raw = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('getScreenTimeUsageArchive');
      if (raw == null) return null;
      return Map<String, dynamic>.from(raw);
    } catch (_) {
      return null;
    }
  }

  Future<ScreenTimeSnapshot?> _fetchUsageFromBackend() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth.accessToken') ?? '';
    if (token.isEmpty) return null;

    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };

    Future<Map<String, dynamic>?> getJson(String path) {
      return getJsonWithRetry(
        Uri.parse('$_baseUrl$path'),
        headers: headers,
      );
    }

    final results = await Future.wait<Map<String, dynamic>?>([
      getJson('/api/auth/usage/daily/'),
      getJson('/api/screentime/summary/'),
      getJson('/api/auth/usage/weekly/'),
      getJson('/api/auth/usage/monthly/'),
      getJson('/api/screen-time/today/'),
      getJson('/api/auth/usage/live/'),
    ]);

    final daily = results[0];
    final summary = results[1];
    final weekly = results[2];
    final monthly = results[3];
    final trackingToday = results[4];
    final live = results[5];
    final trackerStatus = !kIsWeb
        ? await _channel.invokeMethod<Map<dynamic, dynamic>>('getTrackerStatus')
        : null;
    final nativeTrackerConfigured =
        ((trackerStatus?['trackingConfigured'] as bool?) ?? false) ||
        ((trackerStatus?['serviceRunning'] as bool?) ?? false);
    final faceReactionRecording =
        (trackerStatus?['faceReactionRecording'] as bool?) ?? false;
    final faceReactionCooldownUntilMs =
        (trackerStatus?['faceReactionCooldownUntilMs'] as num?)?.toInt() ?? 0;
    final faceReactionLastError =
        (trackerStatus?['faceReactionLastError'] ?? '').toString();

    // Web has no native tracker; return empty snapshot when API is unreachable.
    if (daily == null) {
      if (kIsWeb) {
        return ScreenTimeSnapshot.empty;
      }
      return null;
    }

    final weeklySafe = weekly ??
        <String, dynamic>{
          'total_seconds': daily['total_seconds'],
          'chart': <String, dynamic>{'data': <dynamic>[]},
        };
    final monthlySafe = monthly ??
        <String, dynamic>{
          'total_seconds': daily['total_seconds'],
          'by_day': <dynamic>[],
        };

    final current = live?['current_app'] as Map<String, dynamic>?;
    final fgName = current?['app_name']?.toString() ?? '';
    final fgPkg = current?['package_name']?.toString() ?? '';
    final fgSecs = (current?['today_seconds'] as num?)?.toInt() ?? 0;

    homeYesterdayDaySeconds =
        (daily['yesterday_total_seconds'] as num?)?.toInt() ?? 0;
    homeBackendSleepSeconds =
        (trackingToday?['sleep_time'] as num?)?.toInt() ?? 0;
    homeBackendLateNightSeconds =
        (trackingToday?['late_night_activity'] as num?)?.toInt() ?? 0;

    var daySeconds = (daily['total_seconds'] as num?)?.toInt() ?? 0;
    if (summary != null) {
      final unified = (summary['today_total_seconds'] as num?)?.toInt();
      if (unified != null && unified >= 0) {
        daySeconds = unified;
      }
    }
    final liveTotal = (live?['total_seconds'] as num?)?.toInt();
    if (liveTotal != null && liveTotal > daySeconds) {
      daySeconds = liveTotal;
    }

    var weekSeconds = (weeklySafe['total_seconds'] as num?)?.toInt() ?? 0;
    var monthSeconds = (monthlySafe['total_seconds'] as num?)?.toInt() ?? 0;
    if (summary != null) {
      weekSeconds = (summary['week_total_seconds'] as num?)?.toInt() ?? weekSeconds;
      monthSeconds = (summary['month_total_seconds'] as num?)?.toInt() ?? monthSeconds;
    }

    final dailyBars = _barsSevenFromDaily(daily['chart_bars_7']);
    final weekBars = _barsSevenFromWeeklyHours(weeklySafe['chart']?['data']);
    final monthBars = _barsSevenFromMonth(monthlySafe['by_day']);
    final nativeWeekBars = await _nativeWeekBarSeconds();

    final dailyApps = (daily['apps'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    final topApps = dailyApps
        .map(
          (app) => AppUsageItem(
            packageName: (app['package_name'] ?? '').toString(),
            appName: (app['app_name'] ?? 'Unknown').toString(),
            durationSeconds: (app['usage_time'] as num?)?.toInt() ?? 0,
          ),
        )
        .where((item) => item.durationSeconds > 0)
        .toList();

    _backendDayAnchorSeconds = daySeconds;
    _backendDayAnchorAt = DateTime.now();
    final webTabExtra = kIsWeb ? _webTabSeconds : 0;

    return ScreenTimeSnapshot(
      daySeconds: daySeconds + webTabExtra,
      weekSeconds: weekSeconds,
      monthSeconds: monthSeconds,
      socialSeconds:
          (trackingToday?['social_media_time'] as num?)?.toInt() ?? 0,
      videoSeconds: (trackingToday?['video_watch_time'] as num?)?.toInt() ?? 0,
      topApps: topApps,
      recordingActive: (trackerStatus?['recordingActive'] as bool?) ?? false,
      activeVideoPlatform: (trackerStatus?['lastVideoPlatform'] ?? '')
          .toString(),
      lastVideoUploadError: (trackerStatus?['lastVideoUploadError'] ?? '')
          .toString(),
      screenCaptureGranted:
          (trackerStatus?['screenCaptureGranted'] as bool?) ?? false,
      foregroundAppName: fgName,
      foregroundPackage: fgPkg,
      foregroundAppTodaySeconds: fgSecs,
      foregroundIconPngBase64: '',
      analyticsDayBarHeights: _sevenBarsSingle(dailyBars),
      analyticsWeekBarHeights: nativeWeekBars.isNotEmpty
          ? _barsFromSecondList(nativeWeekBars)
          : _sevenBarsSingle(weekBars),
      analyticsMonthBarHeights: _sevenBarsSingle(monthBars),
      usageStatsGranted: kIsWeb,
      nativeTrackerConfigured: nativeTrackerConfigured || kIsWeb,
      faceReactionRecording: faceReactionRecording,
      faceReactionCooldownUntilMs: faceReactionCooldownUntilMs,
      faceReactionLastError: faceReactionLastError,
    );
  }

  String? _optionalIconBase64(Map<dynamic, dynamic> m) {
    final s = m['iconPngBase64']?.toString();
    if (s == null || s.isEmpty) return null;
    return s;
  }

  List<double> _barsSevenFromDaily(dynamic raw) {
    if (raw is! List) return const [];
    final out =
        raw.map((e) => (e as num).toDouble().clamp(8.0, 80.0)).toList();
    if (out.length >= 7) return out.sublist(0, 7);
    return out;
  }

  List<double> _barsSevenFromWeeklyHours(dynamic raw) {
    if (raw is! List || raw.isEmpty) return const [];
    final allHours = raw.map((e) => (e as num).toDouble()).toList();
    final hours =
        allHours.length <= 7 ? allHours : allHours.sublist(allHours.length - 7);
    double maxH = hours.isEmpty ? 1.0 : hours.reduce((a, b) => a > b ? a : b);
    if (maxH <= 0) maxH = 1;
    final bars =
        hours.map((h) => ((h / maxH) * 68.0).clamp(10.0, 68.0)).toList();
    while (bars.length < 7) {
      bars.add(28.0);
    }
    return bars.sublist(0, 7);
  }

  List<double> _barsSevenFromMonth(dynamic raw) {
    if (raw is! List || raw.isEmpty) return const [];
    final totals = <double>[];
    for (final row in raw) {
      if (row is Map<String, dynamic>) {
        totals.add(((row['day_total'] as num?) ?? 0).toDouble());
      }
    }
    final chunk =
        totals.length <= 7 ? totals : totals.sublist(totals.length - 7);
    if (chunk.isEmpty) return const [];
    double maxV = chunk.reduce((a, b) => a > b ? a : b);
    if (maxV <= 0) maxV = 1;
    final bars =
        chunk.map((v) => ((v / maxV) * 68.0).clamp(10.0, 68.0)).toList();
    while (bars.length < 7) {
      bars.add(28.0);
    }
    return bars.sublist(0, 7);
  }

  Future<void> setTrackingUser(String? userId) async {
    _currentUserId = userId;
    if (userId != null && userId.isNotEmpty) {
      _stickyMonitoringActive = true;
      await startTrackingSession(userId);
      await flushMidnightScreenTimePending();
    }
    await persistDevicePermissionGrants(userId: userId);
    await _syncTrackerContext();
    try {
      await _channel.invokeMethod('pingTracker');
    } catch (_) {}
  }

  Future<bool> startTrackingSession(String userId) async {
    if (kIsWeb || userId.isEmpty) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('startTrackingSession', userId);
      await refreshSessionDisplaySeconds(userId);
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> resetUsageBaselinesForNewUser(String userId) async {
    if (kIsWeb || userId.isEmpty) return;
    try {
      await _channel.invokeMethod('resetUsageBaselines', userId);
    } catch (_) {}
  }

  Future<void> endTrackingSession(String userId) async {
    if (kIsWeb || userId.isEmpty) return;
    try {
      await _channel.invokeMethod('endTrackingSession', userId);
    } catch (_) {}
    sessionDisplaySeconds.value = 0;
  }

  Future<void> refreshSessionDisplaySeconds([String? userId]) async {
    final id = userId ?? _currentUserId;
    if (kIsWeb || id == null || id.isEmpty) return;
    try {
      final raw = await _channel.invokeMethod<dynamic>('getSessionScreenTimeMs', id);
      int ms = 0;
      if (raw is int) {
        ms = raw;
      } else if (raw is num) {
        ms = raw.toInt();
      }
      final secs = (ms / 1000).floor().clamp(0, 1 << 30);
      _sessionAnchorSeconds = secs;
      _sessionAnchorWallAt = DateTime.now();
      sessionDisplaySeconds.value = secs;
      _tickTodayLiveDisplay();
    } catch (_) {}
  }

  void _tickSessionDisplay() {
    if (!_running) return;
    if (_currentUserId == null || _currentUserId!.isEmpty) return;
    if (_sessionAnchorWallAt == null) return;
    final extra = DateTime.now().difference(_sessionAnchorWallAt!).inSeconds;
    final display = (_sessionAnchorSeconds + extra).clamp(0, 1 << 30);
    if (sessionDisplaySeconds.value != display) {
      sessionDisplaySeconds.value = display;
    }
  }

  Future<bool> hasAccessibilityService() async {
    if (kIsWeb) return true;
    try {
      final v = await _channel.invokeMethod<bool>('hasAccessibilityService');
      return v ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> openAccessibilitySettings() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('openAccessibilitySettings');
    } catch (_) {}
  }

  Future<void> clearTrackingUser() async {
    final ending = _currentUserId;
    if (ending != null && ending.isNotEmpty) {
      await endTrackingSession(ending);
    }
    _currentUserId = null;
    _appInBackground = false;
    _stickyMonitoringActive = false;
    _lastGoodSnapshot = null;
    _osTodayAnchorAt = null;
    _osTodayAnchorSeconds = 0;
    todayLiveDisplaySeconds.value = 0;
    sessionDisplaySeconds.value = 0;
    _sessionAnchorSeconds = 0;
    _sessionAnchorWallAt = null;
    _rollingMerged.clear();
    rollingAppUsage.value = const <AppUsageItem>[];
    await _syncTrackerContext();
  }

  /// Native [getRollingAppUsage]: merges by [AppUsageItem.packageName] (no full list replace).
  Future<void> refreshRollingAppUsage() async {
    if (kIsWeb || !_running) return;
    try {
      if (!await hasUsageAccess()) return;
      final raw = await _channel.invokeMethod<List<dynamic>>('getRollingAppUsage');
      if (raw == null) return;
      final incomingPkgs = <String>{};
      for (final e in raw) {
        if (e is! Map) continue;
        final m = Map<dynamic, dynamic>.from(e);
        final pkg = (m['packageName'] ?? '').toString();
        if (pkg.isEmpty) continue;
        final name = (m['appName'] ?? pkg).toString();
        final ms = (m['totalTimeInForegroundMs'] as num?)?.toInt() ?? 0;
        if (ms <= 0) continue;
        incomingPkgs.add(pkg);
        final sec = (ms / 1000).round();
        final iconRaw = m['iconPngBase64']?.toString();
        _rollingMerged[pkg] = AppUsageItem(
          packageName: pkg,
          appName: name,
          durationSeconds: sec,
          iconPngBase64: (iconRaw == null || iconRaw.isEmpty) ? null : iconRaw,
          totalForegroundMs: ms,
        );
      }
      _rollingMerged.removeWhere((k, _) => !incomingPkgs.contains(k));
      final list = _rollingMerged.values.toList()
        ..sort((a, b) => b.sortKeyMs.compareTo(a.sortKeyMs));
      rollingAppUsage.value = list;
    } catch (_) {}
  }

  Future<void> _refreshOsTodayAnchor() async {
    if (kIsWeb || !_running) return;
    try {
      if (!await hasUsageAccess()) return;
      final raw = await _channel.invokeMethod<dynamic>('getTodayScreenTimeMs');
      int ms = 0;
      if (raw is int) {
        ms = raw;
      } else if (raw is num) {
        ms = raw.toInt();
      }
      _osTodayAnchorSeconds = (ms / 1000).floor();
      _osTodayAnchorAt = DateTime.now();
      _tickTodayLiveDisplay();
    } catch (_) {}
  }

  void _maybeSeedOsAnchorFromSnapshot(ScreenTimeSnapshot merged) {
    if (kIsWeb || !merged.usageStatsGranted) return;
    if (_currentUserId != null && _currentUserId!.isNotEmpty) return;
    if (_osTodayAnchorAt == null) {
      _osTodayAnchorSeconds = merged.daySeconds;
      _osTodayAnchorAt = DateTime.now();
    }
  }

  List<double> _barsFromSecondList(List<int> seconds) {
    if (seconds.isEmpty) return List<double>.from(ScreenTimeSnapshot.analyticsBarsNoData);
    final max = seconds.reduce((a, b) => a > b ? a : b);
    if (max <= 0) return List<double>.from(ScreenTimeSnapshot.analyticsBarsNoData);
    return seconds
        .map((s) => (s / max * 100.0).clamp(8.0, 100.0))
        .toList();
  }

  Future<List<int>> _nativeWeekBarSeconds() async {
    if (kIsWeb) return const [];
    try {
      if (!await hasUsageAccess()) return const [];
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('getUsageSnapshot');
      final bars = raw?['weekBarSeconds'] as List<dynamic>?;
      if (bars == null) return const [];
      return bars.map((e) => (e as num?)?.toInt() ?? 0).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _flushWebTabSecondsToBackend() async {
    if (!kIsWeb || _currentUserId == null || _currentUserId!.isEmpty) return;
    final delta = _webTabSeconds - _lastWebFlushSeconds;
    if (delta <= 0) return;
    final ok = await updateScreenTime(deltaTotal: delta);
    if (ok) {
      _lastWebFlushSeconds = _webTabSeconds;
    }
  }

  void _tickTodayLiveDisplay() {
    if (!_running) return;
    final snap = snapshot.value;
    var display = snap.daySeconds;
    if (kIsWeb) {
      todayLiveDisplaySeconds.value = display < 0 ? 0 : display;
      return;
    }
    if (_currentUserId != null && _currentUserId!.isNotEmpty) {
      if (snap.usageStatsGranted && snap.nativeTrackerConfigured) {
        display = snap.daySeconds;
      } else if (_backendDayAnchorAt != null) {
        final extra = DateTime.now().difference(_backendDayAnchorAt!).inSeconds;
        display = _backendDayAnchorSeconds + extra;
        if (display < snap.daySeconds) {
          display = snap.daySeconds;
        }
      } else {
        display = snap.daySeconds;
      }
      todayLiveDisplaySeconds.value = display < 0 ? 0 : display;
      return;
    }
    if (_osTodayAnchorAt != null && snap.usageStatsGranted) {
      final extra = DateTime.now().difference(_osTodayAnchorAt!).inSeconds;
      display = _osTodayAnchorSeconds + extra;
      if (display < snap.daySeconds) {
        display = snap.daySeconds;
      }
    }
    todayLiveDisplaySeconds.value = display < 0 ? 0 : display;
  }

  Future<bool> hasOverlayPermission() async {
    if (kIsWeb) return true;
    try {
      final v = await _channel.invokeMethod<bool>('hasOverlayPermission');
      return v ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> openManageOverlaySettings() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('openManageOverlaySettings');
    } catch (_) {}
  }

  static String _localDateIso() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Keeps today's per-user total in Django (calendar day, local midnight reset on device).
  Future<void> syncTodayScreenTimeToBackend() async {
    if (kIsWeb) return;
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) return;
    if (!await hasUsageAccess()) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth.accessToken') ?? '';
      if (token.isEmpty) return;

      final raw = await _channel.invokeMethod<dynamic>('getSessionScreenTimeMs', uid);
      int ms = 0;
      if (raw is int) {
        ms = raw;
      } else if (raw is num) {
        ms = raw.toInt();
      }
      if (ms <= 0) return;

      await http
          .post(
            Uri.parse('$_baseUrl/api/screentime/save-day/'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'total_ms': ms,
              'date': _localDateIso(),
            }),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {}
  }

  /// Posts rolled-over local session ms after midnight ([screenTimeCheckMidnightReset]).
  Future<void> flushMidnightScreenTimePending() async {
    if (kIsWeb) return;
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth.accessToken') ?? '';
      if (token.isEmpty) return;

      final raw = await _channel.invokeMethod<dynamic>('screenTimeCheckMidnightReset', uid);
      if (raw is! Map) return;
      final ms = (raw['total_ms'] as num?)?.toInt() ?? 0;
      if (ms <= 0) return;
      final dateStr = raw['date']?.toString();

      await http
          .post(
            Uri.parse('$_baseUrl/api/screentime/save-day/'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'total_ms': ms,
              if (dateStr != null && dateStr.isNotEmpty) 'date': dateStr,
            }),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {}
  }

  Future<void> _syncTrackerContext() async {
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth.accessToken') ?? '';
      var screenCaptureOnboardingDone =
          prefs.getBool(TrackingPermissionPrefs.screenCaptureGrantedKey) ?? false;
      final nativeScreenCapture = await hasScreenCapturePermission();
      if (nativeScreenCapture && !screenCaptureOnboardingDone) {
        screenCaptureOnboardingDone = true;
        await prefs.setBool(
          TrackingPermissionPrefs.screenCaptureGrantedKey,
          true,
        );
      }
      await _channel.invokeMethod('configureTracker', {
        'baseUrl': _baseUrl,
        'token': token,
        'userId': _currentUserId ?? '',
        'faceVerified': faceVerified.value,
        'faceMatchPercent': faceMatchPercent.value,
        'screenCaptureOnboardingDone': screenCaptureOnboardingDone,
      });
      if (nativeScreenCapture) {
        await _notifyNativeScreenCaptureGranted();
      }
      await ParentalControlService.restoreNativeHomeBlockerFromPrefs();
    } on MissingPluginException {
      // Plugin not available on this platform/build.
    } catch (_) {
      // Ignore channel sync errors.
    }
  }

  /// Update screen time on backend
  ///
  /// Called when video tracking completes or screen time is recorded
  Future<bool> updateScreenTime({
    int deltaTotal = 0,
    int deltaSocial = 0,
    int deltaVideo = 0,
    String dataPlatform = '',
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth.accessToken') ?? '';
      if (token.isEmpty) return false;

      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

      final body = jsonEncode({
        'mode': 'delta',
        'delta_total': deltaTotal,
        'delta_social': deltaSocial,
        'delta_video': deltaVideo,
      });

      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/screen-time/update/'),
            headers: headers,
            body: body,
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 201) {
        _refresh();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error updating screen time: $e');
      return false;
    }
  }
}

String formatDurationShort(int totalSeconds) {
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  if (hours == 0) return '${minutes}m';
  return '${hours}h ${minutes}m';
}

/// Live screen time: seconds → m:ss → h:mm:ss.
String formatDurationClock(int totalSeconds) {
  final s = totalSeconds < 0 ? 0 : totalSeconds;
  if (s < 60) return '${s}s';
  if (s < 3600) {
    final m = s ~/ 60;
    final sec = s % 60;
    return '$m:${sec.toString().padLeft(2, '0')}';
  }
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  return '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
}

class _ScreenTimeLifecycleObserver with WidgetsBindingObserver {
  _ScreenTimeLifecycleObserver(this._service);

  final ScreenTimeService _service;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _service._onAppLifecycle(state);
  }
}
