import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Hashes passwords for local SQLite login only (never sent to Firestore).
class PasswordHash {
  PasswordHash._();

  static const _googleMarker = '__google_account__';

  static String hash(String password) {
    final salt = _randomSalt();
    final digest = sha256.convert(utf8.encode('$salt:$password'));
    return '$salt:${digest.toString()}';
  }

  static String googleAccountMarker() => _googleMarker;

  static bool verify(String password, String stored) {
    if (stored == _googleMarker) return false;
    final parts = stored.split(':');
    if (parts.length < 2) return false;
    final salt = parts.first;
    final expected = parts.sublist(1).join(':');
    final digest = sha256.convert(utf8.encode('$salt:$password')).toString();
    return digest == expected;
  }

  static bool isGoogleAccount(String stored) => stored == _googleMarker;

  static String _randomSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Url.encode(bytes);
  }
}
