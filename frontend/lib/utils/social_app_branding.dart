import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// Brand icons + colors for tracked social apps (centered in usage rows).
class SocialAppBranding {
  const SocialAppBranding({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.barColor,
    this.brandIcon,
  });

  final IconData icon;
  final IconData? brandIcon;
  final Color iconBg;
  final Color iconColor;
  final Color barColor;

  static SocialAppBranding forApp({
    required String appName,
    String packageName = '',
  }) {
    final pkg = packageName.toLowerCase();
    final lower = appName.toLowerCase();

    if (pkg.contains('youtube') || lower.contains('youtube')) {
      return const SocialAppBranding(
        icon: Icons.play_circle_fill_rounded,
        brandIcon: FontAwesomeIcons.youtube,
        iconBg: Color(0xFFFFF1F1),
        iconColor: Color(0xFFFF0000),
        barColor: Color(0xFFFF0000),
      );
    }
    if (pkg.contains('instagram') || lower.contains('instagram')) {
      return const SocialAppBranding(
        icon: Icons.camera_alt_rounded,
        brandIcon: FontAwesomeIcons.instagram,
        iconBg: Color(0xFFFFEFFB),
        iconColor: Color(0xFFE1306C),
        barColor: Color(0xFFE1306C),
      );
    }
    if (pkg.contains('facebook') || lower.contains('facebook')) {
      return const SocialAppBranding(
        icon: Icons.facebook_rounded,
        brandIcon: FontAwesomeIcons.facebook,
        iconBg: Color(0xFFEEF2FF),
        iconColor: Color(0xFF1877F2),
        barColor: Color(0xFF1877F2),
      );
    }
    if (pkg.contains('snapchat') || lower.contains('snapchat')) {
      return const SocialAppBranding(
        icon: Icons.bolt_rounded,
        brandIcon: FontAwesomeIcons.snapchat,
        iconBg: Color(0xFFFFF9E6),
        iconColor: Color(0xFFFFFC00),
        barColor: Color(0xFFF5D000),
      );
    }
    if (pkg.contains('reddit') || lower.contains('reddit')) {
      return const SocialAppBranding(
        icon: Icons.forum_rounded,
        brandIcon: FontAwesomeIcons.reddit,
        iconBg: Color(0xFFFFEDE8),
        iconColor: Color(0xFFFF4500),
        barColor: Color(0xFFFF4500),
      );
    }
    if (pkg.contains('twitter') ||
        pkg.contains('x.android') ||
        lower.contains('twitter') ||
        lower == 'x') {
      return const SocialAppBranding(
        icon: Icons.tag_rounded,
        brandIcon: FontAwesomeIcons.xTwitter,
        iconBg: Color(0xFFF2F2F2),
        iconColor: Color(0xFF000000),
        barColor: Color(0xFF333333),
      );
    }
    if (pkg.contains('musically') ||
        pkg.contains('trill') ||
        pkg.contains('tiktok') ||
        lower.contains('tiktok')) {
      return const SocialAppBranding(
        icon: Icons.music_note_rounded,
        brandIcon: FontAwesomeIcons.tiktok,
        iconBg: Color(0xFFFFEEF3),
        iconColor: Color(0xFF000000),
        barColor: Color(0xFF000000),
      );
    }
    if (pkg.contains('whatsapp') || lower.contains('whatsapp')) {
      return const SocialAppBranding(
        icon: Icons.chat_rounded,
        brandIcon: FontAwesomeIcons.whatsapp,
        iconBg: Color(0xFFE8F8EE),
        iconColor: Color(0xFF25D366),
        barColor: Color(0xFF25D366),
      );
    }
    if (lower.contains('discord')) {
      return const SocialAppBranding(
        icon: Icons.forum_rounded,
        brandIcon: FontAwesomeIcons.discord,
        iconBg: Color(0xFFF1F2FF),
        iconColor: Color(0xFF5563D4),
        barColor: Color(0xFF626ED7),
      );
    }
    return const SocialAppBranding(
      icon: Icons.apps_rounded,
      iconBg: Color(0xFFF1F3F8),
      iconColor: Color(0xFF5A5E6C),
      barColor: Color(0xFF7A80A0),
    );
  }

  /// Same package/name rules as [forApp] — used for social-only usage totals.
  static bool isSocialMediaApp({
    required String appName,
    String packageName = '',
  }) {
    final pkg = packageName.toLowerCase();
    final lower = appName.toLowerCase();
    if (pkg.contains('youtube') || lower.contains('youtube')) return true;
    if (pkg.contains('instagram') || lower.contains('instagram')) return true;
    if (pkg.contains('facebook') || lower.contains('facebook')) return true;
    if (pkg.contains('snapchat') || lower.contains('snapchat')) return true;
    if (pkg.contains('reddit') || lower.contains('reddit')) return true;
    if (pkg.contains('twitter') ||
        pkg.contains('x.android') ||
        lower.contains('twitter') ||
        lower == 'x') {
      return true;
    }
    if (pkg.contains('musically') ||
        pkg.contains('trill') ||
        pkg.contains('tiktok') ||
        lower.contains('tiktok')) {
      return true;
    }
    if (pkg.contains('whatsapp') || lower.contains('whatsapp')) return true;
    if (lower.contains('discord')) return true;
    if (pkg.contains('telegram') || lower.contains('telegram')) return true;
    return false;
  }
}
