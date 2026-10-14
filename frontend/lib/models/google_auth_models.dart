import '../config/google_auth_config.dart';

/// Prefill data when login via Google finds no existing MindSync account.
class GoogleSignupPrefill {
  const GoogleSignupPrefill({
    required this.email,
    required this.displayName,
    required this.firstName,
    required this.uid,
    this.lastName = '',
    this.photoUrl,
  });

  final String email;
  final String displayName;
  final String firstName;
  final String lastName;
  final String? photoUrl;
  final String uid;

  factory GoogleSignupPrefill.fromJson(Map<String, dynamic> json) {
    return GoogleSignupPrefill(
      email: (json['email'] as String?) ?? '',
      displayName: (json['display_name'] as String?) ?? '',
      firstName: (json['first_name'] as String?) ?? '',
      lastName: (json['last_name'] as String?) ?? '',
      photoUrl: json['photo_url'] as String?,
      uid: (json['uid'] as String?) ?? '',
    );
  }
}

/// Result of the native Google Sign-In UI (before backend exchange).
class GoogleSignInCredentials {
  const GoogleSignInCredentials({
    required this.email,
    required this.displayName,
    required this.photoUrl,
    required this.uid,
    required this.accessToken,
    this.firstName = '',
    this.lastName = '',
  });

  final String email;
  final String displayName;
  final String photoUrl;
  final String uid;
  final String accessToken;
  final String firstName;
  final String lastName;
}

enum GoogleAuthFailure {
  cancelled,
  notConfigured,
  networkError,
  playServicesUnavailable,
  userNotFound,
  passwordAccountExists,
  emailAlreadyRegistered,
  unknown,
}

class GoogleAuthException implements Exception {
  GoogleAuthException(
    this.failure, {
    this.message,
    this.prefill,
  });

  final GoogleAuthFailure failure;
  final String? message;
  final GoogleSignupPrefill? prefill;

  @override
  String toString() => message ?? _defaultMessage(failure);

  static String _defaultMessage(GoogleAuthFailure failure) {
    switch (failure) {
      case GoogleAuthFailure.cancelled:
        return 'Google sign-in was cancelled.';
      case GoogleAuthFailure.notConfigured:
        return GoogleAuthConfig.configurationHint;
      case GoogleAuthFailure.networkError:
        return 'Network error. Check your connection and try again.';
      case GoogleAuthFailure.playServicesUnavailable:
        return 'Google Play Services is unavailable or outdated on this device.';
      case GoogleAuthFailure.userNotFound:
        return 'No MindSync account exists for this Google email.';
      case GoogleAuthFailure.passwordAccountExists:
        return 'An account with this email already exists. Log in with email and password.';
      case GoogleAuthFailure.emailAlreadyRegistered:
        return 'An account with this email already exists. Log in instead.';
      case GoogleAuthFailure.unknown:
        return 'Unable to sign in with Google right now.';
    }
  }
}
