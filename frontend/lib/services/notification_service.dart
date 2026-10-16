import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/app_notification.dart';
import 'api_client.dart';

/// Syncs in-app notifications with Django (`/api/auth/notifications/`).
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final ValueNotifier<List<AppNotification>> notifications =
      ValueNotifier<List<AppNotification>>(const []);
  final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);

  Timer? _pollTimer;
  bool _loading = false;

  void resetForNewUser() {
    _pollTimer?.cancel();
    _pollTimer = null;
    notifications.value = const [];
    unreadCount.value = 0;
  }

  void startPolling({Duration interval = const Duration(minutes: 3)}) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(interval, (_) => unawaited(refresh()));
    unawaited(refresh());
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> syncTriggers() async {
    final response = await ApiClient.instance.post(
      '/api/auth/notifications/sync-triggers/',
      body: const {},
    );
    if (response != null &&
        response.statusCode >= 200 &&
        response.statusCode < 300) {
      try {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        unreadCount.value = (json['unread_count'] as num?)?.toInt() ?? 0;
      } catch (_) {}
    }
    await refresh(force: true);
  }

  Future<void> refresh({bool force = false}) async {
    if (_loading && !force) return;
    _loading = true;
    try {
      final json = await ApiClient.instance.getJson('/api/auth/notifications/');
      if (json == null) return;
      final list = (json['notifications'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(AppNotification.fromJson)
          .toList();
      notifications.value = list;
      unreadCount.value = (json['unread_count'] as num?)?.toInt() ??
          list.where((n) => !n.isRead).length;
    } finally {
      _loading = false;
    }
  }

  Future<AppNotification?> fetchDetail(int id) async {
    final json =
        await ApiClient.instance.getJson('/api/auth/notifications/$id/');
    if (json == null) return null;
    final item = AppNotification.fromJson(json);
    _replaceLocal(item);
    _recomputeUnread();
    return item;
  }

  Future<void> markAllRead() async {
    await ApiClient.instance.post(
      '/api/auth/notifications/mark-all-read/',
      body: const {},
    );
    notifications.value = notifications.value
        .map((n) => n.copyWith(isRead: true))
        .toList();
    unreadCount.value = 0;
  }

  Future<bool> deleteByIds(List<int> ids) async {
    if (ids.isEmpty) return false;
    final response = await ApiClient.instance.post(
      '/api/auth/notifications/bulk-delete/',
      body: {'ids': ids},
    );
    if (response == null ||
        response.statusCode < 200 ||
        response.statusCode >= 300) {
      return false;
    }
    final idSet = ids.toSet();
    notifications.value =
        notifications.value.where((n) => !idSet.contains(n.id)).toList();
    _recomputeUnread();
    return true;
  }

  void _replaceLocal(AppNotification item) {
    final list = List<AppNotification>.from(notifications.value);
    final idx = list.indexWhere((n) => n.id == item.id);
    if (idx >= 0) {
      list[idx] = item;
    } else {
      list.insert(0, item);
    }
    notifications.value = list;
  }

  void _recomputeUnread() {
    unreadCount.value =
        notifications.value.where((n) => !n.isRead).length;
  }
}
