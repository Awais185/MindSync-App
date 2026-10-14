import '../models/app_user.dart';
import '../services/local_db_service.dart';
import '../utils/password_hash.dart';

/// Mirrors Django auth responses into on-device SQLite (login source).
class AuthLocalSync {
  AuthLocalSync._();

  static Future<void> saveFromBackendUser(
    Map<String, dynamic> user, {
    required String password,
    bool isGoogleAccount = false,
  }) async {
    final appUser = appUserFromBackendMap(user);
    final hash = isGoogleAccount
        ? PasswordHash.googleAccountMarker()
        : PasswordHash.hash(password);

    await LocalDbService.instance.saveUserWithPassword(
      appUser,
      passwordHash: hash,
      isGoogleAccount: isGoogleAccount,
    );
  }

  static AppUser appUserFromBackendMap(Map<String, dynamic> user) {
    final id = user['id']?.toString() ?? '';
    final email = (user['email'] as String?) ?? '';
    final firstName = (user['first_name'] as String?) ?? '';
    return AppUser(
      uid: id.isEmpty ? 'user_${email.hashCode}' : id,
      name: firstName,
      email: email.trim().toLowerCase(),
      createdAt: DateTime.now().toUtc(),
      firstName: firstName,
      lastName: (user['last_name'] as String?) ?? '',
      username: (user['username'] as String?) ?? '',
      profession: (user['profession'] as String?) ?? 'other',
      faceImage: (user['face_image'] as String?) ?? '',
      faceEnrolled: (user['face_enrolled'] as bool?) ?? false,
      isDoctor: (user['is_doctor'] as bool?) ?? false,
    );
  }
}
