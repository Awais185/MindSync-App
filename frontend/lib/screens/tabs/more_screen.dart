import 'dart:async';

import 'package:flutter/material.dart';
import '../main_shell_screen.dart';
import '../auth/login_screen.dart';
import '../pages/community_screen.dart';
import '../pages/emergency_screen.dart';
import '../pages/face_scan_screen.dart';
import '../pages/profile_screen.dart';
import '../pages/recommendation_screen.dart';
import '../pages/upgrade_plan_screen.dart';
import '../pages/doctor_inbox_screen.dart';
import '../../services/local_auth_service.dart';
import '../../services/screen_time_service.dart';
import '../../services/recommendations_service.dart';
import '../../services/subscription_service.dart';
import '../../services/user_session_cache.dart';
import '../../ui/components/mind_sync_header.dart';
import '../../ui/layout/mindsync_layout.dart';

class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> with AutomaticKeepAliveClientMixin {
  final _auth = LocalAuthService();
  AuthProfile? _profile;
  late Future<WellnessRecommendationResponse> _recommendationsFuture;
  VoidCallback? _sessionListener;
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _refreshRecommendationsFuture();
    _loadProfile();
    _sessionListener = _onUserSessionChanged;
    UserSessionCache.sessionGeneration.addListener(_sessionListener!);
    unawaited(
      SubscriptionService.instance.getCurrentSubscription(forceRefresh: true),
    );
  }

  @override
  void dispose() {
    if (_sessionListener != null) {
      UserSessionCache.sessionGeneration.removeListener(_sessionListener!);
    }
    super.dispose();
  }

  void _onUserSessionChanged() {
    _refreshRecommendationsFuture();
    unawaited(_loadProfile());
  }

  void _refreshRecommendationsFuture() {
    _recommendationsFuture = RecommendationsService.instance
        .fetchRecommendations(range: 'week');
    if (mounted) setState(() {});
  }

  Future<void> _loadProfile() async {
    final profile = await _auth.fetchCurrentUserProfile();
    if (!mounted) return;
    setState(() => _profile = profile);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          cacheExtent: 1200,
          padding: MindSyncLayout.pagePadding(context, top: 10, bottom: 100),
          children: [
            MindSyncHeader(
              onProfileTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                );
              },
              profileAvatarImageUrl: _profile?.faceImage,
            ),
            const SizedBox(height: 24),

            // Profile Section (name + email; opens profile settings)
            GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                );
              },
              behavior: HitTestBehavior.opaque,
              child: Center(
                child: Column(
                  children: [
                    Text(
                      _profile?.fullName ??
                          _profile?.displayName ??
                          'MindSync User',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF161820),
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _profile?.email ?? 'No email found',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF868894),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            FutureBuilder<WellnessRecommendationResponse>(
              future: _recommendationsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
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
                      children: const [
                        SizedBox(height: 4),
                        Text(
                          'Top Recommendation',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF9DA0AB),
                          ),
                        ),
                        SizedBox(height: 12),
                        SizedBox(height: 16, width: 240),
                        SizedBox(height: 10, width: 280),
                        SizedBox(height: 16),
                        SizedBox(height: 44, width: double.infinity),
                      ],
                    ),
                  );
                }
                final recs =
                    (snapshot.data ?? WellnessRecommendationResponse.empty).cards;
                if (recs.isEmpty) return const SizedBox.shrink();
                final top = recs.first;
                final isHigh = top.priority.toLowerCase() == 'high';
                final isMedium = top.priority.toLowerCase() == 'medium';
                final bg = isHigh
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF6F39E8), Color(0xFFEF4444)],
                      )
                    : isMedium
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF6F39E8), Color(0xFF22C55E)],
                      )
                    : const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF9DA0AB), Color(0xFFE3E4EA)],
                      );

                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    gradient: bg,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Top Recommendation',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF9DA0AB),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          top.title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF161820),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          top.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.45,
                            color: Color(0xFF4C4F61),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const RecommendationScreen(),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6F39E8),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                            child: const Text(
                              'View All Recommendations',
                              style: TextStyle(
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
              },
            ),

            ValueListenableBuilder<CurrentSubscriptionModel?>(
              valueListenable: SubscriptionService.instance.subscription,
              builder: (context, current, _) {
                final planName = current?.plan.name.isNotEmpty == true
                    ? current!.plan.name
                    : (current?.effectivePlanCode.isNotEmpty == true
                        ? current!.effectivePlanCode[0].toUpperCase() +
                            current.effectivePlanCode.substring(1)
                        : null);
                final displayPlan = planName ?? 'Loading...';
                final status = (current?.status ?? 'inactive').toUpperCase();
                final expiry = current?.endDate != null
                    ? '${current!.endDate!.toLocal().year}-${current.endDate!.toLocal().month.toString().padLeft(2, '0')}-${current.endDate!.toLocal().day.toString().padLeft(2, '0')}'
                    : 'No active subscription';
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF5F2FDF), Color(0xFF7A4FE8)],
                    ),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6F39E8).withOpacity(0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'CURRENT TIER',
                              style: TextStyle(
                                color: Color(0xFFD5C6FF),
                                letterSpacing: 1.5,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '$displayPlan Plan',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                height: 1,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'Status: $status • Expires: $expiry',
                                style: const TextStyle(
                                  color: Color(0xFFD9CCFF),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _buildRenewButton(context),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 28),

            // PERSONALIZATION Section
            const Text(
              'PERSONALIZATION',
              style: TextStyle(
                color: Color(0xFF8B8D98),
                letterSpacing: 1.8,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),

            _MenuTile(
              icon: Icons.face_retouching_natural,
              title: 'Face Scan',
              subtitle: 'Set up facial recognition for mood tracking',
              onTap: () => _navigateTo(context, 'Face Scan'),
            ),
            const SizedBox(height: 8),

            _MenuTile(
              icon: Icons.auto_awesome,
              title: 'Upgrade Plan',
              subtitle: 'Basic • Standard • Premium',
              onTap: () => _navigateTo(context, 'Upgrade Plan'),
            ),
            const SizedBox(height: 8),

            _MenuTile(
              icon: Icons.phone_android,
              title: 'Screen Time',
              subtitle: 'Manage app usage limits',
              onTap: () => _navigateTo(context, 'Screen Time'),
            ),
            const SizedBox(height: 8),

            _MenuTile(
              icon: Icons.emergency,
              title: 'Emergency',
              subtitle: 'Crisis support & resources',
              onTap: () => _navigateTo(context, 'Emergency'),
            ),
            const SizedBox(height: 8),

            _MenuTile(
              icon: Icons.groups_rounded,
              title: 'Community',
              subtitle: 'Connect with others on similar journeys',
              onTap: () => _navigateTo(context, 'Community'),
            ),
            const SizedBox(height: 8),

            _MenuTile(
              icon: Icons.thumb_up_alt_rounded,
              title: 'Recommendation',
              subtitle: 'Personalized content for you',
              onTap: () => _navigateTo(context, 'Recommendation'),
            ),
            if ((_profile?.isApprovedDoctor ?? false)) ...[
              const SizedBox(height: 8),
              _MenuTile(
                icon: Icons.inbox_rounded,
                title: 'Inbox',
                subtitle: 'User messages for doctor account',
                onTap: () => _navigateTo(context, 'Inbox'),
              ),
            ],
            const SizedBox(height: 28),

            // SUPPORT & GROWTH Section (Duplicate removed - already included above)
            // Sign Out Button
            GestureDetector(
              onTap: () => _showSignOutDialog(context),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F5F9),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0xFFE7E8EE)),
                ),
                child: const Center(
                  child: Text(
                    'SIGN OUT',
                    style: TextStyle(
                      color: Color(0xFFDC2626),
                      fontSize: 13,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Footer
            const Center(
              child: Text(
                'MINDSYNC v2.4.0 • CRAFTED WITH INTENTION',
                style: TextStyle(
                  color: Color(0xFFA8AAB4),
                  fontSize: 12,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildRenewButton(BuildContext context) {
    return GestureDetector(
      onTap: () => _navigateTo(context, 'Upgrade Plan'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.3)),
        ),
        child: const Text(
          'RENEW',
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            letterSpacing: 1,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  void _navigateTo(BuildContext context, String screen) {
    switch (screen) {
      case 'Upgrade Plan':
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const UpgradePlanScreen()));
        return;
      case 'Emergency':
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const EmergencyScreen()));
        return;
      case 'Community':
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const CommunityScreen()));
        return;
      case 'Recommendation':
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const RecommendationScreen()));
        return;
      case 'Face Scan':
        Navigator.of(
          context,
        ).push(
          MaterialPageRoute(
            builder: (_) => const FaceScanScreen(),
          ),
        );
        return;
      case 'Screen Time':
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => const MainShellScreen(initialTab: 1),
          ),
          (_) => false,
        );
        return;
      case 'Inbox':
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const DoctorInboxScreen()));
        return;
      default:
        return;
    }
  }

  void _showSignOutDialog(BuildContext navigatorContext) {
    showDialog<void>(
      context: navigatorContext,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Sign Out',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
        ),
        content: const Text(
          'Are you sure you want to sign out?',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(
              'Cancel',
              style: TextStyle(
                color: Color(0xFF8B8D98),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              ScreenTimeService.instance.setFaceVerified(false);
              await ScreenTimeService.instance.clearTrackingUser();
              ScreenTimeService.instance.stop();
              await _auth.logout();
              if (!mounted) return;
              if (!navigatorContext.mounted) return;
              Navigator.of(navigatorContext).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (_) => false,
              );
            },
            child: const Text(
              'Sign Out',
              style: TextStyle(
                color: Color(0xFFDC2626),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFF0EBFF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, size: 22, color: const Color(0xFF6F39E8)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF161820),
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF8F919C),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: Color(0xFFC5C6D0),
            ),
          ],
        ),
      ),
    );
  }
}
