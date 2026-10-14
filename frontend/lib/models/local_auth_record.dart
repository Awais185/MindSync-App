import 'app_user.dart';

/// User profile plus credentials stored only in the local database.
class LocalAuthRecord {
  const LocalAuthRecord({
    required this.user,
    required this.passwordHash,
    this.isGoogleAccount = false,
  });

  final AppUser user;
  final String passwordHash;
  final bool isGoogleAccount;
}
