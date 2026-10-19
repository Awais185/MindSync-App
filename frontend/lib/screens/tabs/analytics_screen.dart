import 'dart:async';

import 'package:flutter/material.dart';
import '../../models/analytics_dashboard_payload.dart';
import '../../services/analytics_dashboard_service.dart';
import '../../services/tracking_permissions_gate.dart';
import '../../services/wellness_dashboard_service.dart';
import '../../utils/mental_health_severity.dart';
import '../pages/behavioral_insight_detail_screen.dart';
import '../pages/behaviour_study_day_screen.dart';
import '../pages/content_type_watch_screen.dart';
import 'home/home_hero_metrics.dart';

enum AnalyticsRange { week, day, month }

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  AnalyticsRange selected = AnalyticsRange.week;
  late Future<AnalyticsDashboardPayload> _dashboardFuture;
  Timer? _analyticsPoll;

  void _reloadDashboard() {
    setState(() {
      _dashboardFuture = AnalyticsDashboardService.instance.fetch(
        _rangeKey(selected),
      );
    });
  }

  @override
  void initState() {
    super.initState();
    unawaited(TrackingPermissionsGate.startScreenTimeIfPermitted());
    _dashboardFuture = AnalyticsDashboardService.instance.fetch(
      _rangeKey(selected),
    );
    unawaited(WellnessDashboardService.instance.refreshHome(force: true));
    _analyticsPoll = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      _reloadDashboard();
      unawaited(WellnessDashboardService.instance.refreshHome());
      unawaited(
        WellnessDashboardService.instance.refresh(
          days: kReportWellnessWindowDays,
        ),
      );
    });
  }

  @override
  void dispose() {
    _analyticsPoll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F1FB),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 100),
          children: [
                  // ---------- Header text ----------
                  const Text(
                    'WEEKLY DIGEST & TRENDS',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.4,
                      color: Color(0xFF6F39E8),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Focus & Balance',
                    style: TextStyle(
                      fontSize: 32,
                      height: 1.05,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF181A22),
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ---------- Range switch ----------
                  _RangeSwitch(
                    selected: selected,
                    onChanged: (value) {
                      selected = value;
                      _reloadDashboard();
                    },
                  ),
                  const SizedBox(height: 16),

                  FutureBuilder<AnalyticsDashboardPayload>(
                    future: _dashboardFuture,
                    builder: (context, dashSnap) {
                      final dash =
                          dashSnap.data ?? AnalyticsDashboardPayload.empty;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _MindSyncIndexHero(),
                          const SizedBox(height: 22),
                          Row(
                            children: [
                              const Text(
                                'BEHAVIOR',
                                style: TextStyle(
                                  fontSize: 11,
                                  letterSpacing: 1.4,
                                  color: Color(0xFF6F39E8),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                dash.periodLabel.isNotEmpty
                                    ? dash.periodLabel
                                    : 'Synced',
                                style: const TextStyle(
                                  fontSize: 11,
                                  letterSpacing: 0.4,
                                  color: Color(0xFF6F39E8),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _BehaviorGrid(
                            behavior: dash.behavior,
                            period: dash.period,
                          ),
                          const SizedBox(height: 22),
                          const _SectionLabel('RHYTHM DISTRIBUTION'),
                          const SizedBox(height: 8),
                          _RhythmDistributionCard(rhythm: dash.rhythm),
                          const SizedBox(height: 16),
                          _LateNightActivityCard(lateNight: dash.lateNight),
                          const SizedBox(height: 22),
                          const _SectionLabel('ACTIVITY ALLOCATION'),
                          const SizedBox(height: 8),
                          const _ActivityAllocationCard(),
                          const SizedBox(height: 22),
                          const Text(
                            'Behavioral Insights',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1D1F28),
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _BehavioralInsightSection(
                            dash: dash,
                            rangeLabel: _rangeKey(selected),
                          ),
                        ],
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }

  String _rangeKey(AnalyticsRange range) {
    return switch (range) {
      AnalyticsRange.day => 'day',
      AnalyticsRange.week => 'week',
      AnalyticsRange.month => 'month',
    };
  }
}

// ---------------------------------------------------------------------------
// Shared decorations
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        letterSpacing: 1.4,
        color: Color(0xFF6F39E8),
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Range switch
// ---------------------------------------------------------------------------

class _RangeSwitch extends StatelessWidget {
  const _RangeSwitch({required this.selected, required this.onChanged});

  final AnalyticsRange selected;
  final ValueChanged<AnalyticsRange> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildSwitchItem('Day', AnalyticsRange.day),
          _buildSwitchItem('Week', AnalyticsRange.week),
          _buildSwitchItem('Month', AnalyticsRange.month),
        ],
      ),
    );
  }

  Widget _buildSwitchItem(String text, AnalyticsRange value) {
    final isSelected = selected == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF6F39E8) : Colors.transparent,
            borderRadius: BorderRadius.circular(26),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color(0xFF6F39E8).withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              text,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF3A3B46),
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// MindSync Index hero (purple gradient)
// ---------------------------------------------------------------------------

class _BehavioralInsightSection extends StatelessWidget {
  const _BehavioralInsightSection({
    required this.dash,
    required this.rangeLabel,
  });

  final AnalyticsDashboardPayload dash;
  final String rangeLabel;

  @override
  Widget build(BuildContext context) {
    final behaviourSubtitle = 'Today · 30s scans & stress / emotion / depression';

    final facial = dash.facialExpressionStudy;
    final validTotal = facial.classes.fold<int>(
      0,
      (sum, row) => sum + ((row['valid_detections'] as num?)?.toInt() ?? 0),
    );

    const contentSubtitle =
        'Last 7 days · video tracking (gaming, education, social…)';

    return Column(
      children: [
        _InsightTile(
          icon: Icons.psychology_alt_rounded,
          iconBg: const Color(0xFFF0EBFF),
          iconColor: const Color(0xFF6F39E8),
          title: 'Behaviour Study',
          subtitle: behaviourSubtitle,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BehaviourStudyDayScreen()),
            );
          },
        ),
        const SizedBox(height: 12),
        _InsightTile(
          icon: Icons.face_retouching_natural_rounded,
          iconBg: const Color(0xFFDDF7F4),
          iconColor: const Color(0xFF0E9186),
          title: 'Facial Expression Study',
          subtitle: !facial.hasData
              ? 'No facial expression results yet.'
              : '$validTotal high-confidence signals (>0.50)',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BehavioralInsightDetailScreen(
                  title: 'Facial Expression Study',
                  kind: BehavioralInsightKind.facialExpressionStudy,
                  rangeLabel: rangeLabel,
                  behaviourStudy: dash.behaviourStudy,
                  facialExpressionStudy: dash.facialExpressionStudy,
                  contentTypeAnalysis: dash.contentTypeAnalysis,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        _InsightTile(
          icon: Icons.movie_filter_rounded,
          iconBg: const Color(0xFFFFF4E5),
          iconColor: const Color(0xFFE09100),
          title: 'Most Content Type',
          subtitle: contentSubtitle,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ContentTypeWatchScreen(),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _MindSyncIndexHero extends StatelessWidget {
  const _MindSyncIndexHero();

  String _stressCaption(double v) =>
      MentalHealthSeverity.labelFromPercent(v);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        WellnessDashboardService.instance.homeDashboard,
        WellnessDashboardService.instance.dashboard,
        WellnessDashboardService.instance.wellbeingDeltaPoints,
      ]),
      builder: (context, _) {
        final home = WellnessDashboardService.instance.homeDashboard.value;
        final report = WellnessDashboardService.instance.dashboard.value;
        final score = HomeHeroMetrics.resolveMindBalanceWellbeingScore(
          home,
          reportWindow: report,
        );
        final scoreText = score > 0 ? '$score' : '—';
        final delta = WellnessDashboardService.instance.wellbeingDeltaPoints.value;
        final trendLabel = delta == 0
            ? 'Live from your data'
            : delta >= 0
                ? '+$delta pts vs yesterday'
                : '$delta pts vs yesterday';

        final mh = home.mentalHealth;
        final stress = mh.hasData
            ? mh.stress.score
            : home.stressIndicator.toDouble();
        final depression = mh.hasData
            ? mh.depression.score
            : home.depressionIndicator.toDouble();
        final emotion = home.latestEmotion.isNotEmpty
            ? home.latestEmotion
            : report.latestEmotion;

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
            color: const Color(0xFF6F39E8).withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'MINDSYNC INDEX',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFD8C4FF),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(
                      Icons.spa_outlined,
                      size: 12,
                      color: Color(0xFF5EEAD4),
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Thriving & Calm',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Well-being Score',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFFE9D5FF),
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                scoreText,
                style: const TextStyle(
                  fontSize: 46,
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
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  delta >= 0
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                  size: 11,
                  color: delta >= 0
                      ? const Color(0xFFB9F0C0)
                      : const Color(0xFFFFB4B4),
                ),
                const SizedBox(width: 4),
                Text(
                  trendLabel,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _IndexTile(
                  icon: Icons.monitor_heart_outlined,
                  label: 'STRESS',
                  value: stress > 0
                      ? stress.round().toString()
                      : '—',
                  caption: stress > 0
                      ? _stressCaption(stress)
                      : 'No data',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _IndexTile(
                  icon: Icons.insights_rounded,
                  label: 'DEPRESSION',
                  value: depression > 0
                      ? depression.round().toString()
                      : '—',
                  caption: depression > 0
                      ? _stressCaption(depression)
                      : 'No data',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _IndexTile(
                  icon: Icons.emoji_emotions_outlined,
                  label: 'EMOTION',
                  value: emotion.isNotEmpty ? emotion : '—',
                  caption: emotion.isNotEmpty
                      ? 'Latest background scan'
                      : 'No data',
                  valueFontSize: emotion.length > 8 ? 13 : 18,
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

class _IndexTile extends StatelessWidget {
  const _IndexTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.caption,
    this.valueFontSize = 18,
  });

  final IconData icon;
  final String label;
  final String value;
  final String caption;
  final double valueFontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 11, color: const Color(0xFF5EEAD4)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFD8C4FF),
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: valueFontSize,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.3,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            caption,
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
}

// ---------------------------------------------------------------------------
// Behavior metrics grid
// ---------------------------------------------------------------------------

class _BehaviorGrid extends StatelessWidget {
  const _BehaviorGrid({required this.behavior, required this.period});

  final AnalyticsBehaviorMetrics behavior;
  final String period;

  String get _sleepTitle =>
      period == 'day' ? 'Sleep (last night)' : 'Sleep (avg / night)';

  String get _screenTitle => period == 'day'
      ? 'Daily Screen Time'
      : 'Avg. Daily Screen Time';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _VitalCard(
                icon: Icons.bedtime_outlined,
                iconBg: const Color(0xFFF0FDFA),
                iconColor: const Color(0xFF0E9186),
                topTag: '10 PM – 6 AM',
                topTagColor: const Color(0xFF0E9186),
                title: _sleepTitle,
                value: behavior.sleepDisplay,
                caption: 'Screen-off rest window',
                captionColor: const Color(0xFF15803D),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _VitalCard(
                icon: Icons.sentiment_satisfied_alt_rounded,
                iconBg: const Color(0xFFFFF4E5),
                iconColor: const Color(0xFFE09100),
                topTag: 'Mood',
                topTagColor: const Color(0xFFE09100),
                title: 'Mental Mood Score',
                value: behavior.moodScore > 0 ? '${behavior.moodScore}' : '—',
                caption: behavior.moodCaption.isNotEmpty
                    ? behavior.moodCaption
                    : 'Log moods to score',
                captionColor: const Color(0xFF15803D),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _VitalCard(
                icon: Icons.access_time_rounded,
                iconBg: const Color(0xFFF3E8FF),
                iconColor: const Color(0xFF6F39E8),
                topTag: 'Active',
                topTagColor: const Color(0xFF6F39E8),
                title: _screenTitle,
                value: behavior.avgDailyScreenDisplay,
                caption: 'Device usage aggregate',
                captionColor: const Color(0xFF6F39E8),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _VitalCard extends StatelessWidget {
  const _VitalCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.topTag,
    required this.topTagColor,
    required this.title,
    required this.value,
    required this.caption,
    required this.captionColor,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String topTag;
  final Color topTagColor;
  final String title;
  final String value;
  final String caption;
  final Color captionColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: topTagColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  topTag,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: topTagColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF8A8D99),
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF181A22),
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '• $caption',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: captionColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Daily Focus Rhythm card
// ---------------------------------------------------------------------------

class _RhythmDistributionCard extends StatelessWidget {
  const _RhythmDistributionCard({required this.rhythm});

  final AnalyticsRhythmChart rhythm;

  @override
  Widget build(BuildContext context) {
    final labels = rhythm.labels.length >= 7
        ? rhythm.labels.sublist(rhythm.labels.length - 7)
        : List<String>.from(rhythm.labels);
    final hours = rhythm.hoursPerDay.length >= 7
        ? rhythm.hoursPerDay.sublist(rhythm.hoursPerDay.length - 7)
        : List<double>.from(rhythm.hoursPerDay);
    while (labels.length < 7) {
      labels.add('');
    }
    while (hours.length < 7) {
      hours.add(0);
    }
    final maxH = hours.fold<double>(0, (a, b) => a > b ? a : b);
    final scale = maxH > 0 ? maxH : 1.0;
    var peakIndex = 0;
    for (var i = 0; i < hours.length; i++) {
      if (hours[i] >= hours[peakIndex]) peakIndex = i;
    }
    final peakLabel = rhythm.peakDayLabel.isNotEmpty
        ? '${rhythm.peakDayLabel} peak'
        : (labels[peakIndex].isNotEmpty ? '${labels[peakIndex]} peak' : '');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Screen Time Rhythm',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF181A22),
                  letterSpacing: -0.2,
                ),
              ),
              const Spacer(),
              if (peakLabel.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F1FB),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    peakLabel,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF6F39E8),
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Hours per day (0–24h scale)',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF8A8D99),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 158,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(7, (i) {
                final h = hours[i];
                final barH = (h / scale * 104).clamp(4.0, 104.0);
                final isPeak = i == peakIndex;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${h.toStringAsFixed(1)}h',
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 9,
                            height: 1.1,
                            fontWeight: FontWeight.w700,
                            color: isPeak
                                ? const Color(0xFF6F39E8)
                                : const Color(0xFF9B9EA9),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Container(
                          height: barH,
                          decoration: BoxDecoration(
                            color: isPeak
                                ? const Color(0xFF6F39E8)
                                : const Color(0xFFEDEBF7),
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          labels[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            height: 1.1,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF8A8D99),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF9F8FE),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF6F39E8),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    peakLabel.isNotEmpty
                        ? '$peakLabel · up to ${maxH.toStringAsFixed(1)}h'
                        : 'Screen time by weekday (rolling 7 days)',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2C2D36),
                    ),
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

// ---------------------------------------------------------------------------
// Late night activity (10 PM – 6 AM, screen-on only)
// ---------------------------------------------------------------------------

class _LateNightActivityCard extends StatelessWidget {
  const _LateNightActivityCard({required this.lateNight});

  final AnalyticsLateNightActivity lateNight;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Late Night Activity',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF181A22),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            lateNight.periodLabel.isNotEmpty
                ? '${lateNight.periodLabel} · 10 PM – 6 AM screen-on'
                : '10 PM – 6 AM screen-on time',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B6E7A),
            ),
          ),
          const SizedBox(height: 14),
          if (!lateNight.hasData)
            const Text(
              'No late-night screen activity recorded for this period.',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF6B6E7A),
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            )
          else ...[
            _lateRow(
              Icons.nightlight_round,
              'Total late-night use',
              lateNight.totalDisplay,
            ),
            const SizedBox(height: 10),
            if (lateNight.topAppName.isNotEmpty)
              _lateRow(
                Icons.apps_rounded,
                'Top app',
                '${lateNight.topAppName} · ${lateNight.topAppDisplay}',
              ),
            const SizedBox(height: 10),
            _lateRow(
              Icons.people_outline_rounded,
              'Social media',
              lateNight.socialDisplay,
            ),
          ],
        ],
      ),
    );
  }

  Widget _lateRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const Color(0xFF6F39E8)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF8A8D99),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF181A22),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Activity Allocation card
// ---------------------------------------------------------------------------

class _ActivityAllocationCard extends StatelessWidget {
  const _ActivityAllocationCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Text(
                'Activity Allocation',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF181A22),
                  letterSpacing: -0.2,
                ),
              ),
              Spacer(),
              Text(
                'Total: 29.5 hrs',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF8A8D99),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // Stacked bar
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Row(
              children: const [
                Expanded(
                  flex: 55,
                  child: SizedBox(
                    height: 12,
                    child: ColoredBox(color: Color(0xFF6F39E8)),
                  ),
                ),
                Expanded(
                  flex: 25,
                  child: SizedBox(
                    height: 12,
                    child: ColoredBox(color: Color(0xFF14B8A6)),
                  ),
                ),
                Expanded(
                  flex: 20,
                  child: SizedBox(
                    height: 12,
                    child: ColoredBox(color: Color(0xFFE09100)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _AllocRow(
            color: const Color(0xFF6F39E8),
            label: 'Deep Work & Productivity',
            time: '16h 15m',
            percent: '55%',
          ),
          const SizedBox(height: 12),
          _AllocRow(
            color: const Color(0xFF14B8A6),
            label: 'Mindful Rest & Meditation',
            time: '7h 25m',
            percent: '25%',
          ),
          const SizedBox(height: 12),
          _AllocRow(
            color: const Color(0xFFE09100),
            label: 'Social & Restorative Leisure',
            time: '5h 50m',
            percent: '20%',
          ),
        ],
      ),
    );
  }
}

class _AllocRow extends StatelessWidget {
  const _AllocRow({
    required this.color,
    required this.label,
    required this.time,
    required this.percent,
  });

  final Color color;
  final String label;
  final String time;
  final String percent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2C2D36),
            ),
          ),
        ),
        Text(
          time,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF6B6C76),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            percent,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Focus Session History
// ---------------------------------------------------------------------------

class _SessionHistoryCard extends StatelessWidget {
  const _SessionHistoryCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          _SessionRow(
            icon: Icons.bolt_rounded,
            iconBg: const Color(0xFFF3E8FF),
            iconColor: const Color(0xFF6F39E8),
            title: 'Deep Focus Session',
            subtitle: 'Completed · 45 mins · Alpha waves',
          ),
          const Divider(height: 1, color: Color(0xFFEFEFF4)),
          _SessionRow(
            icon: Icons.self_improvement_rounded,
            iconBg: const Color(0xFFF0FDFA),
            iconColor: const Color(0xFF14B8A6),
            title: 'Mindful Breathing',
            subtitle: 'Completed · 15 mins · Vagal reset',
          ),
          const Divider(height: 1, color: Color(0xFFEFEFF4)),
          _SessionRow(
            icon: Icons.nightlight_round,
            iconBg: const Color(0xFFFFF4E5),
            iconColor: const Color(0xFFE09100),
            title: 'Evening Reflection',
            subtitle: 'Completed · 10 mins · Mood +4',
          ),
        ],
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
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
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF181A22),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF8A8D99),
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: Color(0xFFBCBCC8),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Archived reports tile
// ---------------------------------------------------------------------------

class _ArchivedReportsTile extends StatelessWidget {
  const _ArchivedReportsTile();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F1FB),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.archive_outlined,
              size: 18,
              color: Color(0xFF6F39E8),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'View Archived Weekly Reports',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Color(0xFF181A22),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F1FB),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              '12',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Color(0xFF6F39E8),
              ),
            ),
          ),
          const SizedBox(width: 6),
          const Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 20,
            color: Color(0xFF8A8D99),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Behavioral Insight tile (kept for functionality)
// ---------------------------------------------------------------------------

class _InsightTile extends StatelessWidget {
  const _InsightTile({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, size: 22, color: iconColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1D1F28),
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF838391),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: Color(0xFFBCBCC8),
            ),
          ],
        ),
      ),
    );
  }
}