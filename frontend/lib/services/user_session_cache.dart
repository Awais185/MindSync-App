import 'dart:async';

import 'package:flutter/foundation.dart';

import 'plan_access_service.dart';
import 'subscription_service.dart';
import 'wellness_dashboard_service.dart';
import 'notification_service.dart';
import 'weekly_mood_service.dart';

/// Clears in-memory caches so a new login never sees the previous user's data.
class UserSessionCache {
  UserSessionCache._();

  /// Bumped on login/logout so keep-alive tabs reload user-scoped data.
  static final ValueNotifier<int> sessionGeneration = ValueNotifier(0);

  static void _bumpSessionGeneration() {
    sessionGeneration.value++;
  }

  /// Call before persisting new auth tokens (login / account switch).
  static Future<void> onUserSessionStarting() async {
    _bumpSessionGeneration();
    SubscriptionService.instance.clearForNewUser();
    PlanAccessService.instance.invalidate();
    WellnessDashboardService.instance.resetForNewUser();
    WeeklyMoodService.instance.resetForNewUser();
    NotificationService.instance.resetForNewUser();
  }

  /// Call on logout.
  static Future<void> onLogout() async {
    await onUserSessionStarting();
  }

  /// After new tokens are stored — fetch subscription for this user only.
  static Future<void> onUserSessionReady() async {
    await SubscriptionService.instance.getCurrentSubscription(forceRefresh: true);
    await PlanAccessService.instance.refresh(force: true);
    await Future.wait([
      WellnessDashboardService.instance.refreshHome(force: true),
      WellnessDashboardService.instance.refresh(force: true),
    ]);
    WeeklyMoodService.instance.startPolling();
    unawaited(NotificationService.instance.syncTriggers());
    NotificationService.instance.startPolling();
    _bumpSessionGeneration();
  }
}
