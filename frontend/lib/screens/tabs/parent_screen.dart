import 'dart:async';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../pages/profile_screen.dart';
import '../../services/dns_filter_service.dart';
import '../../services/parental_control_service.dart';
import '../../services/local_auth_service.dart';
import '../../services/plan_access_service.dart';
import '../../services/feature_permission_service.dart';
import '../../services/screen_time_service.dart';
import '../../services/social_media_usage_limit_store.dart';
import '../../utils/social_app_branding.dart';
import '../../ui/components/mind_sync_header.dart';
import '../../ui/layout/mindsync_layout.dart';
import '../../widgets/permission_banner.dart';

class ParentScreen extends StatefulWidget {
  const ParentScreen({super.key});

  @override
  State<ParentScreen> createState() => _ParentScreenState();
}

class _ParentScreenState extends State<ParentScreen>
    with WidgetsBindingObserver {
  final _parentService = ParentalControlService();
  final _dnsFilter = DnsFilterService.instance;
  final _auth = LocalAuthService();
  bool _loadingApps = false;
  bool _loadingUser = false;
  String _displayName = 'User';
  String? _faceImageUrl;
  int _socialLimitMinutes = 90;
  int _gamingLimitMinutes = 60;
  int _entertainmentLimitMinutes = 120;
  List<ParentalAppRule> _rules = const [];
  final Map<String, int> _appSocialLimits = {};
  bool _loadingContentMonitor = false;
  ParentContentMonitorSnapshot _contentMonitor =
      ParentContentMonitorSnapshot.empty;

  // Permissions state
  bool _hasAccessibility = true;
  bool _hasOverlay = true;

  // Content Restrictions — default unblocked (DNS + time limits off)
  bool socialMediaLimit = false;
  bool gamingLimit = false;
  bool entertainmentLimit = false;

  // App Restrictions switches
  bool tiktokLimit = true;
  bool youtubeLimit = true;
  bool robloxLimit = false;
  bool instagramLimit = true;

  // Safety Controls — default off
  bool safeSearchActive = false;
  bool blockAdultContent = false;
  DnsFilterStatus _dnsStatus = DnsFilterStatus.empty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
    _initWithPlanCheck();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    final acc = await ScreenTimeService.instance.hasAccessibilityService();
    final ovl = await ScreenTimeService.instance.hasOverlayPermission();
    if (!mounted) return;
    setState(() {
      _hasAccessibility = acc;
      _hasOverlay = ovl;
    });
  }

  Future<void> _initWithPlanCheck() async {
    final allowed = await PlanAccessService.instance.canAccess(
      'parental_control',
    );
    if (!allowed) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Upgrade to Premium to access Parental Control.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).maybePop();
      return;
    }
    _loadUser();
    _loadParentRules();
    _loadContentMonitor();
    await _loadDnsFilterState();
  }

  Future<void> _loadDnsFilterState() async {
    await _dnsFilter.loadPrefsInto(
      apply:
          ({
            required blockSocial,
            required blockGaming,
            required blockEntertainment,
            required safeSearch,
            required blockAdult,
          }) {
            socialMediaLimit = blockSocial;
            gamingLimit = blockGaming;
            entertainmentLimit = blockEntertainment;
            safeSearchActive = safeSearch;
            blockAdultContent = blockAdult;
          },
    );
    final status = await _dnsFilter.getStatus();
    if (!mounted) return;
    setState(() => _dnsStatus = status);
  }

  bool get _anyDnsFilterActive =>
      socialMediaLimit ||
      gamingLimit ||
      entertainmentLimit ||
      safeSearchActive ||
      blockAdultContent;

  Future<bool> _ensureVpnPermission() async {
    if (await _dnsFilter.hasVpnPermission()) return true;
    final granted = await _dnsFilter.prepareVpn();
    if (granted || !mounted) return granted;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('VPN permission required'),
        content: const Text(
          'DNS-based content filtering needs MindSync to run a local VPN that '
          'only intercepts DNS traffic. Android shows this as a VPN connection — '
          'your browsing data is not sent to MindSync servers.\n\n'
          'Without this permission, category blocks, Safe Search, and adult '
          'content filtering cannot take effect.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return false;
  }

  Future<void> _syncDnsFilter() async {
    if (_anyDnsFilterActive && !await _ensureVpnPermission()) {
      await _loadDnsFilterState();
      return;
    }
    final status = await _dnsFilter.applyConfig(
      blockSocial: socialMediaLimit,
      blockGaming: gamingLimit,
      blockEntertainment: entertainmentLimit,
      safeSearch: safeSearchActive,
      blockAdult: blockAdultContent,
    );
    if (!mounted) return;
    setState(() => _dnsStatus = status);
  }

  Future<void> _onSocialCategoryChanged(bool value) async {
    setState(() => socialMediaLimit = value);
    await _syncDnsFilter();
    await _applyPolicy(enableEnforcement: value);
  }

  Future<void> _onGamingCategoryChanged(bool value) async {
    setState(() => gamingLimit = value);
    await _syncDnsFilter();
    await _applyPolicy(enableEnforcement: value);
  }

  Future<void> _onEntertainmentCategoryChanged(bool value) async {
    setState(() => entertainmentLimit = value);
    await _syncDnsFilter();
    await _applyPolicy(enableEnforcement: value);
  }

  Future<void> _onSafeSearchChanged(bool value) async {
    setState(() => safeSearchActive = value);
    await _syncDnsFilter();
  }

  Future<void> _onAdultBlockChanged(bool value) async {
    setState(() => blockAdultContent = value);
    await _syncDnsFilter();
  }

  Future<void> _loadContentMonitor() async {
    setState(() => _loadingContentMonitor = true);
    final snapshot = await _parentService.fetchContentMonitor();
    if (!mounted) return;
    setState(() {
      _contentMonitor = snapshot;
      _loadingContentMonitor = false;
    });
  }

  Future<void> _loadUser() async {
    setState(() => _loadingUser = true);
    final profile = await _auth.fetchCurrentUserProfile();
    if (!mounted) return;
    setState(() {
      _displayName = profile?.fullName.isNotEmpty == true
          ? profile!.fullName
          : (profile?.displayName ?? 'User');
      _faceImageUrl = profile?.faceImage;
      _loadingUser = false;
    });
  }

  Future<void> _loadParentRules() async {
    setState(() => _loadingApps = true);
    final rules = await _parentService.fetchRules();
    if (!mounted) return;
    setState(() {
      _rules = rules;
      for (final rule in rules) {
        _appSocialLimits.putIfAbsent(
          rule.packageName,
          () => _socialLimitMinutes,
        );
      }
      _loadingApps = false;
    });
  }

  Future<void> _toggleApp(String packageName, bool blocked) async {
    final previousRules = _rules;
    setState(() {
      _rules = _rules
          .map(
            (r) => r.packageName == packageName
                ? ParentalAppRule(
                    packageName: r.packageName,
                    appLabel: r.appLabel,
                    blocked: blocked,
                  )
                : r,
          )
          .toList();
    });

    final ok = await _parentService.setBlocked(
      packageName: packageName,
      blocked: blocked,
    );
    if (!ok) {
      if (!mounted) return;
      setState(() => _rules = previousRules);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update app block setting.')),
      );
      return;
    }
    await _loadParentRules();
  }

  Future<void> _applyPolicy({bool enableEnforcement = true}) async {
    await _parentService.applyLocalPolicy(
      socialMinutesLimit: socialMediaLimit ? _socialLimitMinutes : 999999,
      gamingMinutesLimit: gamingLimit ? _gamingLimitMinutes : 999999,
      entertainmentMinutesLimit: entertainmentLimit
          ? _entertainmentLimitMinutes
          : 999999,
      enableEnforcement: enableEnforcement,
    );
  }

  Future<void> _changeLimit({
    required String title,
    required int current,
    required ValueChanged<int> onSave,
  }) async {
    final controller = TextEditingController(text: current.toString());
    final value = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$title Limit (minutes)'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'Enter minutes'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final parsed = int.tryParse(controller.text.trim());
              if (parsed == null || parsed <= 0) return;
              Navigator.of(dialogContext).pop(parsed);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value == null) return;
    onSave(value);
    await _applyPolicy();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FC),
      body: SafeArea(
        child: ListView(
          padding: MindSyncLayout.pagePadding(context, top: 10, bottom: 100),
          children: [
            MindSyncHeader(
              onProfileTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                );
              },
              profileAvatarImageUrl: _faceImageUrl,
            ),
            const SizedBox(height: 16),

            // LIVE PROTECTION label
            const Text(
              'LIVE PROTECTION',
              style: TextStyle(
                fontSize: 12,
                letterSpacing: 1.5,
                color: Color(0xFFA1A1AA),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),

            // Title
            const Text(
              'Parent Control',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                height: 1.1,
                color: Color(0xFF18181B),
              ),
            ),
            const SizedBox(height: 14),

            // User Strip
            _UserStrip(userName: _loadingUser ? 'Loading...' : _displayName),
            const SizedBox(height: 20),

            if (!_hasAccessibility) ...[
              PermissionBanner(
                title: 'Accessibility Required',
                description:
                    'Parent controls need accessibility service to enforce app restrictions.',
                icon: Icons.accessibility_new,
                onAllow: () async {
                  await FeaturePermissionService.ensureAccessibility(context);
                },
              ),
              const SizedBox(height: 20),
            ],

            if (!_hasOverlay) ...[
              PermissionBanner(
                title: 'Overlay Required',
                description:
                    'MindSync needs "Display over other apps" permission to block restricted apps.',
                icon: Icons.layers,
                onAllow: () async {
                  await FeaturePermissionService.ensureOverlay(context);
                },
              ),
              const SizedBox(height: 20),
            ],

            // Usage Health Card
            _UsageHealthCard(userName: _loadingUser ? 'User' : _displayName),
            const SizedBox(height: 20),

            // Content Monitor Card
            _ContentMonitorCard(
              loading: _loadingContentMonitor,
              snapshot: _contentMonitor,
            ),
            const SizedBox(height: 20),

            // Content Time Restrictions Card
            _ContentTimeCard(
              socialMediaLimit: socialMediaLimit,
              gamingLimit: gamingLimit,
              entertainmentLimit: entertainmentLimit,
              socialLimitMinutes: _socialLimitMinutes,
              gamingLimitMinutes: _gamingLimitMinutes,
              entertainmentLimitMinutes: _entertainmentLimitMinutes,
              socialDnsStatus: _dnsStatus.socialStatus,
              gamingDnsStatus: _dnsStatus.gamingStatus,
              entertainmentDnsStatus: _dnsStatus.entertainmentStatus,
              onChangeSocialLimit: () => _changeLimit(
                title: 'Social Media',
                current: _socialLimitMinutes,
                onSave: (v) => setState(() => _socialLimitMinutes = v),
              ),
              onChangeGamingLimit: () => _changeLimit(
                title: 'Gaming',
                current: _gamingLimitMinutes,
                onSave: (v) => setState(() => _gamingLimitMinutes = v),
              ),
              onChangeEntertainmentLimit: () => _changeLimit(
                title: 'Entertainment',
                current: _entertainmentLimitMinutes,
                onSave: (v) => setState(() => _entertainmentLimitMinutes = v),
              ),
              onSocialChanged: _onSocialCategoryChanged,
              onGamingChanged: _onGamingCategoryChanged,
              onEntertainmentChanged: _onEntertainmentCategoryChanged,
            ),
            const SizedBox(height: 20),

            // App Restrictions Card
            _AppRestrictionsCard(
              loading: _loadingApps,
              rules: _rules,
              onRuleChanged: _toggleApp,
              appLimits: _appSocialLimits,
              onEditLimit: (rule) => _changeLimit(
                title: rule.appLabel,
                current:
                    _appSocialLimits[rule.packageName] ?? _socialLimitMinutes,
                onSave: (v) {
                  setState(() {
                    _appSocialLimits[rule.packageName] = v;
                  });
                },
              ),
            ),
            const SizedBox(height: 20),

            // Safety Controls Card
            _SafetyControlsCard(
              safeSearchActive: safeSearchActive,
              blockAdultContent: blockAdultContent,
              safeSearchStatus: _dnsStatus.safeSearchStatus,
              adultBlockStatus: _dnsStatus.adultBlockStatus,
              filterStatusLabel: _dnsStatus.filterStatusLabel,
              vpnActive: _dnsStatus.vpnActive,
              onSafeSearchChanged: _onSafeSearchChanged,
              onAdultBlockChanged: _onAdultBlockChanged,
            ),
          ],
        ),
      ),
    );
  }
}

// User Strip Widget
class _UserStrip extends StatelessWidget {
  const _UserStrip({required this.userName});

  final String userName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircleAvatar(
            radius: 16,
            backgroundColor: Color(0xFFE8D8CA),
            child: Icon(Icons.person, size: 16, color: Color(0xFF7A5036)),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                userName,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF18181B),
                ),
              ),
              const SizedBox(height: 2),
              const Row(
                children: [
                  Icon(Icons.circle, size: 6, color: Color(0xFF22C55E)),
                  SizedBox(width: 4),
                  Text(
                    'Online Now',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF71717A),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Usage Health Card with Ring — editable social media limit (12 h expiry)
class _UsageHealthCard extends StatefulWidget {
  const _UsageHealthCard({required this.userName});

  final String userName;

  @override
  State<_UsageHealthCard> createState() => _UsageHealthCardState();
}

class _UsageHealthCardState extends State<_UsageHealthCard> {
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    unawaited(SocialMediaUsageLimitStore.load());
    _countdownTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      if (SocialMediaUsageLimitStore.notifier.value.isActive) {
        setState(() {});
      } else {
        unawaited(SocialMediaUsageLimitStore.load());
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  int _socialUsageSeconds(ScreenTimeSnapshot snapshot) {
    if (snapshot.socialSeconds > 0) return snapshot.socialSeconds;
    return snapshot.topApps
        .where(
          (app) => SocialAppBranding.isSocialMediaApp(
            appName: app.appName,
            packageName: app.packageName,
          ),
        )
        .fold<int>(0, (sum, app) => sum + app.durationSeconds);
  }

  Future<void> _pickAndSaveLimit(int? currentLimitMinutes) async {
    var hours = (currentLimitMinutes ?? 120) ~/ 60;
    var minutes = (currentLimitMinutes ?? 120) % 60;

    final result = await showDialog<int?>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Social media daily limit'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Applies to social apps only (same as App Usage). '
                    'Limit expires 12 hours after you save it.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF71717A)),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: hours.clamp(0, 12),
                          decoration: const InputDecoration(labelText: 'Hours'),
                          items: List.generate(
                            13,
                            (i) =>
                                DropdownMenuItem(value: i, child: Text('$i h')),
                          ),
                          onChanged: (v) =>
                              setDialogState(() => hours = v ?? hours),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: (minutes ~/ 5) * 5,
                          decoration: const InputDecoration(
                            labelText: 'Minutes',
                          ),
                          items: List.generate(
                            12,
                            (i) => DropdownMenuItem(
                              value: i * 5,
                              child: Text('${i * 5} m'),
                            ),
                          ),
                          onChanged: (v) =>
                              setDialogState(() => minutes = v ?? minutes),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(null),
                  child: const Text('Cancel'),
                ),
                if (currentLimitMinutes != null)
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(0),
                    child: const Text('Remove limit'),
                  ),
                FilledButton(
                  onPressed: () {
                    final total = hours * 60 + minutes;
                    if (total <= 0) return;
                    Navigator.of(ctx).pop(total);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null || !mounted) return;
    if (result == 0) {
      await SocialMediaUsageLimitStore.clearLimit();
      return;
    }
    await SocialMediaUsageLimitStore.saveLimit(limitMinutes: result);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Social media limit set to ${_formatMinutes(result)} (expires in 12h)',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SocialMediaUsageLimitState>(
      valueListenable: SocialMediaUsageLimitStore.notifier,
      builder: (context, limitState, _) {
        return ValueListenableBuilder<ScreenTimeSnapshot>(
          valueListenable: ScreenTimeService.instance.snapshot,
          builder: (context, snapshot, _) {
            final usedSeconds = _socialUsageSeconds(snapshot);
            final usedMinutes = (usedSeconds / 60).ceil();
            final limitMinutes = limitState.limitMinutes;
            final hasLimit = limitState.isActive && limitMinutes != null;
            final activeLimit = limitMinutes ?? 0;
            final progress = hasLimit && activeLimit > 0
                ? (usedMinutes / activeLimit).clamp(0.0, 1.0)
                : 0.0;
            final pct = (progress * 100).round();

            return Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  if (limitState.showExpiredIndicator) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF4E5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE09100)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.schedule,
                            size: 16,
                            color: Color(0xFFE09100),
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Limit expired — no active social media cap',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF92400E),
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              unawaited(
                                SocialMediaUsageLimitStore.clearExpiredIndicator(),
                              );
                            },
                            child: const Text('Dismiss'),
                          ),
                        ],
                      ),
                    ),
                  ],
                  SizedBox(
                    height: 152,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          size: const Size(152, 152),
                          painter: _UsageRingPainter(progress: progress),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _formatMinutes(usedMinutes),
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF18181B),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              hasLimit
                                  ? 'OF ${_formatMinutes(activeLimit).toUpperCase()}'
                                  : 'NO LIMIT SET',
                              style: const TextStyle(
                                fontSize: 12,
                                letterSpacing: 1.2,
                                color: Color(0xFFA1A1AA),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Usage Health',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF18181B),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasLimit
                        ? '${widget.userName} is $pct% through the social media allowance.'
                        : 'Set a temporary social media daily limit (social apps only).',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFA1A1AA),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (hasLimit) ...[
                    const SizedBox(height: 8),
                    Text(
                      formatUsageHealthCountdown(limitState.remaining),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF8B5CF6),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _pickAndSaveLimit(hasLimit ? activeLimit : null),
                      icon: const Icon(Icons.edit_calendar, size: 18),
                      label: Text(
                        hasLimit
                            ? 'Edit social limit (${_formatMinutes(activeLimit)})'
                            : 'Set social media limit',
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _UsageRingPainter extends CustomPainter {
  const _UsageRingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.36;

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..color = const Color(0xFFEFF0F5)
      ..strokeCap = StrokeCap.round;

    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..color = progress >= 1.0
          ? const Color(0xFFE53935)
          : const Color(0xFF8B5CF6)
      ..strokeCap = StrokeCap.round;

    const startAngle = -1.8;
    const sweepTrack = 5.2;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepTrack,
      false,
      trackPaint,
    );

    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepTrack * progress.clamp(0.0, 1.0),
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _UsageRingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// Content Monitor Card
class _ContentMonitorCard extends StatelessWidget {
  const _ContentMonitorCard({required this.loading, required this.snapshot});

  final bool loading;
  final ParentContentMonitorSnapshot snapshot;

  static const _barColors = [
    Color(0xFF14B8A6),
    Color(0xFF8B5CF6),
    Color(0xFF3B82F6),
  ];

  @override
  Widget build(BuildContext context) {
    final items = snapshot.items;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text(
                'Content Monitor',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF18181B),
                ),
              ),
              Spacer(),
              Icon(Icons.monitor_heart, size: 18, color: Color(0xFF14B8A6)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            loading
                ? 'Loading content patterns...'
                : (snapshot.hasData
                      ? 'Top watched content types from analysed video chunks'
                      : (snapshot.message ??
                            'No data available for this period')),
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFFA1A1AA),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          if (loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (!snapshot.hasData || items.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F4F5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                snapshot.message ?? 'No data available for this period',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF71717A),
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            ...List.generate(items.length, (index) {
              final item = items[index];
              final pct = (item.percent / 100).clamp(0.0, 1.0);
              final color = _barColors[index % _barColors.length];
              return Padding(
                padding: EdgeInsets.only(
                  bottom: index < items.length - 1 ? 12 : 0,
                ),
                child: _MonitorBar(
                  label: item.label,
                  value: '${item.percent.toStringAsFixed(1)}%',
                  progress: pct,
                  color: color,
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _MonitorBar extends StatelessWidget {
  final String label;
  final String value;
  final double progress;
  final Color color;

  const _MonitorBar({
    required this.label,
    required this.value,
    required this.progress,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF3F3F46),
              ),
            ),
            const Spacer(),
            Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF52525B),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: const Color(0xFFEFF0F5),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

// Content Time Restrictions Card
class _ContentTimeCard extends StatelessWidget {
  final bool socialMediaLimit;
  final bool gamingLimit;
  final bool entertainmentLimit;
  final int socialLimitMinutes;
  final int gamingLimitMinutes;
  final int entertainmentLimitMinutes;
  final String socialDnsStatus;
  final String gamingDnsStatus;
  final String entertainmentDnsStatus;
  final VoidCallback onChangeSocialLimit;
  final VoidCallback onChangeGamingLimit;
  final VoidCallback onChangeEntertainmentLimit;
  final Future<void> Function(bool) onSocialChanged;
  final Future<void> Function(bool) onGamingChanged;
  final Future<void> Function(bool) onEntertainmentChanged;

  const _ContentTimeCard({
    required this.socialMediaLimit,
    required this.gamingLimit,
    required this.entertainmentLimit,
    required this.socialLimitMinutes,
    required this.gamingLimitMinutes,
    required this.entertainmentLimitMinutes,
    required this.socialDnsStatus,
    required this.gamingDnsStatus,
    required this.entertainmentDnsStatus,
    required this.onChangeSocialLimit,
    required this.onChangeGamingLimit,
    required this.onChangeEntertainmentLimit,
    required this.onSocialChanged,
    required this.onGamingChanged,
    required this.onEntertainmentChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Content\nRestrictions',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              height: 1.15,
              color: Color(0xFF18181B),
            ),
          ),
          const SizedBox(height: 18),
          _RestrictionRow(
            icon: Icons.people,
            iconBg: const Color(0xFFF3E8FF),
            iconColor: const Color(0xFF8B5CF6),
            title: 'Social Media',
            subtitle: 'Limit: ${_formatMinutes(socialLimitMinutes)}',
            statusText: socialDnsStatus,
            value: socialMediaLimit,
            onChanged: (v) => onSocialChanged(v),
            onSubtitleTap: onChangeSocialLimit,
          ),
          const SizedBox(height: 14),
          _RestrictionRow(
            icon: Icons.sports_esports,
            iconBg: const Color(0xFFEFF6FF),
            iconColor: const Color(0xFF3B82F6),
            title: 'Gaming',
            subtitle: 'Limit: ${_formatMinutes(gamingLimitMinutes)}',
            statusText: gamingDnsStatus,
            value: gamingLimit,
            onChanged: (v) => onGamingChanged(v),
            onSubtitleTap: onChangeGamingLimit,
          ),
          const SizedBox(height: 14),
          _RestrictionRow(
            icon: Icons.movie,
            iconBg: const Color(0xFFF0FDFA),
            iconColor: const Color(0xFF14B8A6),
            title: 'Entertainment',
            subtitle: 'Limit: ${_formatMinutes(entertainmentLimitMinutes)}',
            statusText: entertainmentDnsStatus,
            value: entertainmentLimit,
            onChanged: (v) => onEntertainmentChanged(v),
            onSubtitleTap: onChangeEntertainmentLimit,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onChangeSocialLimit,
              icon: const Icon(Icons.timer_outlined, size: 18),
              label: Text(
                'Set Social Media Limit (${_formatMinutes(socialLimitMinutes)})',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// App Restrictions Card
class _AppRestrictionsCard extends StatelessWidget {
  final bool loading;
  final List<ParentalAppRule> rules;
  final Future<void> Function(String packageName, bool blocked) onRuleChanged;
  final Map<String, int> appLimits;
  final Future<void> Function(ParentalAppRule rule) onEditLimit;

  const _AppRestrictionsCard({
    required this.loading,
    required this.rules,
    required this.onRuleChanged,
    required this.appLimits,
    required this.onEditLimit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text(
                'App Restrictions',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF18181B),
                ),
              ),
              Spacer(),
              Text(
                'View All +',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF8B5CF6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (loading)
            const Center(child: CircularProgressIndicator())
          else
            ...rules.take(10).map((rule) {
              final icon = _iconForPackage(rule.packageName, rule.appLabel);
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _AppRestrictionRow(
                  icon: icon.icon,
                  iconBg: icon.iconBg,
                  iconColor: icon.iconColor,
                  iconIsBrand: icon.isBrand,
                  title: rule.appLabel,
                  subtitle:
                      'Limit: ${_formatMinutes(appLimits[rule.packageName] ?? 0)}  •  ${rule.packageName}',
                  value: rule.blocked,
                  onChanged: (val) => onRuleChanged(rule.packageName, val),
                  onEditLimit: () => onEditLimit(rule),
                ),
              );
            }),
        ],
      ),
    );
  }
}

// Safety Controls Card
class _SafetyControlsCard extends StatelessWidget {
  final bool safeSearchActive;
  final bool blockAdultContent;
  final String safeSearchStatus;
  final String adultBlockStatus;
  final String filterStatusLabel;
  final bool vpnActive;
  final Future<void> Function(bool) onSafeSearchChanged;
  final Future<void> Function(bool) onAdultBlockChanged;

  const _SafetyControlsCard({
    required this.safeSearchActive,
    required this.blockAdultContent,
    required this.safeSearchStatus,
    required this.adultBlockStatus,
    required this.filterStatusLabel,
    required this.vpnActive,
    required this.onSafeSearchChanged,
    required this.onAdultBlockChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Safety Controls',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Color(0xFF18181B),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Icon(
                vpnActive ? Icons.shield : Icons.shield_outlined,
                size: 14,
                color: vpnActive ? Colors.green.shade600 : Colors.grey.shade500,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  filterStatusLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: vpnActive
                        ? Colors.green.shade700
                        : Colors.grey.shade600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SafetyRow(
            icon: Icons.search,
            iconBg: const Color(0xFFF0FDFA),
            iconColor: const Color(0xFF14B8A6),
            title: 'SafeSearch Active',
            subtitle: 'Filters explicit search results',
            statusText: safeSearchStatus,
            value: safeSearchActive,
            onChanged: (v) => onSafeSearchChanged(v),
          ),
          const SizedBox(height: 14),
          _SafetyRow(
            icon: Icons.block,
            iconBg: const Color(0xFFF3E8FF),
            iconColor: const Color(0xFF8B5CF6),
            title: 'Block Adult Content',
            subtitle: 'System-wide web filtering',
            statusText: adultBlockStatus,
            value: blockAdultContent,
            onChanged: (v) => onAdultBlockChanged(v),
          ),
        ],
      ),
    );
  }
}

// Reusable Restriction Row
class _RestrictionRow extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String? statusText;
  final bool value;
  final ValueChanged<bool> onChanged;
  final VoidCallback? onSubtitleTap;

  const _RestrictionRow({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.statusText,
    required this.value,
    required this.onChanged,
    this.onSubtitleTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: iconBg,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(icon, size: 18, color: iconColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF18181B),
                ),
              ),
              const SizedBox(height: 2),
              GestureDetector(
                onTap: onSubtitleTap,
                child: Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF71717A),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (statusText != null && statusText!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  statusText!,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF8B5CF6),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        Transform.scale(
          scale: 1,
          child: _BlockToggleButton(value: value, onChanged: onChanged),
        ),
      ],
    );
  }
}

String _formatMinutes(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m';
  return '${h}h ${m.toString().padLeft(2, '0')}m';
}

class _AppIconStyle {
  const _AppIconStyle(
    this.icon,
    this.iconBg,
    this.iconColor, {
    this.isBrand = false,
  });
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final bool isBrand;
}

_AppIconStyle _iconForPackage(String packageName, String appLabel) {
  final v = '$packageName ${appLabel.toLowerCase()}';
  if (v.contains('instagram')) {
    return const _AppIconStyle(
      FontAwesomeIcons.instagram,
      Color(0xFFFFEFFB),
      Color(0xFFB649A9),
      isBrand: true,
    );
  }
  if (v.contains('youtube')) {
    return const _AppIconStyle(
      FontAwesomeIcons.youtube,
      Color(0xFFFEF2F2),
      Color(0xFFEF4444),
      isBrand: true,
    );
  }
  if (v.contains('tiktok') || v.contains('musically') || v.contains('trill')) {
    return const _AppIconStyle(
      FontAwesomeIcons.tiktok,
      Color(0xFF1B1B1B),
      Colors.white,
      isBrand: true,
    );
  }
  if (v.contains('whatsapp')) {
    return const _AppIconStyle(
      FontAwesomeIcons.whatsapp,
      Color(0xFFEAF9EF),
      Color(0xFF25D366),
      isBrand: true,
    );
  }
  if (v.contains('snapchat')) {
    return const _AppIconStyle(
      FontAwesomeIcons.snapchat,
      Color(0xFFFFF9C4),
      Color(0xFFEFB700),
      isBrand: true,
    );
  }
  if (v.contains('facebook')) {
    return const _AppIconStyle(
      FontAwesomeIcons.facebook,
      Color(0xFFEAF0FF),
      Color(0xFF1877F2),
      isBrand: true,
    );
  }
  if (v.contains('twitter') || v.contains('x')) {
    return const _AppIconStyle(
      FontAwesomeIcons.xTwitter,
      Color(0xFFF2F2F2),
      Color(0xFF111111),
      isBrand: true,
    );
  }
  if (v.contains('discord')) {
    return const _AppIconStyle(
      Icons.forum_rounded,
      Color(0xFFF1F2FF),
      Color(0xFF5563D4),
    );
  }
  return const _AppIconStyle(
    Icons.apps_rounded,
    Color(0xFFF1F3F8),
    Color(0xFF5A5E6C),
  );
}

// App Restriction Row with limit text
class _AppRestrictionRow extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final bool iconIsBrand;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final VoidCallback onEditLimit;

  const _AppRestrictionRow({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    this.iconIsBrand = false,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.onEditLimit,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: iconBg,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Center(
            child: iconIsBrand
                ? FaIcon(icon, size: 16, color: iconColor)
                : Icon(icon, size: 18, color: iconColor),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF18181B),
                ),
              ),
              const SizedBox(height: 2),
              GestureDetector(
                onTap: onEditLimit,
                child: Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF71717A),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        _BlockToggleButton(value: value, onChanged: onChanged),
      ],
    );
  }
}

// Safety Row
class _SafetyRow extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String statusText;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SafetyRow({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.statusText,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: iconBg,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(icon, size: 18, color: iconColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF18181B),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF71717A),
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (statusText.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  statusText,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF14B8A6),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        _BlockToggleButton(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _BlockToggleButton extends StatelessWidget {
  const _BlockToggleButton({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final isBlocked = value;
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 92,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isBlocked ? const Color(0xFFFEF2F2) : const Color(0xFF8B5CF6),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isBlocked
                ? const Color(0xFFFCA5A5)
                : const Color(0xFF8B5CF6),
          ),
        ),
        child: Text(
          isBlocked ? 'Unblock' : 'Block',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isBlocked ? const Color(0xFFB91C1C) : Colors.white,
          ),
        ),
      ),
    );
  }
}

// Bottom Navigation Bar
