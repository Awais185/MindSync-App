import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_service.dart';

/// Persists bedtime / wake-up times and schedules native daily OS alarms.
class ParentBedtimeScheduleService {
  ParentBedtimeScheduleService._();

  static const _channel = MethodChannel('mindsync/screen_time');
  static const _kSleepH = 'parent.bedtime.sleep_hour';
  static const _kSleepM = 'parent.bedtime.sleep_minute';
  static const _kWakeH = 'parent.bedtime.wake_hour';
  static const _kWakeM = 'parent.bedtime.wake_minute';

  static Future<({TimeOfDay sleep, TimeOfDay wake})> loadTimes() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      sleep: TimeOfDay(
        hour: prefs.getInt(_kSleepH) ?? 21,
        minute: prefs.getInt(_kSleepM) ?? 30,
      ),
      wake: TimeOfDay(
        hour: prefs.getInt(_kWakeH) ?? 7,
        minute: prefs.getInt(_kWakeM) ?? 0,
      ),
    );
  }

  static Future<void> saveAndSchedule({
    required TimeOfDay sleep,
    required TimeOfDay wake,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kSleepH, sleep.hour);
    await prefs.setInt(_kSleepM, sleep.minute);
    await prefs.setInt(_kWakeH, wake.hour);
    await prefs.setInt(_kWakeM, wake.minute);

    if (kIsWeb) return;

    try {
      await _channel.invokeMethod('scheduleBedtimeNotifications', {
        'sleepHour': sleep.hour,
        'sleepMinute': sleep.minute,
        'wakeHour': wake.hour,
        'wakeMinute': wake.minute,
      });
    } catch (_) {}
  }

  /// Call on app start so alarms survive process death (native also restores on boot).
  static Future<void> restoreNativeScheduleIfSaved() async {
    if (kIsWeb) return;
    final times = await loadTimes();
    await saveAndSchedule(sleep: times.sleep, wake: times.wake);
  }

  /// After a scheduled fire, refresh in-app notification list.
  static Future<void> refreshInAppNotifications() async {
    await NotificationService.instance.refresh(force: true);
  }
}
