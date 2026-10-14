import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../route_observers.dart';
import '../../utils/mental_health_severity.dart';
import '../../utils/social_app_branding.dart';
import '../../widgets/permission_banner.dart';
import '../pages/profile_screen.dart';
import '../../services/app_public_service.dart';
import '../../services/local_auth_service.dart';
import '../../services/screen_time_service.dart';
import '../../services/tracking_permissions_gate.dart';
import '../../services/wellness_dashboard_service.dart';
import '../../services/weekly_mood_service.dart';
import '../../widgets/mindsync_logo.dart';
import '../../widgets/mental_health_insights_gate.dart';
import '../pages/upgrade_plan_screen.dart';

Uint8List? _decodeAppIconBase64(String? b64) {
  if (b64 == null || b64.isEmpty) return null;
  try {
    return Uint8List.fromList(base64Decode(b64));
  } catch (_) {
    return null;
  }
}

String _formatIsoShort(String iso) {
  if (iso.length >= 16)
    return 'Updated ${iso.substring(0, 16).replaceFirst('T', ' ')}';
  return 'Updated recently';
}

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
    unawaited(WellnessDashboardService.instance.refresh(force: true));
    WeeklyMoodService.instance.startPolling();
    AppPublicService.instance.loadBranding(forceRefresh: false);
    _loadProfile();
  }

  Future<void> _bootstrapScreenTime() async {
    await TrackingPermissionsGate.startScreenTimeIfPermitted();
    final userId = await _auth.getStoredUserId();
    await ScreenTimeService.instance.ensureMonitoringForUser(userId);
    await ScreenTimeService.instance.refreshMonitoringStateFromNative();
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
  }

  @override
  void didPopNext() {
    unawaited(_bootstrapScreenTime());
  }

  Future<void> _loadProfile() async {
    final profile = await _auth.fetchCurrentUserProfile();
    if (!mounted || profile == null) return;
    setState(() => _displayName = profile.displayName);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 32),
          children: [
            _TopOverviewCard(
              userName: _displayName,
              onProfileTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                );
              },
            ),
            const SizedBox(height: 16),
            ValueListenableBuilder<ScreenTimeSnapshot>(
              valueListenable: ScreenTimeService.instance.snapshot,
              builder: (context, data, _) {
                if (data.usageStatsGranted) return const SizedBox.shrink();
                return PermissionBanner(
                  title: 'Usage Access Required',
                  description: 'MindSync needs usage access to track your screen time and app usage.',
                  icon: Icons.data_usage,
                  onAllow: () async {
                    await ScreenTimeService.instance.openUsageSettings();
                    await ScreenTimeService.instance.refreshNow();
                  },
                );
              },
            ),
            const _MetricGrid(),
            const SizedBox(height: 16),
            const _AppUsageCard(),
            const SizedBox(height: 16),
            const _VulnerabilityCardDynamic(),
            const SizedBox(height: 16),
            const _WeeklyMoodCardDynamic(),
          ],
        ),
      ),
    );
  }
}

class _TopOverviewCard extends StatefulWidget {
  const _TopOverviewCard({required this.onProfileTap, required this.userName});

  final VoidCallback onProfileTap;
  final String userName;

  @override
  State<_TopOverviewCard> createState() => _TopOverviewCardState();
}

class _TopOverviewCardState extends State<_TopOverviewCard> {
  @override
  void initState() {
    super.initState();
    AppPublicService.instance.loadBranding(forceRefresh: true);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 174, 128, 228),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row with MindSync logo and profile icon
          Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 5),
                child: SizedBox(
                  height: 88,
                  width: 150,
                  child: MindSyncLogo(height: 82, width: 140),
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: widget.onProfileTap,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFE0E0E8),
                      width: 1.5,
                    ),
                  ),
                  child: const CircleAvatar(
                    radius: 16,
                    backgroundColor: Color(0xFFF0F0F5),
                    child: Icon(
                      Icons.person,
                      color: Color(0xFF6B6C76),
                      size: 18,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Hello user greeting
          Text(
            'Hello, ${widget.userName}',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: Color.fromARGB(255, 250, 251, 252),
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          // Restorative phase message
          const Text(
            'MindSync - Because your mental health matters',
            style: TextStyle(
              fontSize: 15,
              color: Color.fromARGB(255, 250, 250, 250),
              fontWeight: FontWeight.w500,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: const [
            Expanded(child: _WellbeingScoreCardLive()),
            SizedBox(width: 12),
            Expanded(child: _ScreenTimeCard()),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: const [
            Expanded(child: _StressLevelCardLive()),
            SizedBox(width: 12),
            Expanded(child: _ActionNeededCard()),
          ],
        ),
      ],
    );
  }
}

class _WellbeingScoreCardLive extends StatelessWidget {
  const _WellbeingScoreCardLive();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 130,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: MentalHealthInsightsGate(
        builder: (context, access) {
          final d = access.dashboard;
          final score = d.wellbeingScore.clamp(0, 100);
          final mental = d.mentalHealthScore.clamp(0, 100);
          final progress = (score / 100.0).clamp(0.001, 1.0);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.circle_outlined,
                size: 14,
                color: Color(0xFF6F39E8),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: 48,
                height: 48,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 3.5,
                      backgroundColor: const Color(0xFFE7E8EF),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color.from(
                          alpha: 1,
                          red: 0.435,
                          green: 0.224,
                          blue: 0.91,
                        ),
                      ),
                    ),
                    Text(
                      '$score',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: Color(0xFF1A2130),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              if (access.canShowInsights)
                MentalHealthScoreDisplay(
                  percent: mental,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  labelFontWeight: FontWeight.w800,
                ),
              const Spacer(),
              const Text(
                'WELLBEING SCORE',
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 1.2,
                  color: Color(0xFF8A8D99),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ScreenTimeCard extends StatelessWidget {
  const _ScreenTimeCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 112,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.access_time, size: 14, color: Color(0xFF6F39E8)),
              const Spacer(),
              ValueListenableBuilder<ScreenTimeSnapshot>(
                valueListenable: ScreenTimeService.instance.snapshot,
                builder: (_, data, _) {
                  final live =
                      data.nativeTrackerConfigured || data.usageStatsGranted;
                  return Text(
                    live ? 'Live' : '—',
                    style: TextStyle(
                      fontSize: 10,
                      color: live
                          ? const Color(0xFF0E9186)
                          : const Color(0xFF8A8D99),
                      fontWeight: FontWeight.w700,
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 2),
          ValueListenableBuilder<int>(
            valueListenable: ScreenTimeService.instance.todayLiveDisplaySeconds,
            builder: (_, liveSecs, _) {
              return ValueListenableBuilder<ScreenTimeSnapshot>(
                valueListenable: ScreenTimeService.instance.snapshot,
                builder: (_, data, _) {
                  final secs = liveSecs > 0 ? liveSecs : data.daySeconds;
                  return FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      formatDurationClock(secs),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        height: 1.0,
                        letterSpacing: 1.0,
                        fontFeatures: [FontFeature.tabularFigures()],
                        fontFamily: 'monospace',
                        color: Color(0xFF1A2130),
                      ),
                    ),
                  );
                },
              );
            },
          ),
          const Text(
            'SCREEN TIME',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.1,
              color: Color(0xFF8A8D99),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StressLevelCardLive extends StatelessWidget {
  const _StressLevelCardLive();

  static Widget _footerLabel() {
    return const Text(
      'STRESS LEVEL',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 11,
        letterSpacing: 1.1,
        color: Color(0xFF8A8D99),
        fontWeight: FontWeight.w600,
        height: 1.1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 130,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Color.fromRGBO(
              (0.435 * 255).toInt(),
              (0.224 * 255).toInt(),
              (0.91 * 255).toInt(),
              1.0,
            ),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: MentalHealthInsightsGate(
        builder: (context, access) {
          if (!access.hasPaidPlan) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: MentalHealthInsightsPlaceholderCard(
                    embedded: true,
                    title: 'STRESS LEVEL',
                    message: access.upgradeMessage,
                    actionLabel: 'View plans',
                    onAction: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const UpgradePlanScreen(),
                        ),
                      );
                    },
                  ),
                ),
                _footerLabel(),
              ],
            );
          }
          if (!access.hasMinimumExpressions) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: MentalHealthInsightsPlaceholderCard(
                    embedded: true,
                    title: 'STRESS LEVEL',
                    message: access.insufficientDataMessage,
                    icon: Icons.hourglass_empty_outlined,
                  ),
                ),
                _footerLabel(),
              ],
            );
          }

          final d = access.dashboard;
          final stress = d.stressIndicator.clamp(0, 100);
          final frac = stress / 100.0;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.monitor_heart_outlined,
                size: 14,
                color: Color(0xFF6F39E8),
              ),
              const SizedBox(height: 6),
              MentalHealthScoreDisplay(
                percent: stress,
                fontSize: 20,
                fontWeight: FontWeight.w600,
                labelFontWeight: FontWeight.w900,
                maxLines: 2,
              ),
              const SizedBox(height: 6),
              Container(
                width: math.min(120.0, 36.0 + 80.0 * frac),
                height: 4,
                decoration: BoxDecoration(
                  color: MentalHealthSeverity.progressBarColor,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const Spacer(),
              _footerLabel(),
            ],
          );
        },
      ),
    );
  }
}

class _ActionNeededCard extends StatelessWidget {
  const _ActionNeededCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 130),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ValueListenableBuilder<ScreenTimeSnapshot>(
        valueListenable: ScreenTimeService.instance.snapshot,
        builder: (context, data, _) {
          final monitoringOn =
              data.usageStatsGranted && data.nativeTrackerConfigured;
          final monitoredLabel = data.foregroundAppName.trim();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                monitoringOn
                    ? Icons.verified_user_outlined
                    : Icons.warning_amber_rounded,
                size: 14,
                color: const Color(0xFF6F39E8),
              ),
              const SizedBox(height: 8),
              Text(
                monitoringOn ? 'Active' : 'Inactive',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  height: 0.95,
                  color: monitoringOn
                      ? const Color(0xFF1A2130)
                      : const Color(0xFFB85C00),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Monitoring',
                style: TextStyle(
                  fontSize: 11,
                  color: Color(0xFF8A8D99),
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (monitoringOn && monitoredLabel.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Currently monitoring: $monitoredLabel',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF0E9186),
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              if (!monitoringOn)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () async {
                    await ScreenTimeService.instance.openUsageSettings();
                    await ScreenTimeService.instance.refreshNow();
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      'Open usage settings',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF6F39E8),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                )
              else if (!data.screenCaptureGranted)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () async {
                    await ScreenTimeService.instance
                        .ensureScreenCapturePermission();
                    await ScreenTimeService.instance.refreshNow();
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      'Optional: screen capture',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF6F39E8),
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              const Text(
                'ALERTS',
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 1.2,
                  color: Color(0xFF8A8D99),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AppUsageCard extends StatelessWidget {
  const _AppUsageCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
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
            children: [
              Row(
                children: [
                  const Text(
                    'App Usage',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A2130),
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    'TODAY',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF8C8C96),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
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
                  final bytes = _decodeAppIconBase64(app.iconPngBase64);
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
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: iconBg.withValues(alpha: 0.6)),
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
                        fontWeight: FontWeight.w600,
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
                fontWeight: FontWeight.w500,
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

class _VulnerabilityCardDynamic extends StatelessWidget {
  const _VulnerabilityCardDynamic();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: MentalHealthInsightsGate(
        builder: (context, access) {
          if (!access.hasPaidPlan) {
            return MentalHealthInsightsPlaceholderCard(
              title: 'Mental Health Insights',
              message: access.upgradeMessage,
              actionLabel: 'Upgrade plan',
              onAction: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const UpgradePlanScreen()),
                );
              },
            );
          }
          if (!access.hasMinimumExpressions) {
            return MentalHealthInsightsPlaceholderCard(
              title: 'Mental Health Insights',
              message: access.insufficientDataMessage,
              icon: Icons.insights_outlined,
            );
          }

          final mh = access.dashboard.mentalHealth;
          final updated = mh.lastUpdated;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Text(
                    'Mental Health Insights',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A2130),
                    ),
                  ),
                  Spacer(),
                  Icon(Icons.info_outline, size: 16, color: Color(0xFF9A9BA6)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    'Overall',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A2130),
                    ),
                  ),
                  const SizedBox(width: 8),
                  MentalHealthScoreDisplay(
                    percent: mh.overall.score,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    labelFontWeight: FontWeight.w800,
                  ),
                  if (updated != null && updated.isNotEmpty) ...[
                    const Spacer(),
                    Text(
                      _formatIsoShort(updated),
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF9A9BA6),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              _VulnerabilityRow(
                label: 'Stress',
                scorePercent: mh.stress.score,
                barColor: MentalHealthSeverity.stressInsightBarColor,
              ),
              const SizedBox(height: 12),
              _VulnerabilityRow(
                label: 'Anxiety',
                scorePercent: mh.anxiety.score,
                barColor: MentalHealthSeverity.anxietyInsightBarColor,
              ),
              const SizedBox(height: 12),
              _VulnerabilityRow(
                label: 'Depression',
                scorePercent: mh.depression.score,
                barColor: MentalHealthSeverity.depressionInsightBarColor,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _VulnerabilityRow extends StatelessWidget {
  final String label;
  final num scorePercent;
  final Color barColor;

  const _VulnerabilityRow({
    required this.label,
    required this.scorePercent,
    required this.barColor,
  });

  @override
  Widget build(BuildContext context) {
    final progress = (scorePercent / 100).clamp(0.0, 1.0);

    return Column(
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: Color(0xFF2C2D36),
              ),
            ),
            const Spacer(),
            MentalHealthScoreDisplay(
              percent: scorePercent,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              labelFontWeight: FontWeight.w800,
            ),
          ],
        ),
        const SizedBox(height: 8),
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
    );
  }
}

class _WeeklyMoodCardDynamic extends StatelessWidget {
  const _WeeklyMoodCardDynamic();

  static const _weekdayLabels = [
    'MON',
    'TUE',
    'WED',
    'THU',
    'FRI',
    'SAT',
    'SUN',
  ];

  Widget _buildTag(BuildContext context, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F3F8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          color: Color(0xFF64646F),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Color _moodColor(String category) {
    switch (category) {
      case 'happy':
        return const Color(0xFF37B48A);
      case 'sad':
        return const Color(0xFF5B7FD6);
      default:
        return const Color(0xFF9B8EC4);
    }
  }

  Widget _buildWeekLabels(List<MoodDayEntry> days) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(7, (i) {
        final weekday = i < _weekdayLabels.length ? _weekdayLabels[i] : '';
        final day = i < days.length ? days[i] : null;
        final hasData = (day?.entries ?? 0) > 0;
        final moodLbl = hasData && (day?.graphLabel.isNotEmpty ?? false)
            ? day!.graphLabel
            : '';
        return Expanded(
          child: Column(
            children: [
              Text(
                weekday,
                style: TextStyle(
                  fontSize: 10,
                  color: hasData
                      ? const Color(0xFF6F39E8)
                      : const Color(0xFF8A8D99),
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (moodLbl.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  moodLbl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: _moodColor(day!.moodCategory),
                  ),
                ),
              ],
            ],
          ),
        );
      }),
    );
  }

  Widget _previewThumb(MoodDayMedia? m) {
    if (m == null) return const SizedBox.shrink();
    if (m.type == 'video') {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFFEDE9FB),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.videocam_rounded,
          color: Color(0xFF6F39E8),
          size: 20,
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        m.url,
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) =>
            const Icon(Icons.image_not_supported_outlined, size: 20),
      ),
    );
  }

  Widget _dayRow(MoodDayEntry day) {
    final label = day.graphLabel.isNotEmpty
        ? day.graphLabel
        : (day.label.isNotEmpty ? day.label : '—');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(
              day.date.length >= 10 ? day.date.substring(5) : day.date,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF8A8D99),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _previewThumb(day.previewMedia),
          if (day.previewMedia != null) const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _moodColor(day.moodCategory),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _distributionRow(List<MoodDistributionItem> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: items.map((item) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _moodColor(item.mood).withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _moodColor(item.mood).withOpacity(0.35)),
          ),
          child: Text(
            '${item.label} ${item.percent.toStringAsFixed(0)}%',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: _moodColor(item.mood),
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ValueListenableBuilder<WeeklyMoodLiveData>(
        valueListenable: WeeklyMoodService.instance.live,
        builder: (context, mood, _) {
          if (!mood.hasSummary) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Weekly Mood Architecture',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                    color: Color(0xFF1A2130),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  mood.placeholder ?? 'Not enough data yet',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6B6E7A),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${mood.entryCount} of 3 mood entries needed',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF8A8D99),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildTag(context, '7 Days'),
                    const SizedBox(width: 8),
                    _buildTag(context, 'Live refresh'),
                  ],
                ),
              ],
            );
          }

          final overall = mood.overallMood;
          final overallLbl = overall.label.isNotEmpty
              ? overall.label
              : mood.dominantMood;
          final graphScores = mood.days.map((d) => d.moodScore ?? 0.5).toList();
          final graphLabels = mood.days
              .map((d) => d.entries > 0 ? d.graphLabel : '')
              .toList();
          final graphCats = mood.days.map((d) => d.moodCategory).toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Weekly Mood Architecture',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                  color: Color(0xFF1A2130),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: _moodColor(overall.category).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _moodColor(overall.category).withOpacity(0.35),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.insights_rounded,
                      size: 20,
                      color: _moodColor(overall.category),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Overall mood: $overallLbl',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: _moodColor(overall.category),
                            ),
                          ),
                          if (overall.score != null)
                            Text(
                              'Weekly average valence ${(overall.score! * 100).round()}%',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF6B6E7A),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _distributionRow(mood.moodDistribution),
              const SizedBox(height: 6),
              Text(
                '${mood.entryCount} captures · concluded from Happy / Neutral / Sad mix',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF6B6E7A),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildTag(context, '7 Days'),
                  const SizedBox(width: 8),
                  _buildTag(context, 'Live refresh'),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 132,
                child: CustomPaint(
                  painter: _MoodGraphPainterLive(
                    scores: graphScores,
                    labels: graphLabels,
                    categories: graphCats,
                  ),
                  size: Size(MediaQuery.of(context).size.width - 60, 132),
                ),
              ),
              const SizedBox(height: 8),
              _buildWeekLabels(mood.days),
              const SizedBox(height: 12),
              ...mood.days.where((d) => d.entries > 0).map(_dayRow),
            ],
          );
        },
      ),
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
    const topPad = 14.0;
    const bottomPad = 28.0;
    final plotH = size.height - topPad - bottomPad;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        const Radius.circular(12),
      ),
      Paint()..color = const Color(0xFFF5F4FC),
    );

    // Y-axis guides: Sad (low) — Neutral — Happy (high)
    final guidePaint = Paint()
      ..color = const Color(0xFFE0DCE8)
      ..strokeWidth = 0.8;
    for (var i = 0; i <= 2; i++) {
      final y = topPad + plotH * (i / 2);
      canvas.drawLine(Offset(8, y), Offset(size.width - 8, y), guidePaint);
    }

    final n = scores.length;
    final pts = <Offset>[];
    final pointColors = <Color>[];

    for (var i = 0; i < n; i++) {
      final hasLabel = i < labels.length && labels[i].isNotEmpty;
      final v = hasLabel ? scores[i].clamp(0.0, 1.0) : 0.5;
      final x = n <= 1 ? size.width / 2 : 12 + (size.width - 24) * i / (n - 1);
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
      if (i < labels.length && labels[i].isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(
            text: labels[i],
            style: TextStyle(
              color: c,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 44);
        tp.paint(canvas, Offset(pts[i].dx - tp.width / 2, topPad + plotH + 4));
      }
    }

    // Side mood scale labels
    void drawSideLabel(String text, double y, Color color) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color.withOpacity(0.7),
            fontSize: 8,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(2, y - tp.height / 2));
    }

    drawSideLabel('Happy', topPad, const Color(0xFF37B48A));
    drawSideLabel('Neutral', topPad + plotH / 2, const Color(0xFF9B8EC4));
    drawSideLabel('Sad', topPad + plotH, const Color(0xFF5B7FD6));
  }

  @override
  bool shouldRepaint(covariant _MoodGraphPainterLive oldDelegate) =>
      oldDelegate.scores != scores ||
      oldDelegate.labels != labels ||
      oldDelegate.categories != categories;
}
