import 'package:flutter/material.dart';

import '../../services/plan_access_service.dart';
import '../../services/recommendations_service.dart';
import '../../ui/components/mind_sync_header.dart';
import '../../ui/layout/mindsync_layout.dart';
import 'profile_screen.dart';
import '../main_shell_screen.dart';
import 'face_scan_screen.dart';
import 'report_screen.dart';

class RecommendationScreen extends StatefulWidget {
  const RecommendationScreen({super.key});

  @override
  State<RecommendationScreen> createState() => _RecommendationScreenState();
}

class _RecommendationScreenState extends State<RecommendationScreen> {
  late Future<WellnessRecommendationResponse> _recommendationsFuture;

  @override
  void initState() {
    super.initState();
    _recommendationsFuture = _fetchWithAccessCheck();
  }

  Future<WellnessRecommendationResponse> _fetchWithAccessCheck() async {
    final allowed = await PlanAccessService.instance.canAccess(
      'personalized_suggestions',
      forceRefresh: true,
    );
    if (!allowed) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Upgrade your plan to access this feature.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return WellnessRecommendationResponse.empty;
    }
    return RecommendationsService.instance.fetchRecommendations(range: 'week');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: ListView(
          padding: MindSyncLayout.pagePadding(context, top: 16, bottom: 100),
          children: [
            MindSyncHeader(
              onBack: () => Navigator.of(context).pop(),
              onProfileTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                );
              },
            ),
            const SizedBox(height: 20),

            // Title Section
            const Text(
              'Sanctuary\nRecommendations',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                height: 1.1,
                color: Color(0xFF161820),
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Curated for your wellbeing',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF747683),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 20),

            FutureBuilder<WellnessRecommendationResponse>(
              future: _recommendationsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const _RecLoading();
                }
                if (snapshot.hasError) {
                  return _RecError(
                    onRetry: () {
                      setState(() {
                        _recommendationsFuture = _fetchWithAccessCheck();
                      });
                    },
                  );
                }
                final modelOutput =
                    snapshot.data ?? WellnessRecommendationResponse.empty;
                final recs = modelOutput.cards;
                if (recs.isEmpty) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Text(
                      'No AI recommendations available yet. Try again after more behavioral data is collected.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: Color(0xFF676B79),
                      ),
                    ),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _RiskSummaryCard(
                      riskLevel: modelOutput.riskLevel,
                      mainIssues: modelOutput.mainIssues,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Personalized Recommendations',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                        height: 1.2,
                        color: Color(0xFF161820),
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...recs.map(
                      (r) => _RecommendationCard(
                        title: r.title,
                        description: r.description,
                        category: r.category,
                        priority: r.priority,
                        action: r.action,
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                );
              },
            ),

            // Tip of the Day Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF6F39E8), Color(0xFF8B5CF6)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6F39E8).withOpacity(0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'TIP OF THE DAY',
                    style: TextStyle(
                      color: Color(0xFFE0D4FF),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'The 20-20-20 Rule',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      height: 1,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Every 20 minutes, look at something 20 feet away for 20 seconds to significantly reduce digital eye strain.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () => _showTipDetails(context),
                    child: const Text(
                      'Learn More →',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Daily Rhythm Section
            const Text(
              'Daily Rhythm',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 20,
                color: Color(0xFF161820),
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 12),

            // Morning Walk
            _MiniTile(
              title: 'Morning Walk',
              subtitle: '15-minute gentle walk to boost mood',
              rating: '4.8',
              ratingColor: const Color(0xFFFBBF24),
              icon: Icons.directions_walk,
              iconBg: const Color(0xFFDDF7F4),
              iconColor: const Color(0xFF0E9186),
            ),
            const SizedBox(height: 8),

            // Phone-Free Hour
            _MiniTile(
              title: 'Phone-Free Hour',
              subtitle: 'Break from digital noise for clarity',
              trailing: '+',
              icon: Icons.phone_iphone,
              iconBg: const Color(0xFFF0EBFF),
              iconColor: const Color(0xFF6F39E8),
            ),
            const SizedBox(height: 8),

            // Connect with Loved Ones
            _MiniTile(
              title: 'Connect with Loved Ones',
              subtitle: 'Spend quality time with friends or family',
              trailing: '›',
              icon: Icons.people,
              iconBg: const Color(0xFFE8F0FE),
              iconColor: const Color(0xFF3B82F6),
            ),
            const SizedBox(height: 24),

            // Curated Content Section
            const Text(
              'Curated Content',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 20,
                color: Color(0xFF161820),
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 12),

            // Guided Meditation
            _ContentTile(
              title: 'Guided Meditation for Focus',
              duration: '10 MIN AUDIO',
              onTap: () => _playContent(context, 'Guided Meditation for Focus'),
            ),
            const SizedBox(height: 12),

            // Deep Sleep
            _ContentTile(
              title: 'The Art of Deep Sleep',
              duration: '15 MIN AUDIO',
              onTap: () => _playContent(context, 'The Art of Deep Sleep'),
            ),
            const SizedBox(height: 24),

            // Explore Topics Section
            const Text(
              'Explore Topics',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 20,
                color: Color(0xFF161820),
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 12),

            // Topics Grid
            Row(
              children: [
                Expanded(
                  child: _TopicBox(
                    text: 'Sleep',
                    color: const Color(0xFFE8DDFC),
                    icon: Icons.bedtime,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TopicBox(
                    text: 'Anxiety',
                    color: const Color(0xFFD4F8F3),
                    icon: Icons.psychology,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _TopicBox(
                    text: 'Focus',
                    color: const Color(0xFFE8F0FE),
                    icon: Icons.center_focus_strong,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TopicBox(
                    text: 'Relax',
                    color: const Color(0xFFF3F4F6),
                    icon: Icons.spa,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Save for Later Section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
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
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0EBFF),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.bookmark_border,
                      color: Color(0xFF6F39E8),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Save for Later',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: Color(0xFF161820),
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Bookmark your favorite recommendations',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF8F919C),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Color(0xFFC5C6D0)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Share Tips Section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF0E9186).withOpacity(0.1),
                    const Color(0xFF6F39E8).withOpacity(0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: const Color(0xFF6F39E8).withOpacity(0.2),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6F39E8), Color(0xFF8B5CF6)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.share,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Share Tips',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: Color(0xFF161820),
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Share wellness tips with your community',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF8F919C),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward,
                    color: Color(0xFF6F39E8),
                    size: 20,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTipDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      backgroundColor: Colors.white,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 60,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E5EA),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'The 20-20-20 Rule',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Color(0xFF161820),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'What it is:',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            const SizedBox(height: 4),
            const Text(
              'The 20-20-20 rule is an eye exercise that helps reduce digital eye strain caused by prolonged screen use.',
              style: TextStyle(fontSize: 13, color: Color(0xFF525563)),
            ),
            const SizedBox(height: 12),
            const Text(
              'How to practice:',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            const SizedBox(height: 4),
            const Text(
              '• Every 20 minutes\n• Look at something 20 feet away\n• For 20 seconds',
              style: TextStyle(fontSize: 13, color: Color(0xFF525563)),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6F39E8),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text(
                  'Got it',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _playContent(BuildContext context, String title) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Playing: $title'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF6F39E8),
      ),
    );
  }
}

class _RecLoading extends StatelessWidget {
  const _RecLoading();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Text(
          'Personalized Recommendations',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 20,
            height: 1.2,
            color: Color(0xFF161820),
            letterSpacing: -0.3,
          ),
        ),
        SizedBox(height: 12),
        _SkeletonRecCard(),
        SizedBox(height: 12),
        _SkeletonRecCard(),
      ],
    );
  }
}

class _SkeletonRecCard extends StatelessWidget {
  const _SkeletonRecCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 14, width: 220, color: const Color(0xFFEDEEF2)),
          const SizedBox(height: 10),
          Container(height: 10, width: 300, color: const Color(0xFFF2F3F7)),
          const SizedBox(height: 8),
          Container(height: 10, width: 260, color: const Color(0xFFF2F3F7)),
          const SizedBox(height: 18),
          Container(
            height: 40,
            width: double.infinity,
            color: const Color(0xFFF0F1F5),
          ),
        ],
      ),
    );
  }
}

class _RecError extends StatelessWidget {
  const _RecError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Could not load recommendations',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Check your connection and try again.',
            style: TextStyle(fontSize: 12, color: Color(0xFF7C7F8C)),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF6F39E8)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: const Text(
                'Retry',
                style: TextStyle(
                  color: Color(0xFF6F39E8),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({
    required this.title,
    required this.description,
    required this.category,
    required this.priority,
    required this.action,
  });

  final String title;
  final String description;
  final String category;
  final String priority;
  final RecommendationAction action;

  Color get _accent => switch (priority) {
    'High' => const Color(0xFFEF4444),
    'Medium' => const Color(0xFF8B5CF6),
    _ => const Color(0xFF9DA0AB),
  };

  @override
  Widget build(BuildContext context) {
    final accent = _accent;
    final gradient = switch (priority) {
      'High' => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF6F39E8), Color(0xFFEF4444)],
      ),
      'Medium' => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF6F39E8), Color(0xFF22C55E)],
      ),
      _ => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF9DA0AB), Color(0xFFE3E4EA)],
      ),
    };

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: gradient,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$priority Priority',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  category,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6B6E7B),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFF161820),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: const TextStyle(
                fontSize: 12,
                height: 1.45,
                fontWeight: FontWeight.w500,
                color: Color(0xFF4C4F61),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final type = action.type;
                  if (type == 'set_app_limits') {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const MainShellScreen(initialTab: 2),
                      ),
                    );
                    return;
                  }

                  if (type == 'face_rescan') {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const FaceScanScreen()),
                    );
                    return;
                  }

                  if (type == 'reduce_toxic_content') {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ReportScreen()),
                    );
                    return;
                  }

                  if (type == 'breathing_exercise') {
                    showModalBottomSheet(
                      context: context,
                      showDragHandle: true,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(28),
                        ),
                      ),
                      builder: (_) => const _BreathingExerciseSheet(),
                    );
                    return;
                  }

                  if (type == 'start_meditation') {
                    showModalBottomSheet(
                      context: context,
                      showDragHandle: true,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(28),
                        ),
                      ),
                      builder: (_) => const _MeditationSheet(),
                    );
                    return;
                  }

                  if (type == 'digital_detox') {
                    showModalBottomSheet(
                      context: context,
                      showDragHandle: true,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(28),
                        ),
                      ),
                      builder: (_) => const _DigitalDetoxSheet(),
                    );
                    return;
                  }

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(action.label),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: const Color(0xFF6F39E8),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6F39E8),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(
                  action.label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
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

class _RiskSummaryCard extends StatelessWidget {
  const _RiskSummaryCard({required this.riskLevel, required this.mainIssues});
  final String riskLevel;
  final List<String> mainIssues;

  Color get _accent => switch (riskLevel.toLowerCase()) {
    'high' => const Color(0xFFEF4444),
    'moderate' => const Color(0xFFF59E0B),
    'low' => const Color(0xFF22C55E),
    _ => const Color(0xFF6F39E8),
  };

  @override
  Widget build(BuildContext context) {
    final accent = _accent;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Risk Level',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF4C4F61),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  riskLevel.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
          if (mainIssues.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              'Main Issues',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Color(0xFF161820),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: mainIssues
                  .map(
                    (issue) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F8),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        issue,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF4D5160),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _BreathingExerciseSheet extends StatelessWidget {
  const _BreathingExerciseSheet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Breathing Exercise',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Try 4-4-6 box breathing:',
            style: TextStyle(fontSize: 13, color: Color(0xFF4C4F61)),
          ),
          const SizedBox(height: 10),
          const _BreathingStep(title: 'Inhale', subtitle: '4 seconds'),
          const _BreathingStep(title: 'Hold', subtitle: '4 seconds'),
          const _BreathingStep(title: 'Exhale', subtitle: '6 seconds'),
          const _BreathingStep(title: 'Hold', subtitle: '2 seconds'),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Breathing started. Take it slow.'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6F39E8),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: const Text(
                'Start',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MeditationSheet extends StatelessWidget {
  const _MeditationSheet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Guided Meditation',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'A short calm session to reduce stress before sleep or work.',
            style: TextStyle(fontSize: 13, color: Color(0xFF4C4F61)),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Text(
              'Tip: Sit comfortably, soften your gaze, and breathe slowly.',
              style: TextStyle(fontSize: 13, color: Color(0xFF4C4F61)),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Meditation started (demo).'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6F39E8),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: const Text(
                'Start Meditation',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DigitalDetoxSheet extends StatelessWidget {
  const _DigitalDetoxSheet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Digital Detox',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Try a 15-minute break: put your phone face-down and do one calm activity.',
            style: TextStyle(fontSize: 13, color: Color(0xFF4C4F61)),
          ),
          const SizedBox(height: 12),
          const _DetoxTip(text: 'Dim brightness to 40%'),
          const _DetoxTip(text: 'Mute social apps for 15 minutes'),
          const _DetoxTip(text: 'Replace scrolling with a short checklist'),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Detox timer started (demo).'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6F39E8),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: const Text(
                'Start Detox',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BreathingStep extends StatelessWidget {
  const _BreathingStep({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: const Color(0xFFEDE9FE),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              title == 'Inhale'
                  ? Icons.arrow_upward_rounded
                  : title == 'Exhale'
                  ? Icons.arrow_downward_rounded
                  : title == 'Hold'
                  ? Icons.pause_circle_outline_rounded
                  : Icons.pause_circle_outline_rounded,
              size: 16,
              color: const Color(0xFF6F39E8),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF161820),
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B6E7B),
                    fontWeight: FontWeight.w500,
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

class _DetoxTip extends StatelessWidget {
  const _DetoxTip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            size: 16,
            color: Color(0xFF6F39E8),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF4C4F61),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniTile extends StatelessWidget {
  const _MiniTile({
    required this.title,
    required this.subtitle,
    this.rating,
    this.ratingColor,
    this.trailing,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
  });

  final String title;
  final String subtitle;
  final String? rating;
  final Color? ratingColor;
  final String? trailing;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, size: 24, color: iconColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: Color(0xFF161820),
                      ),
                    ),
                    if (rating != null) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.star, size: 12, color: ratingColor),
                      const SizedBox(width: 4),
                      Text(
                        rating!,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: ratingColor,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF8F919C),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6F39E8),
              ),
            ),
          if (trailing == null)
            const Icon(Icons.chevron_right, size: 20, color: Color(0xFFC5C6D0)),
        ],
      ),
    );
  }
}

class _ContentTile extends StatelessWidget {
  const _ContentTile({
    required this.title,
    required this.duration,
    required this.onTap,
  });

  final String title;
  final String duration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 100,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1E293B), Color(0xFF334155)],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              duration,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TopicBox extends StatelessWidget {
  const _TopicBox({
    required this.text,
    required this.color,
    required this.icon,
  });

  final String text;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exploring $text topics'),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF6F39E8),
          ),
        );
      },
      child: Container(
        height: 70,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: const Color(0xFF4B5563)),
            const SizedBox(height: 6),
            Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1F2937),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
