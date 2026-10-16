import 'package:flutter/material.dart';

import '../../models/app_notification.dart';
import '../../services/notification_service.dart';
import 'recommendation_screen.dart';
import 'report_screen.dart';
import 'profile_screen.dart';
import '../main_shell_screen.dart';

class NotificationDetailScreen extends StatefulWidget {
  const NotificationDetailScreen({
    super.key,
    required this.notificationId,
    this.initial,
  });

  final int notificationId;
  final AppNotification? initial;

  @override
  State<NotificationDetailScreen> createState() =>
      _NotificationDetailScreenState();
}

class _NotificationDetailScreenState extends State<NotificationDetailScreen> {
  AppNotification? _item;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _item = widget.initial;
    _load();
  }

  Future<void> _load() async {
    final detail =
        await NotificationService.instance.fetchDetail(widget.notificationId);
    if (!mounted) return;
    setState(() {
      _item = detail ?? _item;
      _loading = false;
    });
  }

  void _openAction(BuildContext context, AppNotification item) {
    final route = item.actionRoute.trim().toLowerCase();
    switch (route) {
      case 'weekly_report':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ReportScreen()),
        );
        return;
      case 'recommendations':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const RecommendationScreen()),
        );
        return;
      case 'profile':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ProfileScreen()),
        );
        return;
      case 'home':
      default:
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainShellScreen()),
          (r) => false,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    final style = item?.visualStyle ?? NotificationVisualStyle.forEvent('');

    return Scaffold(
      backgroundColor: const Color(0xFFF3F1FB),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
              child: Row(
                children: [
                  Material(
                    color: Colors.white,
                    shape: const CircleBorder(),
                    child: InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      customBorder: const CircleBorder(),
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(
                          Icons.arrow_back_rounded,
                          size: 20,
                          color: Color(0xFF1F2330),
                        ),
                      ),
                    ),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text(
                        'Notification',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1F2330),
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 44),
                ],
              ),
            ),
            Expanded(
              child: _loading && item == null
                  ? const Center(child: CircularProgressIndicator())
                  : item == null
                      ? const Center(
                          child: Text(
                            'Notification not found.',
                            style: TextStyle(color: Color(0xFF6B6E7A)),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                          children: [
                            Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(
                                  color: const Color(0xFFE7E4F1),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          color: style.iconBg,
                                          borderRadius:
                                              BorderRadius.circular(16),
                                        ),
                                        child: Icon(
                                          style.icon,
                                          color: style.iconColor,
                                          size: 22,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          item.title,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF1F2330),
                                            letterSpacing: -0.3,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    item.relativeTimeLabel,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF9B9EA9),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    item.body,
                                    style: const TextStyle(
                                      fontSize: 14.5,
                                      height: 1.45,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF4B4E5C),
                                    ),
                                  ),
                                  if (item.actionLabel.isNotEmpty &&
                                      item.actionRoute.isNotEmpty) ...[
                                    const SizedBox(height: 20),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton(
                                        onPressed: () =>
                                            _openAction(context, item),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              const Color(0xFF6F39E8),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 14,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(16),
                                          ),
                                        ),
                                        child: Text(
                                          item.actionLabel,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
