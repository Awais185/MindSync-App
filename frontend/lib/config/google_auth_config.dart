import 'package:flutter/foundation.dart' show kIsWeb;

/// Google OAuth client IDs for MindSync.
///
/// Register OAuth 2.0 credentials in Google Cloud Console (project: mindsync-c6917):
/// 1. Web application client → pass as [webClientId] (also used as Android `serverClientId`).
/// 2. Android client → download updated `google-services.json` (package: com.example.frontend).
/// 3. Add your debug/release SHA-1 fingerprints to the Android OAuth client.
///
/// Run with:
/// `flutter run --dart-define=GOOGLE_WEB_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com`
abstract final class GoogleAuthConfig {
  GoogleAuthConfig._();

  static const String webClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '',
  );

  static const String iosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
    defaultValue: '',
  );

  static bool get isConfigured {
    if (kIsWeb) return webClientId.trim().isNotEmpty;
    return webClientId.trim().isNotEmpty;
  }

  static String get configurationHint =>
      'Google Sign-In is not configured. Add GOOGLE_WEB_CLIENT_ID via '
      '--dart-define and register OAuth clients in Google Cloud Console.';
}
