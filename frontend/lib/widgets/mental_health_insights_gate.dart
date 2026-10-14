import 'package:flutter/material.dart';

import '../services/plan_access_service.dart';
import '../services/wellness_dashboard_service.dart';

/// Access rules for Home mental health insights (stress / anxiety / depression).
class MentalHealthInsightsAccess {
  const MentalHealthInsightsAccess({
    required this.loading,
    required this.hasPaidPlan,
    required this.expressionCount,
    required this.minExpressionsRequired,
    required this.dashboard,
  });

  final bool loading;
  final bool hasPaidPlan;
  final int expressionCount;
  final int minExpressionsRequired;
  final WellnessDashboardData dashboard;

  bool get hasMinimumExpressions =>
      expressionCount >= minExpressionsRequired;

  bool get canShowInsights =>
      !loading && hasPaidPlan && dashboard.mentalHealth.hasData;

  String get insufficientDataMessage =>
      'Not enough data available to generate mental health insights.';

  String get upgradeMessage =>
      'Upgrade to a Basic or Premium plan to access Mental Health Insights.';
}

/// Loads subscription + wellness payload and exposes [MentalHealthInsightsAccess].
class MentalHealthInsightsGate extends StatefulWidget {
  const MentalHealthInsightsGate({
    super.key,
    required this.builder,
  });

  final Widget Function(BuildContext context, MentalHealthInsightsAccess access)
      builder;

  @override
  State<MentalHealthInsightsGate> createState() =>
      _MentalHealthInsightsGateState();
}

class _MentalHealthInsightsGateState extends State<MentalHealthInsightsGate> {
  bool _loadingPlan = true;
  bool _hasPaidPlan = false;

  @override
  void initState() {
    super.initState();
    _loadPlanAccess();
  }

  Future<void> _loadPlanAccess() async {
    try {
      final allowed =
          await PlanAccessService.instance.canAccessMentalHealthInsights();
      if (!mounted) return;
      setState(() {
        _hasPaidPlan = allowed;
        _loadingPlan = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasPaidPlan = false;
        _loadingPlan = false;
      });
    }
  }

  MentalHealthInsightsAccess _access(WellnessDashboardData dashboard) {
    final mh = dashboard.mentalHealth;
    return MentalHealthInsightsAccess(
      loading: _loadingPlan,
      hasPaidPlan: _hasPaidPlan,
      expressionCount: mh.expressionCount,
      minExpressionsRequired: mh.minExpressionsRequired,
      dashboard: dashboard,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<WellnessDashboardData>(
      valueListenable: WellnessDashboardService.instance.dashboard,
      builder: (context, dashboard, _) {
        return widget.builder(context, _access(dashboard));
      },
    );
  }
}

/// Shared placeholder card for locked or insufficient-data states.
class MentalHealthInsightsPlaceholderCard extends StatelessWidget {
  const MentalHealthInsightsPlaceholderCard({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.lock_outline,
    this.actionLabel,
    this.onAction,
    this.compact = false,
    this.embedded = false,
  });

  final String title;
  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;
  /// When true, renders content only (no outer card chrome). Use inside fixed-height home metric tiles.
  final bool embedded;

  Widget _buildContent(BuildContext context) {
    final titleSize = embedded ? 11.0 : (compact ? 12.0 : 22.0);
    final messageSize = embedded ? 10.0 : (compact ? 11.0 : 14.0);
    final iconSize = embedded ? 13.0 : (compact ? 14.0 : 18.0);
    final gapAfterTitle = embedded ? 4.0 : (compact ? 8.0 : 14.0);
    final actionGap = embedded ? 4.0 : 10.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(icon, size: iconSize, color: const Color(0xFF9A9BA6)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: titleSize,
                  letterSpacing: embedded ? 1.0 : 0,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1A2130),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: gapAfterTitle),
        Text(
          message,
          maxLines: embedded ? 2 : (compact ? 3 : 4),
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: messageSize,
            color: const Color(0xFF8A8D99),
            fontWeight: FontWeight.w600,
            height: 1.25,
          ),
        ),
        if (actionLabel != null && onAction != null) ...[
          SizedBox(height: actionGap),
          GestureDetector(
            onTap: onAction,
            child: Text(
              actionLabel!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: embedded ? 10 : 12,
                color: const Color(0xFF6F39E8),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (embedded) {
      return _buildContent(context);
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 12 : 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(compact ? 20 : 24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: _buildContent(context),
    );
  }
}
