import 'package:flutter/material.dart';

import '../../services/screen_time_service.dart';
import '../../widgets/behavioral_insights_modules.dart';
import '../../widgets/late_night_activity_widgets.dart';
import '../../models/late_night_sleep_snapshot.dart';

enum BehavioralInsightKind {
  behaviourStudy,
  facialExpressionStudy,
  contentType,
}

class BehavioralInsightDetailScreen extends StatelessWidget {
  const BehavioralInsightDetailScreen({
    super.key,
    required this.title,
    required this.kind,
    required this.rangeLabel,
    required this.behaviourStudy,
    required this.facialExpressionStudy,
    required this.contentTypeAnalysis,
    this.lateNightSleep = LateNightSleepSnapshot.empty,
  });

  final String title;
  final BehavioralInsightKind kind;
  final String rangeLabel;
  final BehaviourStudyData behaviourStudy;
  final FacialExpressionStudyData facialExpressionStudy;
  final ContentTypeAnalysisData contentTypeAnalysis;
  final LateNightSleepSnapshot lateNightSleep;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F6FA),
        elevation: 0,
        title: Text(
          title,
          style: const TextStyle(
            color: Color(0xFF1A1C24),
            fontWeight: FontWeight.w700,
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF6F39E8)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
        children: [
          _HeroCard(
            title: title,
            subtitle: 'Insights from your analysed sessions (${rangeLabel.toUpperCase()})',
          ),
          const SizedBox(height: 16),
          switch (kind) {
            BehavioralInsightKind.behaviourStudy =>
              ValueListenableBuilder<ScreenTimeSnapshot>(
                valueListenable: ScreenTimeService.instance.snapshot,
                builder: (context, snap, _) {
                  final merged = mergeLateNightSleepSources(
                    live: snap.lateNightSleep,
                    archive: lateNightSleep,
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BehaviourStudyDetailGrid(data: behaviourStudy),
                      LateNightActivityDetailSection(data: merged),
                    ],
                  );
                },
              ),
            BehavioralInsightKind.facialExpressionStudy =>
              FacialExpressionStudyDetailGrid(data: facialExpressionStudy),
            BehavioralInsightKind.contentType =>
              ContentTypeAnalysisDetailList(data: contentTypeAnalysis),
          },
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6F39E8), Color(0xFF8B5CF6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              color: Color(0xFFE8DEFF),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
