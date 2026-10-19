import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/upgrade_plan_catalog.dart';
import '../../services/app_public_service.dart';
import '../../services/subscription_service.dart';

class UpgradePlanScreen extends StatefulWidget {
  const UpgradePlanScreen({super.key});

  @override
  State<UpgradePlanScreen> createState() => _UpgradePlanScreenState();
}

class _UpgradePlanScreenState extends State<UpgradePlanScreen> {
  static const _accent = Color(0xFF6F39E8);

  late final AppPublicService _publicService;
  late final SubscriptionService _subscriptionService;

  List<SubscriptionPlanModel> _plans = UpgradePlanCatalog.bundledPlans();
  CurrentSubscriptionModel? _current =
      UpgradePlanCatalog.offlineFreeSubscription();
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _publicService = AppPublicService.instance;
    unawaited(_publicService.loadBranding());
    _subscriptionService = SubscriptionService.instance;
    unawaited(_loadData());
  }

  Future<void> _loadData() async {
    await _subscriptionService.hydrateFromCache();

    List<SubscriptionPlanModel> plans = UpgradePlanCatalog.bundledPlans();
    try {
      final remote = await _subscriptionService.getPlans();
      plans = UpgradePlanCatalog.mergeWithRemote(remote);
    } catch (_) {}

    CurrentSubscriptionModel? current =
        _subscriptionService.cachedCurrent ??
        UpgradePlanCatalog.offlineFreeSubscription();
    try {
      final live = await _subscriptionService.getCurrentSubscription(
        forceRefresh: false,
      );
      if (live != null) current = live;
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _plans = plans;
      _current = current;
      _selectedIndex = _indexForPlan(
        current?.effectivePlanCode ?? 'free',
        plans,
      ).clamp(0, plans.length - 1);
    });
  }

  int _indexForPlan(String code, List<SubscriptionPlanModel> plans) {
    final c = code.toLowerCase();
    final i = plans.indexWhere((p) => p.code.toLowerCase() == c);
    return i >= 0 ? i : 0;
  }

  Future<void> _openPricingWebsite() async {
    final uri = Uri.parse(mindSyncPricingUrl);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open the pricing page. Try again later.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _ctaLabel({
    required SubscriptionPlanModel selected,
    required String currentCode,
  }) {
    final selectedCode = selected.code.toLowerCase();
    final cur = currentCode.toLowerCase();
    if (selectedCode == cur) {
      return cur == 'free' ? 'Explore plans on web' : 'Renew on website';
    }
    if (selectedCode == 'free') return 'View plans on website';
    return 'Upgrade on website';
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedIndex >= _plans.length) _selectedIndex = 0;
    final selectedPlan = _plans[_selectedIndex];
    final currentCode = (_current?.effectivePlanCode ?? 'free').toLowerCase();
    final isCurrent = selectedPlan.code.toLowerCase() == currentCode;
    final onFreeTier = isCurrent && currentCode == 'free';
    final showRenew = isCurrent && currentCode != 'free';
    final showUpgrade = !isCurrent;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 18,
                          color: Color(0xFF6E6F7A),
                        ),
                      ),
                      const Spacer(),
                      ValueListenableBuilder<AppBrandingData>(
                        valueListenable: _publicService.branding,
                        builder: (context, branding, _) => Text(
                          branding.appName,
                          style: const TextStyle(
                            color: _accent,
                            fontWeight: FontWeight.w800,
                            fontSize: 22,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      const Spacer(),
                      const SizedBox(width: 22),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PLANS & PRICING',
                          style: TextStyle(
                            color: Color(0xFFE9D5FF),
                            fontSize: 11,
                            letterSpacing: 1.4,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Choose the right\nMindSync tier',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            height: 1.1,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Compare plans below. Subscribe or renew on our secure website — not inside the app.',
                          style: TextStyle(
                            color: Color(0xFFF3E8FF),
                            fontSize: 12.5,
                            height: 1.35,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _PlanTabs(
                    plans: _plans,
                    selectedIndex: _selectedIndex,
                    onChanged: (i) => setState(() => _selectedIndex = i),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE7E8EE)),
                    ),
                    child: Text(
                      'Current plan: ${_current?.plan.name ?? 'Free'} • '
                      '${(_current?.status ?? 'inactive').toUpperCase()}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF5B5E6B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _PlanCard(plan: selectedPlan, isCurrent: isCurrent),
                  const SizedBox(height: 24),
                  const Text(
                    'Compare benefits',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                      color: Color(0xFF14151D),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ..._plans.map((plan) => _Benefit(plan: plan)),
                ],
              ),
            ),
            if (showRenew || showUpgrade)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _openPricingWebsite,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(26),
                      ),
                    ),
                    child: Text(
                      showRenew
                          ? 'Renew on website'
                          : _ctaLabel(
                              selected: selectedPlan,
                              currentCode: currentCode,
                            ),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              )
            else if (onFreeTier)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F8F4),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: const Color(0xFFBBF7D0)),
                  ),
                  child: const Text(
                    'Current plan',
                    style: TextStyle(
                      color: Color(0xFF0E9186),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlanTabs extends StatelessWidget {
  const _PlanTabs({
    required this.plans,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<SubscriptionPlanModel> plans;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0F5),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children: [
          for (var i = 0; i < plans.length; i++)
            Expanded(
              child: _PlanTabChip(
                selected: selectedIndex == i,
                label: plans[i].name,
                onTap: () => onChanged(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlanTabChip extends StatelessWidget {
  const _PlanTabChip({
    required this.selected,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF6F39E8) : Colors.transparent,
          borderRadius: BorderRadius.circular(26),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : const Color(0xFF383944),
          ),
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.isCurrent,
  });

  final SubscriptionPlanModel plan;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final code = plan.code.toLowerCase();
    final isPremium = code == 'premium';
    final isFree = code == 'free';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isPremium
              ? const Color(0xFF6F39E8)
              : const Color(0xFFE5E5EA),
          width: isPremium ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: (isPremium ? const Color(0xFF6F39E8) : Colors.black)
                .withValues(alpha: isPremium ? 0.1 : 0.02),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
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
                      plan.name,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF14151D),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isFree
                          ? 'Always free in the app'
                          : '${plan.billingCycle.toUpperCase()} billing',
                      style: const TextStyle(
                        color: Color(0xFF747683),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (isPremium)
                _badge('BEST VALUE')
              else if (isFree)
                _badge('START HERE'),
            ],
          ),
          const SizedBox(height: 16),
          if (isFree)
            const Text(
              'Free',
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w800,
                color: Color(0xFF14151D),
              ),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '\$${plan.priceUsd.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    height: 1,
                    color: Color(0xFF14151D),
                  ),
                ),
                const SizedBox(width: 4),
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    '/mo',
                    style: TextStyle(
                      color: Color(0xFF747683),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 16),
          ...plan.features.take(10).map(
            (f) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle,
                    size: 16,
                    color: Color(0xFF0E9186),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      f.replaceAll('_', ' '),
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF4C4F61),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isCurrent) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFE8F8F4),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Your active plan',
                style: TextStyle(
                  color: Color(0xFF0E9186),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _badge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6F39E8), Color(0xFF8B5CF6)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({required this.plan});

  final SubscriptionPlanModel plan;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7E8EE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            plan.name,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: Color(0xFF14151D),
            ),
          ),
          const SizedBox(height: 8),
          ...plan.features.map(
            (f) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(Icons.check, size: 14, color: Color(0xFF0E9186)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      f.replaceAll('_', ' '),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF5B5E6B),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
