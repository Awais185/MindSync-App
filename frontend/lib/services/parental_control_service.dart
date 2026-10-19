import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/parent_content_monitor.dart';
import 'api_client.dart';

export '../models/parent_content_monitor.dart';

class ParentalAppRule {
  const ParentalAppRule({
    required this.packageName,
    required this.appLabel,
    required this.blocked,
    this.category,
    this.iconBytes,
    this.isGame = false,
    this.isPriority = false,
  });

  final String packageName;
  final String appLabel;
  final bool blocked;
  final String? category;
  final Uint8List? iconBytes;
  final bool isGame;
  final bool isPriority;

  ParentalAppRule copyWith({
    String? packageName,
    String? appLabel,
    bool? blocked,
    String? category,
    Uint8List? iconBytes,
    bool? isGame,
    bool? isPriority,
  }) {
    return ParentalAppRule(
      packageName: packageName ?? this.packageName,
      appLabel: appLabel ?? this.appLabel,
      blocked: blocked ?? this.blocked,
      category: category ?? this.category,
      iconBytes: iconBytes ?? this.iconBytes,
      isGame: isGame ?? this.isGame,
      isPriority: isPriority ?? this.isPriority,
    );
  }
}

class InstalledAppInfo {
  const InstalledAppInfo({
    required this.packageName,
    required this.appLabel,
    this.iconBytes,
    this.isGame = false,
    this.isPriority = false,
  });

  final String packageName;
  final String appLabel;
  final Uint8List? iconBytes;
  final bool isGame;
  final bool isPriority;
}

/// Display order for Parent → App Restrictions (installed apps only).
abstract final class ParentalAppCatalog {
  static const collapsedCount = 7;

  static const List<(String label, List<String> packageIds)> priorityApps = [
    ('YouTube', ['com.google.android.youtube']),
    ('Facebook', ['com.facebook.katana', 'com.facebook.lite']),
    ('WhatsApp', ['com.whatsapp', 'com.whatsapp.w4b']),
    ('TikTok', [
      'com.zhiliaoapp.musically',
      'com.ss.android.ugc.trill',
      'com.zhiliaoapp.musically.go',
    ]),
    ('Instagram', ['com.instagram.android', 'com.instagram.lite']),
    ('Snapchat', ['com.snapchat.android']),
    ('Netflix', ['com.netflix.mediaclient']),
    ('Play Store', ['com.android.vending']),
    ('YouTube Music', ['com.google.android.apps.youtube.music']),
  ];

  static int priorityRank(String packageName, String appLabel) {
    final pkg = packageName.toLowerCase();
    for (var i = 0; i < priorityApps.length; i++) {
      final ids = priorityApps[i].$2;
      if (ids.any((id) => id.toLowerCase() == pkg)) return i;
      final label = priorityApps[i].$1.toLowerCase();
      if (appLabel.toLowerCase().contains(label)) return i;
    }
    return 999;
  }

  /// Keeps the on-device display name when the API returns a raw package id.
  static String resolveAppLabel({
    required String packageName,
    required String deviceLabel,
    String? apiLabel,
    String? previousLabel,
  }) {
    final pkg = packageName.trim();
    final device = deviceLabel.trim();
    final api = (apiLabel ?? '').trim();
    final previous = (previousLabel ?? '').trim();

    bool looksLikePackageId(String value) {
      if (value.isEmpty || value == pkg) return true;
      return value.contains('.') && value.split('.').length >= 3;
    }

    if (previous.isNotEmpty && !looksLikePackageId(previous)) {
      return previous;
    }
    if (device.isNotEmpty && !looksLikePackageId(device)) {
      return device;
    }
    if (api.isNotEmpty && !looksLikePackageId(api)) {
      return api;
    }
    for (final entry in priorityApps) {
      if (entry.$2.any((id) => id.toLowerCase() == pkg.toLowerCase())) {
        return entry.$1;
      }
    }
    if (device.isNotEmpty) return device;
    if (api.isNotEmpty) return api;
    return pkg;
  }

  static List<ParentalAppRule> sortForDisplay(List<ParentalAppRule> rules) {
    final list = List<ParentalAppRule>.from(rules);
    list.sort((a, b) {
      final pa = priorityRank(a.packageName, a.appLabel);
      final pb = priorityRank(b.packageName, b.appLabel);
      if (pa != pb) return pa.compareTo(pb);
      if (a.isGame != b.isGame) return a.isGame ? -1 : 1;
      return a.appLabel.toLowerCase().compareTo(b.appLabel.toLowerCase());
    });
    return list;
  }
}

class ParentalControlService {
  static const MethodChannel _channel = MethodChannel('mindsync/screen_time');

  /// Persisted blocked package ids mirrored to native HOME blocker ([AppBlockerService]).
  static const blockedPkgsStorageKey = 'parental.home_block_packages.v1';

  static const List<List<String>> _blockedAliasGroups = [
    [
      'com.zhiliaoapp.musically',
      'com.ss.android.ugc.trill',
      'com.zhiliaoapp.musically.go',
    ],
    ['com.twitter.android', 'com.x.android'],
    ['com.whatsapp', 'com.whatsapp.w4b'],
  ];

  /// Package ids that share one block state (e.g. TikTok variants).
  static Set<String> expandBlockedAliases(String packageName) =>
      _expandBlockedAliases(packageName);

  static Set<String> _expandBlockedAliases(String packageName) {
    final trimmed = packageName.trim();
    if (trimmed.isEmpty) return {};
    final out = <String>{trimmed};
    for (final group in _blockedAliasGroups) {
      if (group.contains(trimmed)) {
        out.addAll(group);
        break;
      }
    }
    return out;
  }

  static Set<String> _expandBlockedAliasesForAll(Iterable<String> packages) {
    final out = <String>{};
    for (final pkg in packages) {
      out.addAll(_expandBlockedAliases(pkg));
    }
    return out;
  }

  static bool parseBlockedFlag(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final v = value.trim().toLowerCase();
      if (v == 'true' || v == '1') return true;
      if (v == 'false' || v == '0') return false;
    }
    return false;
  }

  static bool _isBlockedPackage(
    String packageName, {
    required Map<String, ParentalAppRule> apiByPackage,
    required Set<String> prefsBlocked,
    required Set<String> nativeBlocked,
  }) {
    final apiRule = apiByPackage[packageName];
    if (apiRule != null) {
      return parseBlockedFlag(apiRule.blocked);
    }
    // Offline / not yet synced: only explicit local blocks (default = unblocked).
    final aliases = _expandBlockedAliases(packageName);
    if (aliases.any(prefsBlocked.contains)) return true;
    if (aliases.any(nativeBlocked.contains)) return true;
    return false;
  }

  Future<void> _persistBlocked(Set<String> pkgs) async {
    final prefs = await SharedPreferences.getInstance();
    final sorted = pkgs.where((s) => s.isNotEmpty).toList()..sort();
    await prefs.setString(blockedPkgsStorageKey, jsonEncode(sorted));
  }

  Future<Set<String>> _readBlocked() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(blockedPkgsStorageKey);
    if (raw == null || raw.isEmpty) return {};
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => e.toString()).where((s) => s.isNotEmpty).toSet();
  }

  Future<Set<String>> _readNativeBlockedPackages() async {
    if (kIsWeb) return {};
    try {
      final list = await _channel.invokeListMethod<dynamic>(
        'getLocalBlockedPackages',
      );
      if (list == null) return {};
      return list.map((e) => e.toString()).where((s) => s.isNotEmpty).toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> syncNativeHomeBlocker(Set<String> packages) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('appBlockerSetBlockedApps', {
        'packages': packages.toList(),
      });
    } catch (_) {}
  }

  /// Call after login so native blocker restores from prefs without reopening parental UI.
  static Future<void> restoreNativeHomeBlockerFromPrefs() async {
    if (kIsWeb) return;
    await ParentalControlService()._restoreNativeHomeBlockerFromPrefsImpl();
  }

  Future<void> _restoreNativeHomeBlockerFromPrefsImpl() async {
    await syncNativeHomeBlocker(await _readBlocked());
  }

  Future<ParentContentMonitorSnapshot> fetchContentMonitor() async {
    try {
      final json = await ApiClient.instance.getJson(
        '/api/auth/parent/content-monitor/',
      );
      if (json == null) return ParentContentMonitorSnapshot.empty;
      final items = (json['items'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ParentContentMonitorItem.fromJson)
          .take(3)
          .toList();
      return ParentContentMonitorSnapshot(
        hasData: (json['has_data'] as bool?) ?? items.isNotEmpty,
        items: items,
        message: json['message']?.toString(),
      );
    } catch (_) {
      return ParentContentMonitorSnapshot.empty;
    }
  }

  Uint8List? _decodeIcon(dynamic raw) {
    final b64 = raw?.toString().trim() ?? '';
    if (b64.isEmpty) return null;
    try {
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  /// Reads launchable apps from the device (Usage / package manager).
  Future<List<InstalledAppInfo>> fetchInstalledAppsFromDevice() async {
    if (kIsWeb) return const [];
    try {
      final apps = await _channel.invokeListMethod<dynamic>(
        'getInstalledApps',
      );
      if (apps == null || apps.isEmpty) return const [];

      final seen = <String>{};
      final out = <InstalledAppInfo>[];
      for (final raw in apps) {
        if (raw is! Map) continue;
        final pkg = raw['package_name']?.toString().trim() ?? '';
        if (pkg.isEmpty || seen.contains(pkg)) continue;
        seen.add(pkg);
        final label = (raw['app_label']?.toString().trim().isNotEmpty == true)
            ? raw['app_label']!.toString().trim()
            : pkg;
        out.add(
          InstalledAppInfo(
            packageName: pkg,
            appLabel: label,
            iconBytes: _decodeIcon(raw['icon_png_base64']),
            isGame: raw['is_game'] == true,
            isPriority: raw['is_priority'] == true,
          ),
        );
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<List<ParentalAppRule>> _fetchRulesFromApi() async {
    final json = await ApiClient.instance.getJson(
      '/api/auth/parent/blocked-apps/',
    );
    if (json == null) return const [];
    final apps = (json['apps'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    return apps
        .map(
          (a) => ParentalAppRule(
            packageName: (a['package_name'] ?? '').toString(),
            appLabel: (a['app_label'] ?? a['package_name'] ?? '').toString(),
            blocked: parseBlockedFlag(a['blocked']),
            category: a['category']?.toString(),
          ),
        )
        .where((r) => r.packageName.isNotEmpty)
        .toList();
  }

  List<ParentalAppRule> _dedupeTikTokVariants(List<ParentalAppRule> mapped) {
    final results = <ParentalAppRule>[];
    var tiktokShown = false;
    for (final rule in mapped) {
      final key = '${rule.packageName} ${rule.appLabel}'.toLowerCase();
      final isTikTokVariant =
          key.contains('tiktok') ||
          key.contains('musically') ||
          key.contains('trill') ||
          key.contains('tiktok lite');
      if (isTikTokVariant) {
        if (tiktokShown) continue;
        tiktokShown = true;
      }
      results.add(rule);
    }
    return results;
  }

  /// Sync device inventory to backend, merge with API + local block state.
  Future<List<ParentalAppRule>> fetchRules({
    Map<String, String> preserveLabelsByPackage = const {},
  }) async {
    final deviceApps = await fetchInstalledAppsFromDevice();
    await syncInstalledApps(deviceApps: deviceApps);

    final apiRules = await _fetchRulesFromApi();
    final blockedPrefs = await _readBlocked();
    final nativeBlocked = await _readNativeBlockedPackages();

    final apiByPackage = <String, ParentalAppRule>{
      for (final rule in apiRules) rule.packageName: rule,
    };

    final byPackage = <String, ParentalAppRule>{};
    for (final app in deviceApps) {
      final existing = apiByPackage[app.packageName];
      final blocked = _isBlockedPackage(
        app.packageName,
        apiByPackage: apiByPackage,
        prefsBlocked: blockedPrefs,
        nativeBlocked: nativeBlocked,
      );
      byPackage[app.packageName] = ParentalAppRule(
        packageName: app.packageName,
        appLabel: ParentalAppCatalog.resolveAppLabel(
          packageName: app.packageName,
          deviceLabel: app.appLabel,
          apiLabel: existing?.appLabel,
          previousLabel: preserveLabelsByPackage[app.packageName],
        ),
        blocked: blocked,
        category: existing?.category ?? (app.isGame ? 'Games' : null),
        iconBytes: app.iconBytes,
        isGame: app.isGame,
        isPriority: app.isPriority ||
            ParentalAppCatalog.priorityRank(app.packageName, app.appLabel) <
                999,
      );
    }

    final merged = ParentalAppCatalog.sortForDisplay(
      _dedupeTikTokVariants(byPackage.values.toList()),
    );

    final blockedPkgs = _expandBlockedAliasesForAll(
      merged.where((r) => r.blocked).map((r) => r.packageName),
    );
    await _persistBlocked(blockedPkgs);
    await syncNativeHomeBlocker(blockedPkgs);

    return merged;
  }

  Future<bool> setBlocked({
    required String packageName,
    required bool blocked,
    String? appLabel,
  }) async {
    final label = (appLabel ?? '').trim();
    final response = await ApiClient.instance.put(
      '/api/auth/parent/blocked-apps/update/',
      body: {
        'package_name': packageName,
        'blocked': blocked,
        if (label.isNotEmpty) 'app_label': label,
      },
    );
    if (response == null) return false;
    final ok = response.statusCode >= 200 && response.statusCode < 300;
    if (!ok) {
      debugPrint(
        'setBlocked failed HTTP ${response.statusCode}: ${response.body}',
      );
      return false;
    }

    final existing = await _readBlocked();
    final aliases = _expandBlockedAliases(packageName);
    if (blocked) {
      existing.addAll(aliases);
    } else {
      existing.removeAll(aliases);
    }
    await _persistBlocked(existing);

    if (!kIsWeb) {
      await syncNativeHomeBlocker(existing);
      try {
        for (final alias in aliases) {
          await _channel.invokeMethod('setBlockedAppNow', {
            'packageName': alias,
            'blocked': blocked,
          });
        }
      } catch (_) {
        // Backend + home blocker list already saved.
      }
      if (blocked && existing.isNotEmpty) {
        try {
          await _channel.invokeMethod('ensureParentalEnforcementEnabled');
        } catch (_) {}
      }
    }
    return true;
  }

  Future<void> applyLocalPolicy({
    required int socialMinutesLimit,
    required int gamingMinutesLimit,
    required int entertainmentMinutesLimit,
    bool enableEnforcement = false,
  }) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('setParentalPolicy', {
        'socialLimitMinutes': socialMinutesLimit,
        'gamingLimitMinutes': gamingMinutesLimit,
        'entertainmentLimitMinutes': entertainmentMinutesLimit,
        'enableEnforcement': enableEnforcement,
      });
    } catch (_) {}
  }

  Future<void> syncInstalledApps({List<InstalledAppInfo>? deviceApps}) async {
    if (kIsWeb) return;
    try {
      final apps = deviceApps ?? await fetchInstalledAppsFromDevice();
      if (apps.isEmpty) return;

      final payload = apps
          .map(
            (e) => {
              'package_name': e.packageName,
              'app_label': e.appLabel,
            },
          )
          .toList();

      await ApiClient.instance.post(
        '/api/auth/parent/installed-apps/report/',
        body: {'apps': payload},
      );
    } catch (_) {}
  }
}
