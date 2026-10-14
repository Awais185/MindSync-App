import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Temporary social-media daily limit from Parent Control → Usage Health (12 h expiry).
class SocialMediaUsageLimitStore {
  SocialMediaUsageLimitStore._();

  static const _channel = MethodChannel('mindsync/screen_time');
  static const _keyLimitMinutes = 'parent.usage_health.social_limit_minutes';
  static const _keySetAtMs = 'parent.usage_health.social_limit_set_at_ms';
  static const _keyShowExpired = 'parent.usage_health.show_expired_indicator';
  static const expiryMs = 12 * 60 * 60 * 1000;

  static final ValueNotifier<SocialMediaUsageLimitState> notifier =
      ValueNotifier(SocialMediaUsageLimitState.empty);

  static Timer? _expiryTimer;

  static Future<SocialMediaUsageLimitState> load() async {
    final prefs = await SharedPreferences.getInstance();
    var limitMinutes = prefs.getInt(_keyLimitMinutes);
    var setAtMs = prefs.getInt(_keySetAtMs) ?? 0;
    var showExpired = prefs.getBool(_keyShowExpired) ?? false;

    if (!kIsWeb) {
      try {
        final native = await _channel.invokeMethod<Map<dynamic, dynamic>>(
          'getUsageHealthSocialLimit',
        );
        if (native != null) {
          limitMinutes = (native['limitMinutes'] as num?)?.toInt();
          setAtMs = (native['setAtMs'] as num?)?.toInt() ?? setAtMs;
          showExpired = (native['expired'] as bool?) ?? showExpired;
        }
      } catch (_) {}
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final active = _isActive(limitMinutes, setAtMs, now);
    if (!active && setAtMs > 0) {
      showExpired = true;
      await _clearPersisted(prefs, markExpired: true);
      if (!kIsWeb) {
        await _syncNative(limitMinutes: null, setAtMs: 0);
      }
      limitMinutes = null;
      setAtMs = 0;
    }

    final state = SocialMediaUsageLimitState(
      limitMinutes: active ? limitMinutes : null,
      setAtMs: active ? setAtMs : 0,
      showExpiredIndicator: showExpired,
    );
    notifier.value = state;
    _scheduleExpiryTimer(state);
    return state;
  }

  static Future<void> saveLimit({required int limitMinutes}) async {
    if (limitMinutes <= 0) return;
    final setAtMs = DateTime.now().millisecondsSinceEpoch;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyLimitMinutes, limitMinutes);
    await prefs.setInt(_keySetAtMs, setAtMs);
    await prefs.setBool(_keyShowExpired, false);

    if (!kIsWeb) {
      await _syncNative(limitMinutes: limitMinutes, setAtMs: setAtMs);
    }

    final state = SocialMediaUsageLimitState(
      limitMinutes: limitMinutes,
      setAtMs: setAtMs,
      showExpiredIndicator: false,
    );
    notifier.value = state;
    _scheduleExpiryTimer(state);
  }

  static Future<void> clearExpiredIndicator() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowExpired, false);
    notifier.value = notifier.value.copyWith(showExpiredIndicator: false);
  }

  static Future<void> clearLimit() async {
    final prefs = await SharedPreferences.getInstance();
    await _clearPersisted(prefs, markExpired: false);
    if (!kIsWeb) {
      await _syncNative(limitMinutes: null, setAtMs: 0);
    }
    notifier.value = SocialMediaUsageLimitState.empty;
    _expiryTimer?.cancel();
  }

  static bool _isActive(int? limitMinutes, int setAtMs, int nowMs) {
    if (limitMinutes == null || limitMinutes <= 0 || setAtMs <= 0) return false;
    return nowMs < setAtMs + expiryMs;
  }

  static Future<void> _clearPersisted(
    SharedPreferences prefs, {
    required bool markExpired,
  }) async {
    await prefs.remove(_keyLimitMinutes);
    await prefs.remove(_keySetAtMs);
    await prefs.setBool(_keyShowExpired, markExpired);
  }

  static Future<void> _syncNative({
    required int? limitMinutes,
    required int setAtMs,
  }) async {
    try {
      await _channel.invokeMethod('setUsageHealthSocialLimit', {
        'limitMinutes': limitMinutes ?? 0,
        'setAtMs': setAtMs,
      });
    } catch (_) {}
  }

  static void _scheduleExpiryTimer(SocialMediaUsageLimitState state) {
    _expiryTimer?.cancel();
    if (!state.isActive) return;
    final remaining = state.expiresAtMs - DateTime.now().millisecondsSinceEpoch;
    if (remaining <= 0) {
      unawaited(load());
      return;
    }
    _expiryTimer = Timer(Duration(milliseconds: remaining + 500), () {
      unawaited(load());
    });
  }
}

class SocialMediaUsageLimitState {
  const SocialMediaUsageLimitState({
    required this.limitMinutes,
    required this.setAtMs,
    required this.showExpiredIndicator,
  });

  final int? limitMinutes;
  final int setAtMs;
  final bool showExpiredIndicator;

  static const empty = SocialMediaUsageLimitState(
    limitMinutes: null,
    setAtMs: 0,
    showExpiredIndicator: false,
  );

  bool get isActive =>
      limitMinutes != null &&
      limitMinutes! > 0 &&
      setAtMs > 0 &&
      DateTime.now().millisecondsSinceEpoch <
          setAtMs + SocialMediaUsageLimitStore.expiryMs;

  int get expiresAtMs => setAtMs + SocialMediaUsageLimitStore.expiryMs;

  Duration get remaining =>
      Duration(milliseconds: (expiresAtMs - DateTime.now().millisecondsSinceEpoch).clamp(0, 1 << 31));

  SocialMediaUsageLimitState copyWith({
    int? limitMinutes,
    int? setAtMs,
    bool? showExpiredIndicator,
  }) {
    return SocialMediaUsageLimitState(
      limitMinutes: limitMinutes ?? this.limitMinutes,
      setAtMs: setAtMs ?? this.setAtMs,
      showExpiredIndicator: showExpiredIndicator ?? this.showExpiredIndicator,
    );
  }
}

String formatUsageHealthCountdown(Duration remaining) {
  if (remaining.inSeconds <= 0) return 'Expired';
  final h = remaining.inHours;
  final m = remaining.inMinutes.remainder(60);
  if (h <= 0) return 'Expires in ${m}m';
  return 'Expires in ${h}h ${m}m';
}
