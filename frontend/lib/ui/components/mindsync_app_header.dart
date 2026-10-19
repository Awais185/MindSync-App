import 'package:flutter/material.dart';

import '../../screens/pages/notifications_screen.dart';
import '../../screens/pages/profile_screen.dart';
import '../../services/local_auth_service.dart';
import '../../services/notification_service.dart';
import '../../services/user_session_cache.dart';
import '../../widgets/mindsync_logo.dart';

/// Shared top bar: MindSync logo (left), notifications + profile (right).
class MindSyncAppHeader extends StatefulWidget {
  const MindSyncAppHeader({
    super.key,
    this.onBack,
    this.onReportTap,
    this.onMenuTap,
  });

  final VoidCallback? onBack;
  /// Chat tab: opens the 7-day Report screen (left of history menu).
  final VoidCallback? onReportTap;
  final VoidCallback? onMenuTap;

  static const double avatarRadius = 20;

  /// Logo height — reduced by 3 more px (82 → 79)
  static const double logoHeight = 79;

  /// Top spacing of the whole header — unchanged
  static const double headerTopSpacing = 3;
  /// Extra inset for the logo from the screen edge.
  static const double headerLeftSpacing = 12;


  @override
  State<MindSyncAppHeader> createState() => _MindSyncAppHeaderState();
}

class _MindSyncAppHeaderState extends State<MindSyncAppHeader> {
  final _auth = LocalAuthService();
  String? _faceImageUrl;
  VoidCallback? _sessionListener;

  @override
  void initState() {
    super.initState();
    _sessionListener = () => _loadProfile();
    UserSessionCache.sessionGeneration.addListener(_sessionListener!);
    _loadProfile();
  }

  @override
  void dispose() {
    if (_sessionListener != null) {
      UserSessionCache.sessionGeneration.removeListener(_sessionListener!);
    }
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final profile = await _auth.fetchCurrentUserProfile();
    if (!mounted) return;
    final raw = profile?.faceImage;
    setState(() {
      _faceImageUrl =
          raw != null && raw.isNotEmpty ? _auth.resolveMediaUrl(raw) : null;
    });
  }

  void _openProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );
  }

  void _openNotifications() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = _faceImageUrl != null && _faceImageUrl!.isNotEmpty;
    final logoWidth = MindSyncAppHeader.logoHeight * 2.75;

    // Reduced by 3: was logoHeight + 14 → now logoHeight + 11
    final headerHeight = MindSyncAppHeader.logoHeight + 11;

    return Padding(
      padding: const EdgeInsets.only(
        top: MindSyncAppHeader.headerTopSpacing,
      ),
      child: SizedBox(
        height: headerHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (widget.onBack != null) ...[
              IconButton(
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
              const SizedBox(width: 2),
            ],

            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(
                    top: 3,
                    left: MindSyncAppHeader.headerLeftSpacing,
                  ),
                  child: MindSyncLogo(
                    height: MindSyncAppHeader.logoHeight,
                    width: logoWidth,
                    fit: BoxFit.contain,
                    alignment: Alignment.centerLeft,
                  ),
                ),
              ),
            ),

            if (widget.onReportTap != null) ...[
              _HeaderCircleIconButton(
                icon: Icons.assessment_outlined,
                tooltip: 'My Report',
                onTap: widget.onReportTap!,
              ),
              const SizedBox(width: 6),
            ],
            if (widget.onMenuTap != null) ...[
              _HeaderCircleIconButton(
                icon: Icons.menu_rounded,
                tooltip: 'Chat history',
                onTap: widget.onMenuTap!,
              ),
              const SizedBox(width: 6),
            ],
            AnimatedBuilder(
              animation: NotificationService.instance.unreadCount,
              builder: (context, _) {
                final unread = NotificationService.instance.unreadCount.value;
                return _HeaderCircleIconButton(
                  icon: Icons.notifications_none_rounded,
                  badgeCount: unread,
                  onTap: _openNotifications,
                );
              },
            ),
            const SizedBox(width: 6),
            InkWell(
              onTap: _openProfile,
              borderRadius: BorderRadius.circular(24),
              child: Container(
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF6F39E8),
                    width: 1.8,
                  ),
                ),
                child: CircleAvatar(
                  radius: MindSyncAppHeader.avatarRadius,
                  backgroundColor: const Color(0xFF1F2330),
                  backgroundImage:
                      hasImage ? NetworkImage(_faceImageUrl!) : null,
                  child: hasImage
                      ? null
                      : const Icon(
                          Icons.person,
                          color: Colors.white,
                          size: 20,
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

class _HeaderCircleIconButton extends StatelessWidget {
  const _HeaderCircleIconButton({
    required this.icon,
    required this.onTap,
    this.badgeCount = 0,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final int badgeCount;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, size: 20, color: const Color(0xFF1F2330)),
          ),
          if (badgeCount > 0)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                decoration: BoxDecoration(
                  color: const Color(0xFF6F39E8),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white, width: 1.6),
                ),
                alignment: Alignment.center,
                child: Text(
                  badgeCount > 99 ? '99+' : '$badgeCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    if (tooltip != null && tooltip!.isNotEmpty) {
      return Tooltip(message: tooltip!, preferBelow: true, child: button);
    }
    return button;
  }
}