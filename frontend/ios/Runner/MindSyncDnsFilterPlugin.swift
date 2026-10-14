import Flutter
import UIKit

/// iOS DNS filter stub — full filtering requires a Network Extension target
/// (NEDNSProxyProvider or NEFilterDataProvider) with Apple entitlements.
public class MindSyncDnsFilterPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "mindsync/dns_filter",
      binaryMessenger: registrar.messenger()
    )
    let instance = MindSyncDnsFilterPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "dnsFilterGetStatus":
      result(MindSyncDnsFilterPlugin.statusMap())
    case "dnsFilterApplyConfig":
      result(MindSyncDnsFilterPlugin.statusMap())
    case "dnsFilterPrepareVpn":
      result(FlutterError(
        code: "ios_unsupported",
        message: "Add a Network Extension (NEDNSProxyProvider) to enable DNS filtering on iOS.",
        details: nil
      ))
    case "dnsFilterHasVpnPermission":
      result(false)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func statusMap() -> [String: Any] {
    [
      "vpnActive": false,
      "blockSocial": false,
      "blockGaming": false,
      "blockEntertainment": false,
      "safeSearch": false,
      "blockAdult": false,
      "blockedDomainCount": 0,
      "upstreamDns": "System default",
      "safeSearchStatus": "iOS extension required",
      "adultBlockStatus": "iOS extension required",
      "socialStatus": "iOS extension required",
      "gamingStatus": "iOS extension required",
      "entertainmentStatus": "iOS extension required",
      "platform": "ios",
    ]
  }
}
