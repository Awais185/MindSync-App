import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../services/app_public_service.dart';
import '../../services/local_auth_service.dart';
import '../../services/subscription_service.dart';
import '../../models/plan_model.dart';
import '../payment_sheet_screen.dart';
import 'manual_bank_payment_screen.dart';

class UpgradePlanScreen extends StatefulWidget {
  const UpgradePlanScreen({super.key});

  @override
  State<UpgradePlanScreen> createState() => _UpgradePlanScreenState();
}

class _UpgradePlanScreenState extends State<UpgradePlanScreen> {
  late final AppPublicService _publicService;
  late final SubscriptionService _subscriptionService;
  late final LocalAuthService _auth;
  late Future<List<SubscriptionPlanModel>> _plansFuture;
  late Future<CurrentSubscriptionModel?> _currentFuture;
  late Future<AuthProfile?> _profileFuture;
  int selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _publicService = AppPublicService.instance;
    _subscriptionService = SubscriptionService.instance;
    _auth = LocalAuthService();
    _plansFuture = _subscriptionService.getPlans();
    _currentFuture =
        _subscriptionService.getCurrentSubscription(forceRefresh: true);
    _profileFuture = _auth.fetchCurrentUserProfile();
  }

  List<SubscriptionPlanModel> _visiblePlans(
    List<SubscriptionPlanModel> all,
    bool showDoctorPlan,
  ) {
    final allowed = showDoctorPlan
        ? {'basic', 'premium', 'doctor'}
        : {'basic', 'premium'};
    return all
        .where((p) => allowed.contains(p.code.toLowerCase()))
        .toList()
      ..sort((a, b) {
        const order = {'basic': 0, 'premium': 1, 'doctor': 2};
        return (order[a.code.toLowerCase()] ?? 99)
            .compareTo(order[b.code.toLowerCase()] ?? 99);
      });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: FutureBuilder<List<SubscriptionPlanModel>>(
          future: _plansFuture,
          builder: (context, plansSnap) {
            return FutureBuilder<AuthProfile?>(
              future: _profileFuture,
              builder: (context, profileSnap) {
                final showDoctorPlan =
                    profileSnap.data?.isApprovedDoctor ?? false;
                final plans = _visiblePlans(
                  plansSnap.data ?? const <SubscriptionPlanModel>[],
                  showDoctorPlan,
                );
                if (plans.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (selectedIndex >= plans.length) {
                  selectedIndex = 0;
                }

                final selectedPlan = plans[selectedIndex];
                return FutureBuilder<CurrentSubscriptionModel?>(
                  future: _currentFuture,
                  builder: (context, currentSnap) {
                    final current = currentSnap.data;
                    final currentPlanCode = (current?.effectivePlanCode ?? 'free')
                        .toLowerCase();
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      cacheExtent: 800,
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
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
                                  color: Color(0xFF6F39E8),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 24,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ),
                            const Spacer(),
                            const SizedBox(width: 22),
                          ],
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'UNLOCK SYNERGY',
                          style: TextStyle(
                            color: Color(0xFFA2A4AF),
                            letterSpacing: 1.5,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          showDoctorPlan
                              ? 'Choose your\nprofessional plan.'
                              : 'Choose your\njourney.',
                          style: const TextStyle(
                            fontSize: 36,
                            height: 1.05,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF14151D),
                            letterSpacing: -0.5,
                          ),
                        ),
                        if (showDoctorPlan) ...[
                          const SizedBox(height: 10),
                          const Text(
                            'Your admin-approved doctor account can subscribe to the Doctor plan for patient appointments and full clinical access.',
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.4,
                              color: Color(0xFF5B5E6B),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        _PlanTabs(
                          plans: plans,
                          selectedIndex: selectedIndex,
                          onChanged: (index) => setState(() => selectedIndex = index),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            'Current plan: ${current?.plan.name ?? 'Free'} • Status: ${(current?.status ?? 'inactive').toUpperCase()}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF5B5E6B),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        _PlanCard(
                          plan: selectedPlan,
                          currentPlanCode: currentPlanCode,
                          onBought: () {
                            setState(() {
                              _currentFuture =
                                  _subscriptionService.getCurrentSubscription();
                              _plansFuture = _subscriptionService.getPlans();
                            });
                          },
                        ),
                        const SizedBox(height: 28),
                        const Text(
                          'Compare Benefits',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 26,
                            color: Color(0xFF14151D),
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ...plans.map((plan) => _Benefit(plan: plan)),
                      ],
                    );
                  },
                );
              },
            );
          },
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
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: selectedIndex == i
                        ? const Color(0xFF6F39E8)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: Text(
                    plans[i].name,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: selectedIndex == i
                          ? Colors.white
                          : const Color(0xFF383944),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.currentPlanCode,
    required this.onBought,
  });

  final SubscriptionPlanModel plan;
  final String currentPlanCode;
  final VoidCallback onBought;

  @override
  Widget build(BuildContext context) {
    final code = plan.code.toLowerCase();
    final isPremium = code == 'premium';
    final isDoctor = code == 'doctor';
    final isCurrent = currentPlanCode == code;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isPremium || isDoctor
              ? const Color(0xFF6F39E8)
              : const Color(0xFFE5E5EA),
          width: isPremium || isDoctor ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: (isPremium || isDoctor)
                ? const Color(0xFF6F39E8).withValues(alpha: 0.1)
                : Colors.black.withValues(alpha: 0.02),
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
                      isDoctor
                          ? 'Clinical workspace • appointments'
                          : '${plan.billingCycle.toUpperCase()} plan',
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
              else if (isDoctor)
                _badge('DOCTOR'),
            ],
          ),
          const SizedBox(height: 16),
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
          ...plan.features.take(8).map(
            (f) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, size: 16, color: Color(0xFF0E9186)),
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
          const SizedBox(height: 16),
          if (isCurrent)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFE8F8F4),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Text(
                'Current plan',
                style: TextStyle(
                  color: Color(0xFF0E9186),
                  fontWeight: FontWeight.w800,
                ),
              ),
            )
          else ...[
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: kIsWeb
                    ? null
                    : () async {
                        final bought = await Navigator.of(context).push<bool>(
                          MaterialPageRoute(
                            builder: (_) => PaymentSheetScreen(
                              plan: PlanModel.fromSubscriptionPlan(plan),
                            ),
                          ),
                        );
                        if (bought == true) onBought();
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6F39E8),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                child: const Text(
                  'Pay with card',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ManualBankPaymentScreen(plan: plan),
                    ),
                  );
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF6F39E8),
                  side: const BorderSide(color: Color(0xFF6F39E8)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                child: const Text(
                  'Bank transfer',
                  style: TextStyle(fontWeight: FontWeight.w700),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6F39E8), Color(0xFF8B5CF6)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
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
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
