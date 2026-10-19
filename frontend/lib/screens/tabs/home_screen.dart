import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../route_observers.dart';
import '../../utils/mental_health_severity.dart';
import '../../utils/social_app_branding.dart';
import '../../services/app_public_service.dart';
import '../../services/local_auth_service.dart';
import '../../services/screen_time_service.dart';
import '../../services/tracking_permissions_gate.dart';
import '../../services/wellness_dashboard_service.dart';
import '../../services/weekly_mood_service.dart';
import '../../widgets/mental_health_insights_gate.dart';
import 'home/home_emotional_resilience.dart';
import 'home/home_hero_metrics.dart';
import 'home/home_screen_helpers.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with RouteAware {
  final _auth = LocalAuthService();
  String _displayName = 'User';

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrapScreenTime());
    unawaited(WellnessDashboardService.instance.refreshHome(force: true));
    unawaited(
      WellnessDashboardService.instance.refresh(
        force: true,
        days: kReportWellnessWindowDays,
      ),
    );
    WeeklyMoodService.instance.startPolling();
    AppPublicService.instance.loadBranding(forceRefresh: false);
    _loadProfile();
  }

  Future<void> _bootstrapScreenTime() async {
    await TrackingPermissionsGate.startScreenTimeIfPermitted();
    final userId = await _auth.getStoredUserId();
    await ScreenTimeService.instance.ensureMonitoringForUser(userId);
    await ScreenTimeService.instance.refreshMonitoringStateFromNative();
    await ScreenTimeService.instance.refreshRollingAppUsage();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    mindSyncRouteObserver.unsubscribe(this);
    final route = ModalRoute.of(context);
    if (route is PageRoute<void>) {
      mindSyncRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    WeeklyMoodService.instance.stopPolling();
    mindSyncRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPush() {
    unawaited(_bootstrapScreenTime());
    unawaited(WellnessDashboardService.instance.refreshHome(force: true));
    unawaited(
      WellnessDashboardService.instance.refresh(
        force: true,
        days: kReportWellnessWindowDays,
      ),
    );
    unawaited(WeeklyMoodService.instance.refresh());
  }

  @override
  void didPopNext() {
    unawaited(_bootstrapScreenTime());
    unawaited(WellnessDashboardService.instance.refreshHome(force: true));
    unawaited(
      WellnessDashboardService.instance.refresh(
        force: true,
        days: kReportWellnessWindowDays,
      ),
    );
    unawaited(WeeklyMoodService.instance.refresh());
  }

  Future<void> _loadProfile() async {
    final profile = await _auth.fetchCurrentUserProfile();
    if (!mounted || profile == null) return;
    setState(() => _displayName = profile.displayName);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F1FB),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
          children: [
            _GreetingBlock(userName: _displayName),
            const SizedBox(height: 18),
            const _HeroBalanceCard(),
            const SizedBox(height: 16),
            const _AppUsageCard(),
            const SizedBox(height: 16),
            const _MentalHealthCard(),
            const SizedBox(height: 16),
            const _WeeklyMoodCardDynamic(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Greeting block — plain background (no gradient)
// ---------------------------------------------------------------------------

class _GreetingBlock extends StatelessWidget {
  const _GreetingBlock({required this.userName});

  final String userName;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hello, $userName',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: Color(0xFF1A2130),
              letterSpacing: -0.6,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'MINDSYNC, Because Your Mental Health Matters',
            style: TextStyle(
              fontSize: 13.5,
              color: Color(0xFF6B6E7A),
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hero card — starts at MIN BALANCE INDEX (gradient begins here)
// ---------------------------------------------------------------------------

class _HeroBalanceCard extends StatelessWidget {
  const _HeroBalanceCard();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        WellnessDashboardService.instance.homeDashboard,
        WellnessDashboardService.instance.dashboard,
        WellnessDashboardService.instance.wellbeingDeltaPoints,
        ScreenTimeService.instance.snapshot,
        ScreenTimeService.instance.rollingAppUsage,
      ]),
      builder: (context, _) {
        final wellness = WellnessDashboardService.instance.homeDashboard.value;
        final reportWellness =
            WellnessDashboardService.instance.dashboard.value;
        final screen = ScreenTimeService.instance.snapshot.value;
        final st = ScreenTimeService.instance;
        final metrics = HomeHeroMetrics.compose(
          wellness: wellness,
          reportWellness: reportWellness,
          screen: screen,
          yesterdayDaySeconds: st.homeYesterdayDaySeconds,
          backendSleepSeconds: st.homeBackendSleepSeconds,
          backendLateNightSeconds: st.homeBackendLateNightSeconds,
          wellbeingDeltaPoints:
              WellnessDashboardService.instance.wellbeingDeltaPoints.value,
          rollingApps: ScreenTimeService.instance.rollingAppUsage.value,
        );
        final showWellbeing = metrics.wellbeingScore > 0 ||
            wellness.hasWellbeingSignal ||
            reportWellness.hasWellbeingSignal ||
            wellness.mentalHealth.hasData ||
            wellness.totalChunks > 0;
        final scoreText = metrics.wellbeingScore > 0
            ? '${metrics.wellbeingScore}'
            : (showWellbeing ? '…' : '—');

        return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6F39E8).withValues(alpha: 0.30),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- Restorative pill ----
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  size: 13,
                  color: Color(0xFFB9F0C0),
                ),
                const SizedBox(width: 6),
                Text(
                  showWellbeing
                      ? 'Restorative · $scoreText/100 · ${kHomeWellnessWindowDays}-day'
                      : 'Restorative Day',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ---- Mind Balance Index header + ring ----
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'MIND BALANCE INDEX',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFD8C4FF),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          scoreText,
                          style: const TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.w900,
                            height: 1.0,
                            color: Colors.white,
                            letterSpacing: -1,
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.only(left: 6, bottom: 6),
                          child: Text(
                            '/ 100',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFD8C4FF),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            metrics.wellbeingDeltaPoints >= 0
                                ? Icons.arrow_upward_rounded
                                : Icons.arrow_downward_rounded,
                            size: 11,
                            color: metrics.wellbeingDeltaPoints >= 0
                                ? const Color(0xFFB9F0C0)
                                : const Color(0xFFFFB4B4),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            metrics.wellbeingDeltaLabel,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 82,
                height: 82,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 82,
                      height: 82,
                      child: CircularProgressIndicator(
                        value: metrics.wellbeingProgress,
                        strokeWidth: 6,
                        backgroundColor: Colors.white.withValues(alpha: 0.18),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF5EEAD4),
                        ),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.spa_outlined,
                          size: 16,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          metrics.balanceRingLabel,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ---- 2×2 stat tiles ----
          Row(
            children: [
              Expanded(
                child: _HeroStatTile(
                  icon: Icons.access_time_rounded,
                  iconColor: const Color(0xFF5EEAD4),
                  label: 'Screen Time',
                  value: metrics.screenTimeValue,
                  caption: metrics.screenTimeCaption,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HeroStatTile(
                  icon: Icons.monitor_heart_outlined,
                  iconColor: const Color(0xFF5EEAD4),
                  label: 'Stress Baseline',
                  value: metrics.stressValue,
                  caption: metrics.stressCaption,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _HeroStatTile(
                  icon: Icons.nightlight_round,
                  iconColor: const Color(0xFF5EEAD4),
                  label: 'Sleep',
                  value: metrics.sleepValue,
                  caption: metrics.sleepCaption,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HeroStatTile(
                  icon: Icons.check_circle_outline_rounded,
                  iconColor: const Color(0xFF5EEAD4),
                  label: 'Habit Guidance',
                  value: metrics.habitValue,
                  caption: metrics.habitCaption,
                  appIconBytes: decodeAppIconBase64(
                    metrics.topHabitApp?.iconPngBase64,
                  ),
                  appPackageName: metrics.topHabitApp?.packageName ?? '',
                  appDisplayName: metrics.topHabitApp?.appName ?? '',
                ),
              ),
            ],
          ),
        ],
      ),
    );
      },
    );
  }
}

class _HeroStatTile extends StatelessWidget {
  const _HeroStatTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.caption,
    this.appIconBytes,
    this.appPackageName = '',
    this.appDisplayName = '',
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String caption;
  final Uint8List? appIconBytes;
  final String appPackageName;
  final String appDisplayName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: iconColor),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFD8C4FF),
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (appIconBytes != null && appIconBytes!.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.memory(
                    appIconBytes!,
                    width: 20,
                    height: 20,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _habitFallbackIcon(),
                  ),
                ),
                const SizedBox(width: 6),
              ] else if (appDisplayName.isNotEmpty) ...[
                _habitFallbackIcon(),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }

  Widget _habitFallbackIcon() {
    if (appDisplayName.isEmpty) {
      return const SizedBox.shrink();
    }
    final style = _styleForApp(appDisplayName, packageName: appPackageName);
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: style.iconBg.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Icon(
        style.brandIcon ?? style.icon,
        size: 12,
        color: Colors.white,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// App Usage card
// ---------------------------------------------------------------------------

class _AppUsageCard extends StatelessWidget {
  const _AppUsageCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _sectionDecoration(),
      child: AnimatedBuilder(
        animation: Listenable.merge([
          ScreenTimeService.instance.snapshot,
          ScreenTimeService.instance.rollingAppUsage,
        ]),
        builder: (context, _) {
          final data = ScreenTimeService.instance.snapshot.value;
          final rolling = ScreenTimeService.instance.rollingAppUsage.value;
          final fgName = data.foregroundAppName.trim();
          final fgPkg = data.foregroundPackage.trim();

          final useNativeToday =
              data.nativeTrackerConfigured && data.topApps.isNotEmpty;
          final useRolling =
              !useNativeToday && data.usageStatsGranted && rolling.isNotEmpty;
          var ranked = List<AppUsageItem>.from(
            useNativeToday
                ? data.topApps
                : (useRolling ? rolling : data.topApps),
          )..sort((a, b) => b.sortKeyMs.compareTo(a.sortKeyMs));

          final shown = <AppUsageItem>[];
          if (fgName.isNotEmpty && fgPkg.isNotEmpty) {
            AppUsageItem? match;
            for (final a in ranked) {
              if (a.packageName == fgPkg) {
                match = a;
                break;
              }
            }
            shown.add(
              match ??
                  AppUsageItem(
                    packageName: fgPkg,
                    appName: fgName,
                    durationSeconds: data.foregroundAppTodaySeconds,
                    totalForegroundMs: data.foregroundAppTodaySeconds * 1000,
                    iconPngBase64: data.foregroundIconPngBase64.isEmpty
                        ? null
                        : data.foregroundIconPngBase64,
                  ),
            );
          }
          for (final a in ranked) {
            if (shown.length >= 5) break;
            if (fgPkg.isNotEmpty && a.packageName == fgPkg) continue;
            shown.add(a);
          }

          final maxMs = shown.isEmpty
              ? 1
              : shown.map((e) => e.sortKeyMs).reduce((a, b) => a > b ? a : b);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'App Usage',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A2130),
                      letterSpacing: -0.3,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F1FB),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'TODAY',
                      style: TextStyle(
                        fontSize: 10,
                        color: Color(0xFF6F39E8),
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Mindful screen distribution today',
                style: TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF8A8D99),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              if (shown.isEmpty)
                const Text(
                  'Usage data will appear after you use other apps today. '
                  'Ensure Usage Access is enabled.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF7A7D8A)),
                )
              else
                ...shown.asMap().entries.map((entry) {
                  final app = entry.value;
                  final style = _styleForApp(
                    app.appName,
                    packageName: app.packageName,
                  );
                  final bytes = decodeAppIconBase64(app.iconPngBase64);
                  final isFg = fgPkg.isNotEmpty && app.packageName == fgPkg;
                  final displaySecs = (app.sortKeyMs / 1000).round();
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: entry.key == shown.length - 1 ? 0 : 14,
                    ),
                    child: _UsageRow(
                      label: app.appName,
                      time: formatDurationClock(displaySecs),
                      progress: app.sortKeyMs / maxMs,
                      color: style.barColor,
                      icon: style.icon,
                      brandIcon: style.brandIcon,
                      iconBg: style.iconBg,
                      iconColor: style.iconColor,
                      iconBitmap: bytes,
                      showLiveBadge: isFg,
                    ),
                  );
                }),
              if (shown.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F1FB),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Icon(
                        Icons.lightbulb_outline_rounded,
                        size: 16,
                        color: Color(0xFF6F39E8),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '30 min screen-free wind-down is recommended at '
                          '10:30 PM for melatonin alignment.',
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.4,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF6B6E7A),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

SocialAppBranding _styleForApp(String appName, {String packageName = ''}) {
  return SocialAppBranding.forApp(appName: appName, packageName: packageName);
}

class _UsageRow extends StatelessWidget {
  final String label;
  final String time;
  final double progress;
  final Color color;
  final IconData icon;
  final IconData? brandIcon;
  final Color iconBg;
  final Color iconColor;
  final Uint8List? iconBitmap;
  final bool showLiveBadge;

  const _UsageRow({
    required this.label,
    required this.time,
    required this.progress,
    required this.color,
    required this.icon,
    this.brandIcon,
    required this.iconBg,
    required this.iconColor,
    this.iconBitmap,
    this.showLiveBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: brandIcon != null
                  ? FaIcon(brandIcon!, size: 15, color: iconColor)
                  : iconBitmap != null && iconBitmap!.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        iconBitmap!,
                        width: 26,
                        height: 26,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      ),
                    )
                  : Icon(icon, size: 15, color: iconColor),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Row(
                children: [
                  if (showLiveBadge) ...[
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: const BoxDecoration(
                        color: Color(0xFFE53935),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const Text(
                      'LIVE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFE53935),
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2C2D36),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Text(
              time,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF6B6C76),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 5,
            backgroundColor: const Color(0xFFEFF0F5),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Mental Health card — placeholders with 0 values when no data
// ---------------------------------------------------------------------------

class _MentalHealthCard extends StatelessWidget {
  const _MentalHealthCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _sectionDecoration(),
      child: MentalHealthInsightsGate(
        dashboardListenable: WellnessDashboardService.instance.homeDashboard,
        builder: (context, access) {
          const header = Row(
            children: [
              Text(
                'Mental Health',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A2130),
                  letterSpacing: -0.3,
                ),
              ),
              Spacer(),
              _LivePill(),
            ],
          );

          final hasOpenFace = access.dashboard.openfaceCaptureCount > 0;
          final showLive =
              access.hasPaidPlan &&
              (access.hasMinimumExpressions || hasOpenFace);

          if (!showLive) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                header,
                const SizedBox(height: 4),
                const Text(
                  '3-day rolling · OpenFace background video',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF8A8D99),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),
                const _BioMetricRow(
                  label: 'Stress Load',
                  subtitle: 'From ~30s background face analysis',
                  scorePercent: 0,
                  barColor: MentalHealthSeverity.stressInsightBarColor,
                  rightLabel: 'Calm',
                  showPercent: true,
                ),
                const SizedBox(height: 16),
                const _BioMetricRow(
                  label: 'Depression Screening',
                  subtitle: 'OpenFace AU + depression model',
                  scorePercent: 0,
                  barColor: MentalHealthSeverity.depressionInsightBarColor,
                  rightLabel: 'Calm',
                  showPercent: true,
                ),
                const SizedBox(height: 20),
                HomeEmotionalResilienceSegmentBar(
                  days: _placeholderResilienceDays(),
                ),
              ],
            );
          }

          final mh = access.dashboard.mentalHealth;
          final resilienceDays = access.dashboard.emotionalResilienceDays;
          final resilienceSlots = resilienceDays.length >= kHomeWellnessWindowDays
              ? resilienceDays
              : _placeholderResilienceDays();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header,
              const SizedBox(height: 4),
              const Text(
                '3-day rolling · OpenFace background video',
                style: TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF8A8D99),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              _BioMetricRow(
                label: 'Stress Load',
                subtitle: 'From ~30s background face analysis',
                scorePercent: mh.stress.score,
                barColor: MentalHealthSeverity.stressInsightBarColor,
                rightLabel: _severityLabel(mh.stress.score),
                showPercent: true,
              ),
              const SizedBox(height: 16),
              _BioMetricRow(
                label: 'Depression Screening',
                subtitle: 'OpenFace AU + depression model',
                scorePercent: mh.depression.score,
                barColor: MentalHealthSeverity.depressionInsightBarColor,
                rightLabel: _severityLabel(mh.depression.score),
                showPercent: true,
              ),
              const SizedBox(height: 20),
              HomeEmotionalResilienceSegmentBar(days: resilienceSlots),
            ],
          );
        },
      ),
    );
  }

  static String _severityLabel(num score) {
    if (score < 30) return 'Calm';
    if (score < 60) return 'Moderate';
    if (score < 80) return 'Elevated';
    return 'High';
  }
}

class _LivePill extends StatelessWidget {
  const _LivePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFDCFCE7),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Color(0xFF22C55E),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          const Text(
            'Live Bio-Sync',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: Color(0xFF15803D),
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

List<EmotionalResilienceDay> _placeholderResilienceDays() {
  const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final today = DateTime.now();
  return List.generate(kHomeWellnessWindowDays, (i) {
    final d = today.subtract(Duration(days: kHomeWellnessWindowDays - 1 - i));
    return EmotionalResilienceDay(
      date: '',
      dayName: labels[d.weekday - 1],
      emotionLabel: 'Awaiting scan',
      resilienceFill: 0,
      samples: 0,
      tone: 'neutral',
    );
  });
}

class _BioMetricRow extends StatelessWidget {
  final String label;
  final String subtitle;
  final num scorePercent;
  final Color barColor;
  final String rightLabel;
  final bool showPercent;

  const _BioMetricRow({
    required this.label,
    required this.subtitle,
    required this.scorePercent,
    required this.barColor,
    required this.rightLabel,
    this.showPercent = true,
  });

  @override
  Widget build(BuildContext context) {
    final progress = (scorePercent / 100).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F8FE),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: Color(0xFF1A2130),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF8A8D99),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (showPercent)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    MentalHealthScoreDisplay(
                      percent: scorePercent,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      labelFontWeight: FontWeight.w800,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      rightLabel,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF8A8D99),
                      ),
                    ),
                  ],
                )
              else
                Text(
                  rightLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF8A8D99),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(
              MentalHealthSeverity.homeProgressBarBorderRadius,
            ),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: MentalHealthSeverity.homeProgressBarMinHeight,
              backgroundColor: MentalHealthSeverity.progressBarBackground,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Weekly Mood card — always renders the graph (with 0 values when empty)
// ---------------------------------------------------------------------------

class _WeeklyMoodCardDynamic extends StatelessWidget {
  const _WeeklyMoodCardDynamic();

  static const _weekdayLabels = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  String _weekdayFromDate(String isoDate) {
    if (isoDate.length < 10) return '';
    try {
      final dt = DateTime.parse(isoDate);
      final idx = dt.weekday - 1;
      if (idx >= 0 && idx < _weekdayLabels.length) {
        return _weekdayLabels[idx];
      }
    } catch (_) {}
    return '';
  }

  Widget _buildDayLabels(List<MoodDayEntry> days) {
    final slots = kWeeklyMoodDays;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(slots, (i) {
        String weekday = '';
        if (i < days.length) {
          weekday = _weekdayFromDate(days[i].date);
          if (weekday.isEmpty && days[i].graphLabel.isNotEmpty) {
            weekday = days[i].graphLabel;
          }
        }
        return Expanded(
          child: Text(
            weekday,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF8A8D99),
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _sectionDecoration(),
      child: ValueListenableBuilder<WeeklyMoodLiveData>(
        valueListenable: WeeklyMoodService.instance.live,
        builder: (context, mood, _) {
          final List<double> graphScores;
          final List<String> graphLabels;
          final List<String> graphCats;

          final weekDays = mood.days.length >= kWeeklyMoodDays
              ? mood.days
              : (mood.days.isEmpty
                  ? List<MoodDayEntry>.generate(
                      kWeeklyMoodDays,
                      (_) => const MoodDayEntry(
                        date: '',
                        label: '',
                        graphLabel: '',
                        moodScore: null,
                        moodCategory: 'neutral',
                        entries: 0,
                        media: [],
                      ),
                    )
                  : mood.days);
          if (mood.hasGraphData && weekDays.any((d) => d.entries > 0)) {
            graphScores = weekDays
                .map((d) => d.entries > 0 ? (d.moodScore ?? 0.5) : 0.0)
                .toList();
            graphLabels = weekDays
                .map((d) => d.entries > 0 ? (d.label.isNotEmpty ? d.label : d.graphLabel) : '')
                .toList();
            graphCats = weekDays.map((d) => d.moodCategory).toList();
          } else {
            graphScores = List.filled(kWeeklyMoodDays, 0.0);
            graphLabels = List.filled(kWeeklyMoodDays, '');
            graphCats = List.filled(kWeeklyMoodDays, 'neutral');
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Color(0xFF22C55E),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'POSITIVE TRAJECTORY',
                              style: TextStyle(
                                fontSize: 10,
                                letterSpacing: 1.2,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF15803D),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Weekly Mood',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                            color: Color(0xFF1A2130),
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F1FB),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '7 Days',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF6F39E8),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 140,
                    width: 48,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: const [
                        Text(
                          'Happy',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF37B48A),
                            height: 1.1,
                          ),
                        ),
                        Text(
                          'Neutral',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF9B8EC4),
                            height: 1.1,
                          ),
                        ),
                        Text(
                          'Unhappy',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF5B7FD6),
                            height: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        SizedBox(
                          height: 140,
                          width: double.infinity,
                          child: CustomPaint(
                            painter: _MoodGraphPainterLive(
                              scores: graphScores,
                              labels: graphLabels,
                              categories: graphCats,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        _buildDayLabels(weekDays),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (mood.entryCount >= 1 && mood.recentEntries.isNotEmpty) ...[
                ...mood.recentEntries.take(6).map(_recentMoodTile),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  Icon(
                    mood.hasGraphData
                        ? Icons.trending_up_rounded
                        : Icons.hourglass_empty_rounded,
                    size: 14,
                    color: mood.hasGraphData
                        ? const Color(0xFF15803D)
                        : const Color(0xFF8A8D99),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      mood.latestMood.isNotEmpty
                          ? 'Latest: ${mood.latestMood}${mood.hasSummary ? ' · week trend' : ''}'
                          : mood.hasGraphData
                              ? 'Mood captured · building 7-day trend'
                              : (mood.placeholder ?? 'Unlock to capture mood'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: mood.hasGraphData
                            ? const Color(0xFF15803D)
                            : const Color(0xFF8A8D99),
                      ),
                    ),
                  ),
                  const Text(
                    'Full Log →',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF6F39E8),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _recentMoodTile(RecentMoodEntry entry) {
    final preview = entry.preview;
    final url = preview?.url ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: url.isNotEmpty
                ? Image.network(
                    url,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _moodThumbPlaceholder(),
                  )
                : _moodThumbPlaceholder(),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.label.isNotEmpty ? entry.label : 'Mood',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A2130),
                  ),
                ),
                if (entry.time.isNotEmpty)
                  Text(
                    entry.time,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF8A8D99),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _moodThumbPlaceholder() {
    return Container(
      width: 44,
      height: 44,
      color: const Color(0xFFF3F1FB),
      child: const Icon(Icons.face_rounded, color: Color(0xFF6F39E8), size: 22),
    );
  }
}

class _MoodGraphPainterLive extends CustomPainter {
  _MoodGraphPainterLive({
    required this.scores,
    required this.labels,
    required this.categories,
  });

  final List<double> scores;
  final List<String> labels;
  final List<String> categories;

  static Color _catColor(String cat) {
    switch (cat) {
      case 'happy':
        return const Color(0xFF37B48A);
      case 'sad':
        return const Color(0xFF5B7FD6);
      default:
        return const Color(0xFF9B8EC4);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    const topPad = 10.0;
    const bottomPad = 8.0;
    const leftPad = 6.0;
    const rightPad = 8.0;
    final plotW = size.width - leftPad - rightPad;
    final plotH = size.height - topPad - bottomPad;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        const Radius.circular(12),
      ),
      Paint()..color = const Color(0xFFF5F4FC),
    );

    final guidePaint = Paint()
      ..color = const Color(0xFFE0DCE8)
      ..strokeWidth = 0.8;
    for (var i = 0; i <= 2; i++) {
      final y = topPad + plotH * (i / 2);
      canvas.drawLine(
        Offset(leftPad, y),
        Offset(size.width - rightPad, y),
        guidePaint,
      );
    }

    final axisPaint = Paint()
      ..color = const Color(0xFFD8D3E6)
      ..strokeWidth = 1.2;
    canvas.drawLine(
      Offset(leftPad, topPad),
      Offset(leftPad, topPad + plotH),
      axisPaint,
    );

    final n = scores.length;
    final pts = <Offset>[];
    final pointColors = <Color>[];

    for (var i = 0; i < n; i++) {
      final hasLabel = i < labels.length && labels[i].isNotEmpty;
      final v = hasLabel ? scores[i].clamp(0.0, 1.0) : 0.5;
      final x = n <= 1
          ? leftPad + plotW / 2
          : leftPad + plotW * i / (n - 1);
      final y = topPad + plotH * (1.0 - v);
      pts.add(Offset(x, y));
      final cat = i < categories.length ? categories[i] : 'neutral';
      pointColors.add(hasLabel ? _catColor(cat) : const Color(0xFFD0D3DC));
    }

    if (pts.length >= 2) {
      final linePath = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (var i = 1; i < pts.length; i++) {
        final prev = pts[i - 1];
        final cur = pts[i];
        final midX = (prev.dx + cur.dx) / 2;
        linePath.cubicTo(midX, prev.dy, midX, cur.dy, cur.dx, cur.dy);
      }
      final fillPath = Path.from(linePath)
        ..lineTo(pts.last.dx, topPad + plotH)
        ..lineTo(pts.first.dx, topPad + plotH)
        ..close();
      canvas.drawPath(fillPath, Paint()..color = const Color(0xFFEAE5FA));
      canvas.drawPath(
        linePath,
        Paint()
          ..color = const Color(0xFF6F39E8)
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }

    for (var i = 0; i < pts.length; i++) {
      final c = pointColors[i];
      canvas.drawCircle(pts[i], 5, Paint()..color = Colors.white);
      canvas.drawCircle(
        pts[i],
        5,
        Paint()
          ..color = c
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MoodGraphPainterLive oldDelegate) =>
      oldDelegate.scores != scores ||
      oldDelegate.labels != labels ||
      oldDelegate.categories != categories;
}

// ---------------------------------------------------------------------------
// Shared card decoration
// ---------------------------------------------------------------------------

BoxDecoration _sectionDecoration() {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(24),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.03),
        blurRadius: 16,
        offset: const Offset(0, 6),
      ),
    ],
  );
}