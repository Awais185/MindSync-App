import 'package:flutter/material.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.eventType,
    required this.title,
    required this.body,
    required this.isRead,
    required this.createdAt,
    this.actionRoute = '',
    this.actionLabel = '',
    this.priority = 0,
  });

  final int id;
  final String eventType;
  final String title;
  final String body;
  final bool isRead;
  final DateTime createdAt;
  final String actionRoute;
  final String actionLabel;
  final int priority;

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: (json['id'] as num).toInt(),
      eventType: (json['event_type'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      body: (json['body'] ?? '').toString(),
      isRead: json['is_read'] == true,
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ??
          DateTime.now(),
      actionRoute: (json['action_route'] ?? '').toString(),
      actionLabel: (json['action_label'] ?? '').toString(),
      priority: (json['priority'] as num?)?.toInt() ?? 0,
    );
  }

  AppNotification copyWith({bool? isRead}) {
    return AppNotification(
      id: id,
      eventType: eventType,
      title: title,
      body: body,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
      actionRoute: actionRoute,
      actionLabel: actionLabel,
      priority: priority,
    );
  }

  NotificationVisualStyle get visualStyle =>
      NotificationVisualStyle.forEvent(eventType);

  String get relativeTimeLabel => formatNotificationTime(createdAt);
}

class NotificationVisualStyle {
  const NotificationVisualStyle({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;

  static NotificationVisualStyle forEvent(String eventType) {
    switch (eventType) {
      case 'welcome':
        return const NotificationVisualStyle(
          icon: Icons.waving_hand_rounded,
          iconBg: Color(0xFFF3E8FF),
          iconColor: Color(0xFF6F39E8),
        );
      case 'weekly_report':
        return const NotificationVisualStyle(
          icon: Icons.insights_rounded,
          iconBg: Color(0xFFEFF6FF),
          iconColor: Color(0xFF3B82F6),
        );
      case 'password_reset_requested':
      case 'password_changed':
        return const NotificationVisualStyle(
          icon: Icons.shield_outlined,
          iconBg: Color(0xFFFFF4E5),
          iconColor: Color(0xFFE09100),
        );
      case 'low_wellbeing':
        return const NotificationVisualStyle(
          icon: Icons.monitor_heart_outlined,
          iconBg: Color(0xFFFEE2E2),
          iconColor: Color(0xFFDC2626),
        );
      default:
        return const NotificationVisualStyle(
          icon: Icons.notifications_none_rounded,
          iconBg: Color(0xFFF3F1FB),
          iconColor: Color(0xFF6F39E8),
        );
    }
  }
}

String formatNotificationTime(DateTime createdAt) {
  final now = DateTime.now();
  final diff = now.difference(createdAt);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} hours ago';
  if (diff.inDays == 1) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays} days ago';
  return '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-'
      '${createdAt.day.toString().padLeft(2, '0')}';
}
