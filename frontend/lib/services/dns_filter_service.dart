import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// DNS-based content restrictions and safety controls (Android VPN / iOS stub).
class DnsFilterStatus {
  const DnsFilterStatus({
    required this.vpnActive,
    required this.blockSocial,
    required this.blockGaming,
    required this.blockEntertainment,
    required this.safeSearch,
    required this.blockAdult,
    required this.blockedDomainCount,
    required this.upstreamDns,
    required this.socialStatus,
    required this.gamingStatus,
    required this.entertainmentStatus,
    required this.safeSearchStatus,
    required this.adultBlockStatus,
    required this.filterStatusLabel,
    required this.platform,
    required this.supported,
  });

  final bool vpnActive;
  final bool blockSocial;
  final bool blockGaming;
  final bool blockEntertainment;
  final bool safeSearch;
  final bool blockAdult;
  final int blockedDomainCount;
  final String upstreamDns;
  final String socialStatus;
  final String gamingStatus;
  final String entertainmentStatus;
  final String safeSearchStatus;
  final String adultBlockStatus;
  final String filterStatusLabel;
  final String platform;
  final bool supported;

  static const empty = DnsFilterStatus(
    vpnActive: false,
    blockSocial: false,
    blockGaming: false,
    blockEntertainment: false,
    safeSearch: false,
    blockAdult: false,
    blockedDomainCount: 0,
    upstreamDns: 'System default',
    socialStatus: 'DNS: Off',
    gamingStatus: 'DNS: Off',
    entertainmentStatus: 'DNS: Off',
    safeSearchStatus: 'Off',
    adultBlockStatus: 'Off',
    filterStatusLabel: 'No filtering active',
    platform: 'unknown',
    supported: false,
  );

  factory DnsFilterStatus.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return DnsFilterStatus.empty;
    String readStr(String key, String fallback) {
      final v = map[key];
      return v?.toString() ?? fallback;
    }

    bool readBool(String key) => map[key] == true;

    return DnsFilterStatus(
      vpnActive: readBool('vpnActive'),
      blockSocial: readBool('blockSocial'),
      blockGaming: readBool('blockGaming'),
      blockEntertainment: readBool('blockEntertainment'),
      safeSearch: readBool('safeSearch'),
      blockAdult: readBool('blockAdult'),
      blockedDomainCount: (map['blockedDomainCount'] as num?)?.toInt() ?? 0,
      upstreamDns: readStr('upstreamDns', 'System default'),
      socialStatus: readStr('socialStatus', 'DNS: Off'),
      gamingStatus: readStr('gamingStatus', 'DNS: Off'),
      entertainmentStatus: readStr('entertainmentStatus', 'DNS: Off'),
      safeSearchStatus: readStr('safeSearchStatus', 'Off'),
      adultBlockStatus: readStr('adultBlockStatus', 'Off'),
      filterStatusLabel: readStr('filterStatusLabel', 'No filtering active'),
      platform: readStr('platform', 'unknown'),
      supported: readStr('platform', '') == 'android',
    );
  }
}

class DnsFilterService {
  DnsFilterService._();
  static final DnsFilterService instance = DnsFilterService._();

  static const _channel = MethodChannel('mindsync/dns_filter');

  Future<DnsFilterStatus> getStatus() async {
    if (kIsWeb) return DnsFilterStatus.empty;
    try {
      final map = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'dnsFilterGetStatus',
      );
      return DnsFilterStatus.fromMap(map);
    } catch (_) {
      return _statusFromPrefs();
    }
  }

  Future<bool> hasVpnPermission() async {
    if (kIsWeb) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('dnsFilterHasVpnPermission');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Returns true if VPN permission granted (or not needed).
  Future<bool> prepareVpn() async {
    if (kIsWeb) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('dnsFilterPrepareVpn');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<DnsFilterStatus> applyConfig({
    required bool blockSocial,
    required bool blockGaming,
    required bool blockEntertainment,
    required bool safeSearch,
    required bool blockAdult,
  }) async {
    await _persistConfig(
      blockSocial: blockSocial,
      blockGaming: blockGaming,
      blockEntertainment: blockEntertainment,
      safeSearch: safeSearch,
      blockAdult: blockAdult,
    );

    if (kIsWeb) {
      return _statusFromPrefs();
    }

    try {
      final map = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'dnsFilterApplyConfig',
        {
          'blockSocial': blockSocial,
          'blockGaming': blockGaming,
          'blockEntertainment': blockEntertainment,
          'safeSearch': safeSearch,
          'blockAdult': blockAdult,
        },
      );
      return DnsFilterStatus.fromMap(map);
    } catch (_) {
      return _statusFromPrefs();
    }
  }

  Future<void> restoreFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final blockSocial = prefs.getBool('dns.blockSocial') ?? false;
    final blockGaming = prefs.getBool('dns.blockGaming') ?? false;
    final blockEntertainment = prefs.getBool('dns.blockEntertainment') ?? false;
    final safeSearch = prefs.getBool('dns.safeSearch') ?? false;
    final blockAdult = prefs.getBool('dns.blockAdult') ?? false;
    if (!blockSocial &&
        !blockGaming &&
        !blockEntertainment &&
        !safeSearch &&
        !blockAdult) {
      return;
    }
    await applyConfig(
      blockSocial: blockSocial,
      blockGaming: blockGaming,
      blockEntertainment: blockEntertainment,
      safeSearch: safeSearch,
      blockAdult: blockAdult,
    );
  }

  Future<void> loadPrefsInto({
    required void Function({
      required bool blockSocial,
      required bool blockGaming,
      required bool blockEntertainment,
      required bool safeSearch,
      required bool blockAdult,
    }) apply,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    apply(
      blockSocial: prefs.getBool('dns.blockSocial') ?? false,
      blockGaming: prefs.getBool('dns.blockGaming') ?? false,
      blockEntertainment: prefs.getBool('dns.blockEntertainment') ?? false,
      safeSearch: prefs.getBool('dns.safeSearch') ?? false,
      blockAdult: prefs.getBool('dns.blockAdult') ?? false,
    );
  }

  Future<void> _persistConfig({
    required bool blockSocial,
    required bool blockGaming,
    required bool blockEntertainment,
    required bool safeSearch,
    required bool blockAdult,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dns.blockSocial', blockSocial);
    await prefs.setBool('dns.blockGaming', blockGaming);
    await prefs.setBool('dns.blockEntertainment', blockEntertainment);
    await prefs.setBool('dns.safeSearch', safeSearch);
    await prefs.setBool('dns.blockAdult', blockAdult);
  }

  Future<DnsFilterStatus> _statusFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final blockSocial = prefs.getBool('dns.blockSocial') ?? false;
    final blockGaming = prefs.getBool('dns.blockGaming') ?? false;
    final blockEntertainment = prefs.getBool('dns.blockEntertainment') ?? false;
    final safeSearch = prefs.getBool('dns.safeSearch') ?? false;
    final blockAdult = prefs.getBool('dns.blockAdult') ?? false;
    return DnsFilterStatus(
      vpnActive: false,
      blockSocial: blockSocial,
      blockGaming: blockGaming,
      blockEntertainment: blockEntertainment,
      safeSearch: safeSearch,
      blockAdult: blockAdult,
      blockedDomainCount: 0,
      upstreamDns: (safeSearch || blockAdult) ? '94.140.14.15' : '1.1.1.1',
      socialStatus: blockSocial ? 'DNS: Pending' : 'DNS: Off',
      gamingStatus: blockGaming ? 'DNS: Pending' : 'DNS: Off',
      entertainmentStatus: blockEntertainment ? 'DNS: Pending' : 'DNS: Off',
      safeSearchStatus: safeSearch ? 'Pending' : 'Off',
      adultBlockStatus: blockAdult ? 'Pending' : 'Off',
      filterStatusLabel: (safeSearch || blockAdult)
          ? 'Protected by AdGuard Family DNS'
          : (blockSocial || blockGaming || blockEntertainment)
              ? 'Category DNS blocking active'
              : 'No filtering active',
      platform: defaultTargetPlatform.name,
      supported: !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
    );
  }
}
