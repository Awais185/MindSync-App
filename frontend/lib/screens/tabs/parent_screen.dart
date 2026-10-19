import 'dart:async';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../services/dns_filter_service.dart';
import '../../services/parental_control_service.dart';
import '../../services/local_auth_service.dart';
import '../../services/plan_access_service.dart';
import '../../services/feature_permission_service.dart';
import '../../services/screen_time_service.dart';
import '../../services/social_media_usage_limit_store.dart';
import '../../services/parent_bedtime_schedule_service.dart';
import '../../services/notification_service.dart';
import '../../utils/social_app_branding.dart';

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
  String _onlineStatus = 'Online Now';
  int _socialLimitMinutes = 90;
  int _gamingLimitMinutes = 60;
  int _entertainmentLimitMinutes = 120;
  List<ParentalAppRule> _rules = const [];
  bool _loadingContentMonitor = false;
  ParentContentMonitorSnapshot _contentMonitor =
      ParentContentMonitorSnapshot.empty;

  // Bedtime schedule (visual state)
  TimeOfDay _sleepHour = const TimeOfDay(hour: 21, minute: 30);
  TimeOfDay _wakeUp = const TimeOfDay(hour: 7, minute: 0);

  // Content Restrictions — default unblocked
  bool socialMediaLimit = false;
  bool gamingLimit = false;
  bool entertainmentLimit = false;

  // Safety Controls
  bool safeSearchActive = false;
  bool blockAdultContent = false;
  DnsFilterStatus _dnsStatus = DnsFilterStatus.empty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
      unawaited(_recheckPermissionsSilent());
      unawaited(_loadParentRules());
    }
  }

  Future<void> _recheckPermissionsSilent() async {
    await ScreenTimeService.instance.hasAccessibilityService();
    await ScreenTimeService.instance.hasOverlayPermission();
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
    await _loadBedtimeSchedule();
    await _loadDnsFilterState();
  }

  Future<void> _loadBedtimeSchedule() async {
    final times = await ParentBedtimeScheduleService.loadTimes();
    if (!mounted) return;
    setState(() {
      _sleepHour = times.sleep;
      _wakeUp = times.wake;
    });
    await ParentBedtimeScheduleService.restoreNativeScheduleIfSaved();
    unawaited(NotificationService.instance.refresh(force: true));
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        title: const Text(
          'VPN permission required',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
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
            child: const Text(
              'OK',
              style: TextStyle(
                color: Color(0xFF6F39E8),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    return false;
  }

  /// Usage access, accessibility, and overlay — required before blocking an app.
  Future<bool> _ensureBlockingPermissions() async {
    final usage = await ScreenTimeService.instance.hasUsageAccess();
    if (!usage) {
      if (!mounted) return false;
      await FeaturePermissionService.ensureUsageAccess(context);
      if (!await ScreenTimeService.instance.hasUsageAccess()) return false;
    }
    final acc = await ScreenTimeService.instance.hasAccessibilityService();
    if (!acc) {
      if (!mounted) return false;
      await FeaturePermissionService.ensureAccessibility(context);
      final acc2 = await ScreenTimeService.instance.hasAccessibilityService();
      if (!acc2) return false;
    }
    final ovl = await ScreenTimeService.instance.hasOverlayPermission();
    if (!ovl) {
      if (!mounted) return false;
      await FeaturePermissionService.ensureOverlay(context);
      final ovl2 = await ScreenTimeService.instance.hasOverlayPermission();
      if (!ovl2) return false;
    }
    return true;
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
      _onlineStatus = 'Online Now';
      _loadingUser = false;
    });
  }

  Future<void> _loadParentRules() async {
    setState(() => _loadingApps = true);
    final rules = await _parentService.fetchRules();
    if (!mounted) return;
    setState(() {
      _rules = rules;
      _loadingApps = false;
    });
  }

  Future<void> _toggleApp(String packageName, bool blocked) async {
    // If blocking (not unblocking), ensure the mandatory permissions first.
    if (blocked) {
      final ok = await _ensureBlockingPermissions();
      if (!ok) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Enable Usage Access, Accessibility, and Overlay to block apps.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    final previousRules = _rules;
    final aliases = ParentalControlService.expandBlockedAliases(packageName);
    var appLabel = packageName;
    for (final r in _rules) {
      if (r.packageName == packageName) {
        appLabel = r.appLabel;
        break;
      }
    }
    setState(() {
      _rules = _rules
          .map(
            (r) => aliases.contains(r.packageName)
                ? r.copyWith(blocked: blocked, appLabel: appLabel)
                : r,
          )
          .toList();
    });

    final ok = await _parentService.setBlocked(
      packageName: packageName,
      blocked: blocked,
      appLabel: appLabel,
    );
    if (!ok) {
      if (!mounted) return;
      setState(() => _rules = previousRules);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update app block setting.')),
      );
      return;
    }
    final labelSnapshot = {
      for (final r in _rules) r.packageName: r.appLabel,
    };
    final rules = await _parentService.fetchRules(
      preserveLabelsByPackage: labelSnapshot,
    );
    if (!mounted) return;
    setState(() => _rules = rules);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          blocked
              ? '$appLabel is blocked'
              : '$appLabel is unblocked',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        title: Text(
          '$title Limit',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: 'Enter minutes',
            filled: true,
            fillColor: const Color(0xFFF5F3FC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(
                color: Color(0xFF6B6D79),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              final parsed = int.tryParse(controller.text.trim());
              if (parsed == null || parsed <= 0) return;
              Navigator.of(dialogContext).pop(parsed);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6F39E8),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: const Text(
              'Save',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
    if (value == null) return;
    onSave(value);
    await _applyPolicy();
  }

  Future<void> _editBedtimeSchedule() async {
    final sleep = await showTimePicker(
      context: context,
      initialTime: _sleepHour,
      helpText: 'Select sleep hour',
    );
    if (sleep == null || !mounted) return;
    final wake = await showTimePicker(
      context: context,
      initialTime: _wakeUp,
      helpText: 'Select wake-up time',
    );
    if (wake == null || !mounted) return;
    setState(() {
      _sleepHour = sleep;
      _wakeUp = wake;
    });
    await ParentBedtimeScheduleService.saveAndSchedule(
      sleep: sleep,
      wake: wake,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Bedtime and wake-up reminders scheduled for every day.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F1FB),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 100),
          children: [
            // LIVE PROTECTION pill
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 5,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(
                    Icons.circle,
                    size: 8,
                    color: Color(0xFF22C55E),
                  ),
                  SizedBox(width: 6),
                  Text(
                    'LIVE PROTECTION · ACTIVE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF15803D),
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // User strip (API data: name + status)
            _UserStrip(
              userName: _loadingUser ? 'Loading...' : _displayName,
              status: _onlineStatus,
            ),
            const SizedBox(height: 18),

            // Usage Health card
            _UsageHealthCard(
              userName: _loadingUser ? 'User' : _displayName,
            ),
            const SizedBox(height: 16),

            // Content Monitor card
            _ContentMonitorCard(
              loading: _loadingContentMonitor,
              snapshot: _contentMonitor,
            ),
            const SizedBox(height: 16),

            // App Restrictions card
            _AppRestrictionsCard(
              loading: _loadingApps,
              rules: _rules,
              onRuleChanged: _toggleApp,
            ),
            const SizedBox(height: 16),

            // Bedtime Schedule card
            _BedtimeScheduleCard(
              sleepHour: _sleepHour,
              wakeUp: _wakeUp,
              onEdit: _editBedtimeSchedule,
            ),
            const SizedBox(height: 16),

            // Safety Controls card
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
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// User strip — shows API name + status
// ---------------------------------------------------------------------------

class _UserStrip extends StatelessWidget {
  const _UserStrip({required this.userName, required this.status});
  final String userName;
  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              const CircleAvatar(
                radius: 20,
                backgroundColor: Color(0xFFF5F3FC),
                child: Icon(
                  Icons.person,
                  size: 20,
                  color: Color(0xFF6F39E8),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Color(0xFF22C55E),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, size: 10, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  userName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF18181B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  status,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF22C55E),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F3FC),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'iOS 17.4',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF6F39E8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Usage Health card
// ---------------------------------------------------------------------------

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

  Future<void> _resetUsageHealthLimit() async {
    await SocialMediaUsageLimitStore.clearLimit();
    await SocialMediaUsageLimitStore.clearExpiredIndicator();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Usage limit cleared. Social apps are unrestricted again.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _pickAndSaveLimit(int? currentLimitMinutes) async {
    var hours = (currentLimitMinutes ?? 120) ~/ 60;
    var minutes = (currentLimitMinutes ?? 120) % 60;

    final result = await showModalBottomSheet<int?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Drag handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE5E4EE),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F1FB),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.timer_outlined,
                            size: 20,
                            color: Color(0xFF6F39E8),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Set Usage Limit',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF18181B),
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Applies to social apps only. Limit expires 12 hours after you save it.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF71717A),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: _DurationPicker(
                            label: 'HOURS',
                            value: hours.clamp(0, 12),
                            max: 12,
                            onChanged: (v) =>
                                setModalState(() => hours = v),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _DurationPicker(
                            label: 'MINUTES',
                            value: (minutes ~/ 5) * 5,
                            max: 11,
                            step: 5,
                            onChanged: (v) =>
                                setModalState(() => minutes = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Live preview pill
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F1FB),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.schedule_rounded,
                            size: 18,
                            color: Color(0xFF6F39E8),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'New limit:',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF6B6E7A),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _formatMinutes(hours * 60 + minutes),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF6F39E8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        if (currentLimitMinutes != null)
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(ctx).pop(0),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFE53935),
                                side: const BorderSide(
                                  color: Color(0xFFFCA5A5),
                                  width: 1.4,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: const Text(
                                'Remove',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                        if (currentLimitMinutes != null)
                          const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: () {
                              final total = hours * 60 + minutes;
                              if (total <= 0) return;
                              Navigator.of(ctx).pop(total);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6F39E8),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text(
                              'Save Limit',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (result == null || !mounted) return;
    if (result == 0) {
      await _resetUsageHealthLimit();
      return;
    }
    await SocialMediaUsageLimitStore.saveLimit(limitMinutes: result);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Limit set to ${_formatMinutes(result)} (expires in 12h)',
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
            final remaining =
                hasLimit ? (activeLimit - usedMinutes).clamp(0, activeLimit) : 0;

            return Container(
              padding: const EdgeInsets.all(20),
              decoration: _sectionDecoration(),
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
                              'Limit expired — no active cap',
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
                                SocialMediaUsageLimitStore
                                    .clearExpiredIndicator(),
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
                        ? '${widget.userName} is $pct% of daily allowance. ${_formatMinutes(remaining)} balance remaining.'
                        : 'Set a temporary usage limit for social apps.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF8A8D99),
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                  if (hasLimit) ...[
                    const SizedBox(height: 6),
                    Text(
                      formatUsageHealthCountdown(limitState.remaining),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF8B5CF6),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          _pickAndSaveLimit(hasLimit ? activeLimit : null),
                      icon: Icon(
                        hasLimit ? Icons.edit_calendar : Icons.add_alarm,
                        size: 18,
                      ),
                      label: Text(
                        hasLimit
                            ? 'Edit Usage Limit (${_formatMinutes(activeLimit)})'
                            : 'Add Usage Limit',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6F39E8),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  ),
                  if (hasLimit) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: OutlinedButton(
                        onPressed: _resetUsageHealthLimit,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF6F39E8),
                          side: const BorderSide(color: Color(0xFFD6CCF4)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: const Text(
                          'Reset',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _DurationPicker extends StatelessWidget {
  const _DurationPicker({
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
    this.step = 1,
  });

  final String label;
  final int value;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F3FC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w800,
              color: Color(0xFF6F39E8),
            ),
          ),
          const SizedBox(height: 6),
          DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: value,
              isExpanded: true,
              icon: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Color(0xFF6F39E8),
              ),
              items: List.generate(max + 1, (i) {
                final v = step == 1 ? i : i * step;
                return DropdownMenuItem(
                  value: v,
                  child: Text(
                    step == 1 ? '$v' : '$v',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF18181B),
                    ),
                  ),
                );
              }),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ],
      ),
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
          : const Color(0xFF6F39E8)
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

// ---------------------------------------------------------------------------
// Content Monitor card — shows 4 sample placeholders with 0 value when no data
// ---------------------------------------------------------------------------

class _ContentMonitorCard extends StatelessWidget {
  const _ContentMonitorCard({required this.loading, required this.snapshot});

  final bool loading;
  final ParentContentMonitorSnapshot snapshot;

  static const _samplePlaceholders = [
    ('Education & Learning', Color(0xFF14B8A6)),
    ('Social Media', Color(0xFF6F39E8)),
    ('Gaming', Color(0xFF3B82F6)),
    ('Entertainment', Color(0xFFE09100)),
  ];

  @override
  Widget build(BuildContext context) {
    final items = snapshot.items;
    final hasRealData = !loading && snapshot.hasData && items.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _sectionDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text(
                'Content Monitor',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF18181B),
                  letterSpacing: -0.3,
                ),
              ),
              Spacer(),
              Icon(
                Icons.bar_chart_rounded,
                size: 18,
                color: Color(0xFF14B8A6),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Safe browsing & activity balance',
            style: TextStyle(
              fontSize: 12,
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
          else if (hasRealData)
            ...List.generate(items.length, (index) {
              final item = items[index];
              final pct = (item.percent / 100).clamp(0.0, 1.0);
              final color = _samplePlaceholders[index % _samplePlaceholders.length].$2;
              return Padding(
                padding: EdgeInsets.only(
                  bottom: index < items.length - 1 ? 12 : 0,
                ),
                child: _MonitorBar(
                  label: item.label,
                  value: '${item.percent.toStringAsFixed(0)}%',
                  progress: pct,
                  color: color,
                ),
              );
            })
          else
            // Placeholder rows with 0 value
            ...List.generate(_samplePlaceholders.length, (index) {
              final (label, color) = _samplePlaceholders[index];
              return Padding(
                padding: EdgeInsets.only(
                  bottom: index < _samplePlaceholders.length - 1 ? 12 : 0,
                ),
                child: _MonitorBar(
                  label: label,
                  value: '0%',
                  progress: 0.0,
                  color: color.withValues(alpha: 0.55),
                ),
              );
            }),
          // Protection status chips
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ProtectionChip(
                  icon: Icons.shield_outlined,
                  bg: const Color(0xFFFFF1F1),
                  fg: const Color(0xFFB91C1C),
                  title: 'Adult Risk',
                  subtitle: 'Protected',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ProtectionChip(
                  icon: Icons.check_circle_outline_rounded,
                  bg: const Color(0xFFFFFAEB),
                  fg: const Color(0xFFB45309),
                  title: 'Harmful Media',
                  subtitle: 'Filtered',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProtectionChip extends StatelessWidget {
  const _ProtectionChip({
    required this.icon,
    required this.bg,
    required this.fg,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color bg;
  final Color fg;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6B6E7A),
                  ),
                ),
              ],
            ),
          ),
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
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF2C2D36),
              ),
            ),
            const Spacer(),
            Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: color,
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

// ---------------------------------------------------------------------------
// App Restrictions — installed apps, native icons, block/unblock toggles
// ---------------------------------------------------------------------------

class _AppRestrictionsCard extends StatefulWidget {
  final bool loading;
  final List<ParentalAppRule> rules;
  final Future<void> Function(String packageName, bool blocked) onRuleChanged;

  const _AppRestrictionsCard({
    required this.loading,
    required this.rules,
    required this.onRuleChanged,
  });

  @override
  State<_AppRestrictionsCard> createState() => _AppRestrictionsCardState();
}

class _AppRestrictionsCardState extends State<_AppRestrictionsCard> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final visible =
        widget.rules.where((r) => r.appLabel.trim().isNotEmpty).toList();
    final displayCount = _showAll
        ? visible.length
        : visible.length.clamp(0, ParentalAppCatalog.collapsedCount);
    final displayed = visible.take(displayCount).toList();
    final canExpand = visible.length > ParentalAppCatalog.collapsedCount;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _sectionDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Text(
                'App Restrictions',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF18181B),
                  letterSpacing: -0.3,
                ),
              ),
              Spacer(),
              Text(
                'Restrict · Allow',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF6F39E8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Toggle ON to restrict one app. Default is OFF (allowed).',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFFA1A1AA),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          if (widget.loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (visible.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F3FC),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text(
                'No user apps detected yet. Enable Usage Access, then reopen '
                'this tab to refresh installed apps.',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF71717A),
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else ...[
            for (final rule in displayed) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _AppRestrictionRow(
                  rule: rule,
                  onChanged: (blocked) =>
                      widget.onRuleChanged(rule.packageName, blocked),
                ),
              ),
            ],
            if (canExpand && !_showAll)
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton(
                  onPressed: () => setState(() => _showAll = true),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF6F39E8),
                    side: const BorderSide(color: Color(0xFFD6CCF4), width: 1.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    'Show All Apps (${visible.length})',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            if (_showAll && canExpand)
              TextButton(
                onPressed: () => setState(() => _showAll = false),
                child: const Text(
                  'Show less',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF6F39E8),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bedtime Schedule card
// ---------------------------------------------------------------------------

class _BedtimeScheduleCard extends StatelessWidget {
  const _BedtimeScheduleCard({
    required this.sleepHour,
    required this.wakeUp,
    required this.onEdit,
  });

  final TimeOfDay sleepHour;
  final TimeOfDay wakeUp;
  final VoidCallback onEdit;

  String _fmt(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _sectionDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Bedtime Schedule',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF18181B),
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Automatic device rest during night hours',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFFA1A1AA),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _TimeTile(
                  label: 'SLEEP HOUR',
                  value: _fmt(sleepHour),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TimeTile(
                  label: 'WAKE UP',
                  value: _fmt(wakeUp),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton(
              onPressed: onEdit,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF6F39E8),
                side: const BorderSide(color: Color(0xFFD6CCF4), width: 1.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Edit Schedule',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeTile extends StatelessWidget {
  const _TimeTile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F3FC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w800,
              color: Color(0xFF6F39E8),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Color(0xFF18181B),
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Safety controls card
// ---------------------------------------------------------------------------

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
      decoration: _sectionDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Safety Controls',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF18181B),
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Real-time device-level defenses',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFFA1A1AA),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: vpnActive
                  ? const Color(0xFFDCFCE7)
                  : const Color(0xFFF5F3FC),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  vpnActive ? Icons.shield : Icons.shield_outlined,
                  size: 14,
                  color: vpnActive
                      ? const Color(0xFF15803D)
                      : const Color(0xFF71717A),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    filterStatusLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: vpnActive
                          ? const Color(0xFF15803D)
                          : const Color(0xFF71717A),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _SafetyRow(
            icon: Icons.search,
            iconBg: const Color(0xFFF0FDFA),
            iconColor: const Color(0xFF14B8A6),
            title: 'SafeSearch Active',
            subtitle: 'Filters explicit search engine hits',
            statusText: safeSearchStatus,
            value: safeSearchActive,
            onChanged: (v) => onSafeSearchChanged(v),
          ),
          const SizedBox(height: 14),
          _SafetyRow(
            icon: Icons.block,
            iconBg: const Color(0xFFF3E8FF),
            iconColor: const Color(0xFF6F39E8),
            title: 'Block Adult Sites',
            subtitle: 'System-wide real-time web filter',
            statusText: adultBlockStatus,
            value: blockAdultContent,
            onChanged: (v) => onAdultBlockChanged(v),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable rows
// ---------------------------------------------------------------------------

class _AppRestrictionRow extends StatelessWidget {
  final ParentalAppRule rule;
  final ValueChanged<bool> onChanged;

  const _AppRestrictionRow({
    required this.rule,
    required this.onChanged,
  });

  Widget _leadingIcon() {
    final bytes = rule.iconBytes;
    if (bytes != null && bytes.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(
          bytes,
          width: 42,
          height: 42,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _fallbackIcon(),
        ),
      );
    }
    return _fallbackIcon();
  }

  Widget _fallbackIcon() {
    final icon = _iconForPackage(rule.packageName, rule.appLabel);
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: icon.iconBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: icon.isBrand
            ? FaIcon(icon.icon, size: 18, color: icon.iconColor)
            : Icon(icon.icon, size: 20, color: icon.iconColor),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final blocked = rule.blocked;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F8FE),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _leadingIcon(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rule.appLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF18181B),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: blocked,
            onChanged: onChanged,
            activeColor: Colors.white,
            activeTrackColor: const Color(0xFFDC2626),
            inactiveTrackColor: const Color(0xFFE4E4E7),
          ),
        ],
      ),
    );
  }
}

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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F8FE),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: iconColor),
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
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF18181B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF71717A),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.white,
            activeTrackColor: const Color(0xFF6F39E8),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers & icons
// ---------------------------------------------------------------------------

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
  if (v.contains('twitter') || v.contains(' x')) {
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
  if (v.contains('roblox')) {
    return const _AppIconStyle(
      Icons.videogame_asset_rounded,
      Color(0xFFEAF0FF),
      Color(0xFF1877F2),
    );
  }
  return const _AppIconStyle(
    Icons.apps_rounded,
    Color(0xFFF1F3F8),
    Color(0xFF5A5E6C),
  );
}

// ---------------------------------------------------------------------------
// Card decorations
// ---------------------------------------------------------------------------

BoxDecoration _cardDecoration() {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(20),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.03),
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
    ],
  );
}

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