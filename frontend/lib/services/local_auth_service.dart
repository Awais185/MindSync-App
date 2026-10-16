import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../config/google_auth_config.dart';
import '../models/app_user.dart';
import '../models/google_auth_models.dart';
import '../services/auth_local_sync.dart';
import '../services/user_session_cache.dart';
import '../services/auth_api_exception.dart';
import '../services/database_auth_service.dart';
import '../services/local_db_service.dart';
import '../utils/password_hash.dart';

class LocalAuthUser {
  const LocalAuthUser({
    required this.firstName,
    required this.profession,
    required this.email,
    required this.password,
    required this.faceImageData,
  });

  final String firstName;
  final String profession;
  final String email;
  final String password;
  final String faceImageData;
}

class AuthProfile {
  const AuthProfile({
    required this.username,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.profession,
    required this.faceEnrolled,
    required this.faceImage,
    required this.isDoctor,
    this.isApprovedDoctor = false,
  });

  final String username;
  final String firstName;
  final String lastName;
  final String email;
  final String profession;
  final bool faceEnrolled;
  final String? faceImage;
  final bool isDoctor;
  final bool isApprovedDoctor;

  String get displayName {
    if (firstName.trim().isNotEmpty) return firstName.trim();
    if (username.trim().isNotEmpty) return username.trim();
    if (email.trim().isNotEmpty) return email.trim().split('@').first;
    return 'User';
  }

  String get fullName {
    final first = firstName.trim();
    final last = lastName.trim();
    if (first.isEmpty && last.isEmpty) return displayName;
    return '$first $last'.trim();
  }
}

/// Login/signup use Django REST API (PostgreSQL on the server) via REST only.
/// Device SQLite is an offline cache after a successful server login.
/// Django JWT + local SQLite cache only (no Firebase).
class LocalAuthService {
  LocalAuthService._();

  static final LocalAuthService instance = LocalAuthService._();

  factory LocalAuthService() => instance;

  static const _kFirstName = 'auth.firstName';
  static const _kProfession = 'auth.profession';
  static const _kEmail = 'auth.email';
  static const _kFaceData = 'auth.faceData';
  static const _kUsername = 'auth.username';
  static const _kLastName = 'auth.lastName';
  static const _kFaceEnrolled = 'auth.faceEnrolled';
  static const _kUserId = 'auth.userId';
  static const _kAccessToken = 'auth.accessToken';
  static const _kRefreshToken = 'auth.refreshToken';
  static const _kIsDoctor = 'auth.isDoctor';
  static const _kIsApprovedDoctor = 'auth.isApprovedDoctor';
  static const _kLocalSessionUid = 'auth.localSessionUid';

  static const String _googleWebClientId = GoogleAuthConfig.webClientId;

  static GoogleSignIn _createGoogleSignIn() {
    final webId = _googleWebClientId.trim();
    return GoogleSignIn(
      scopes: const <String>['email', 'profile'],
      clientId: kIsWeb && webId.isNotEmpty ? webId : null,
      serverClientId: !kIsWeb && webId.isNotEmpty ? webId : null,
    );
  }

  static final GoogleSignIn _googleSignIn = _createGoogleSignIn();

  final LocalDbService _localDb = LocalDbService.instance;
  final DatabaseAuthService _database = DatabaseAuthService.instance;

  Future<String?> getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_kAccessToken);
    if (token == null || token.isEmpty) return null;
    return token;
  }

  Future<bool> tryRefreshAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    final refresh = prefs.getString(_kRefreshToken);
    if (refresh == null || refresh.isEmpty) return false;

    try {
      final response = await http
          .post(
            ApiConfig.uri('/api/auth/token/refresh/'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refresh': refresh}),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return false;
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final access = body['access'] as String?;
      if (access == null || access.isEmpty) return false;

      await prefs.setString(_kAccessToken, access);
      final newRefresh = body['refresh'] as String?;
      if (newRefresh != null && newRefresh.isNotEmpty) {
        await prefs.setString(_kRefreshToken, newRefresh);
      }
      return true;
    } on Exception {
      return false;
    }
  }

  String _normalizeProfession(String raw) {
    final value = raw.trim().toLowerCase();
    if (value.contains('student')) return 'student';
    if (value.contains('professional')) return 'professional';
    return 'other';
  }

  Future<LocalAuthUser> signup({
    required String firstName,
    required String username,
    required String profession,
    required String ageRange,
    required String email,
    required String password,
    Uint8List? faceImageBytes,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final request =
        http.MultipartRequest('POST', ApiConfig.uri('/api/auth/signup/'));
    request.fields['username'] = username.trim().isEmpty
        ? normalizedEmail.split('@').first
        : username.trim();
    request.fields['email'] = normalizedEmail;
    request.fields['password'] = password;
    request.fields['first_name'] = firstName;
    request.fields['last_name'] = '-';
    request.fields['profession'] = _normalizeProfession(profession);
    request.fields['age_range'] = ageRange.trim();

    if (faceImageBytes != null && faceImageBytes.isNotEmpty) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'face_image',
          faceImageBytes,
          filename: 'face.jpg',
        ),
      );
    }

    await _database.signupMultipart(request);

    try {
      return await login(normalizedEmail, password);
    } on AuthApiException catch (e) {
      throw Exception(
        'Account created, but login failed: ${e.message}',
      );
    }
  }

  Future<void> resetPasswordWithIdentity({
    required String email,
    required String username,
    required String fullName,
    required String newPassword,
    required String confirmPassword,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    http.Response response;
    try {
      response = await http
          .post(
            ApiConfig.uri('/api/auth/password/reset/'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': normalizedEmail,
              'username': username.trim(),
              'full_name': fullName.trim(),
              'new_password': newPassword,
              'confirm_password': confirmPassword,
            }),
          )
          .timeout(const Duration(seconds: 20));
    } on Exception {
      throw AuthApiException(
        'Unable to connect to backend at ${ApiConfig.baseUrl}. '
        'Start the server and check adb reverse / Wi‑Fi.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode >= 500) {
        throw AuthApiException('Server error. Please try again in a moment.');
      }
      throw AuthApiException(_extractErrorMessage(response.body));
    }

    try {
      await login(normalizedEmail, newPassword);
    } on AuthApiException {
      throw Exception('Password updated. Please log in with your new password.');
    }
  }

  /// Login: search Django SQL database first (existing accounts), then device cache if offline.
  Future<LocalAuthUser> login(String email, String password) async {
    final normalized = email.trim().toLowerCase();
    final rawInput = email.trim();

    try {
      return await _loginViaDatabase(rawInput, password);
    } on AuthApiException catch (e) {
      if (!e.isInvalidCredentials) {
        rethrow;
      }
      await _localDb.ensureMigrated();
      final offline = await _tryLocalLogin(normalized, password) ??
          await _tryLocalLogin(rawInput, password);
      if (offline != null) return offline;
      rethrow;
    } on Exception catch (e) {
      final msg = e.toString();
      if (!msg.contains('Cannot reach MindSync server')) {
        rethrow;
      }
      await _localDb.ensureMigrated();
      final offline = await _tryLocalLogin(normalized, password) ??
          await _tryLocalLogin(rawInput, password);
      if (offline != null) return offline;
      rethrow;
    }
  }

  Future<LocalAuthUser?> _tryLocalLogin(String identifier, String password) async {
    final trimmed = identifier.trim();
    var record = await _localDb.getUserByEmail(trimmed.toLowerCase());
    record ??= await _localDb.getUserByUsername(trimmed);
    if (record == null) return null;
    if (record.isGoogleAccount) return null;

    if (record.passwordHash.isEmpty) {
      return null;
    }
    if (!PasswordHash.verify(password, record.passwordHash)) {
      return null;
    }

    await UserSessionCache.onUserSessionStarting();
    await _setLocalSession(record.user.uid);
    await _persistProfileFromAppUser(record.user);
    unawaited(UserSessionCache.onUserSessionReady());
    debugPrint(
      'LocalAuthService: login from local SQLite (${record.user.email})',
    );
    return _toLocalAuthUser(record.user);
  }

  Future<LocalAuthUser> _loginViaDatabase(
    String emailOrUsername,
    String password,
  ) async {
    final body = await _database.login(
      emailOrUsername: emailOrUsername,
      password: password,
    );

    final user = body['user'] as Map<String, dynamic>? ?? const {};
    final email = (user['email'] as String?) ?? emailOrUsername;
    await AuthLocalSync.saveFromBackendUser(user, password: password);
    debugPrint(
      'LocalAuthService: login OK from Django SQL DB — ${user['id']} $email',
    );
    final session = await _persistAuthResponse(body, fallbackEmail: email);
    if (session == null) {
      throw AuthApiException(
        'Login succeeded but the app could not save your session. Try again.',
      );
    }
    return session;
  }

  Future<GoogleSignInCredentials> _signInWithGoogleUi() async {
    if (!GoogleAuthConfig.isConfigured) {
      throw GoogleAuthException(GoogleAuthFailure.notConfigured);
    }

    GoogleSignInAccount? account;
    try {
      account = await _googleSignIn.signIn();
    } on PlatformException catch (e) {
      throw _mapGooglePlatformException(e);
    } on Exception catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('network')) {
        throw GoogleAuthException(GoogleAuthFailure.networkError);
      }
      throw GoogleAuthException(
        GoogleAuthFailure.unknown,
        message: 'Unable to open Google sign-in right now.',
      );
    }

    if (account == null) {
      throw GoogleAuthException(GoogleAuthFailure.cancelled);
    }

    GoogleSignInAuthentication auth;
    try {
      auth = await account.authentication;
    } on PlatformException catch (e) {
      throw _mapGooglePlatformException(e);
    }

    final accessToken = auth.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      throw GoogleAuthException(
        GoogleAuthFailure.unknown,
        message: 'Google sign-in did not return an access token. '
            'Ensure GOOGLE_WEB_CLIENT_ID is set to your Web OAuth client ID.',
      );
    }

    final displayName = account.displayName?.trim() ?? '';
    final parts = displayName.split(' ');
    final firstName = parts.isNotEmpty ? parts.first : '';
    final lastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';

    return GoogleSignInCredentials(
      email: account.email.trim().toLowerCase(),
      displayName: displayName.isNotEmpty ? displayName : account.email,
      photoUrl: account.photoUrl ?? '',
      uid: account.id,
      accessToken: accessToken,
      firstName: firstName,
      lastName: lastName,
    );
  }

  GoogleAuthException _mapGooglePlatformException(PlatformException e) {
    final code = e.code.toLowerCase();
    final message = (e.message ?? '').toLowerCase();
    if (code.contains('canceled') || code.contains('cancelled')) {
      return GoogleAuthException(GoogleAuthFailure.cancelled);
    }
    if (code.contains('network') || message.contains('network')) {
      return GoogleAuthException(GoogleAuthFailure.networkError);
    }
    if (message.contains('play services') ||
        message.contains('12500') ||
        message.contains('apiexception: 10') ||
        message.contains('service_disabled')) {
      return GoogleAuthException(GoogleAuthFailure.playServicesUnavailable);
    }
    return GoogleAuthException(
      GoogleAuthFailure.unknown,
      message: e.message ?? 'Google sign-in failed.',
    );
  }

  Future<LocalAuthUser> _exchangeGoogleToken({
    required String accessToken,
    required String flow,
    required String fallbackEmail,
  }) async {
    http.Response response;
    try {
      response = await http
          .post(
            ApiConfig.uri('/api/auth/google/'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'access_token': accessToken,
              'flow': flow,
            }),
          )
          .timeout(const Duration(seconds: 20));
    } on Exception {
      throw GoogleAuthException(GoogleAuthFailure.networkError);
    }

    if (response.statusCode == 404) {
      final parsed = _parseJsonBody(response.body);
      final code = parsed?['code']?.toString();
      if (code == 'user_not_found') {
        final profile = parsed?['google_profile'];
        GoogleSignupPrefill? prefill;
        if (profile is Map<String, dynamic>) {
          prefill = GoogleSignupPrefill.fromJson(profile);
        }
        throw GoogleAuthException(
          GoogleAuthFailure.userNotFound,
          prefill: prefill,
        );
      }
    }

    if (response.statusCode == 409) {
      final parsed = _parseJsonBody(response.body);
      final code = parsed?['code']?.toString();
      final message = _readBackendMessage(parsed);
      if (code == 'password_account_exists') {
        throw GoogleAuthException(
          GoogleAuthFailure.passwordAccountExists,
          message: message,
        );
      }
      if (code == 'email_already_registered') {
        throw GoogleAuthException(
          GoogleAuthFailure.emailAlreadyRegistered,
          message: message,
        );
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GoogleAuthException(
        GoogleAuthFailure.unknown,
        message: _extractErrorMessage(response.body),
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final user = body['user'] as Map<String, dynamic>? ?? const {};
    await AuthLocalSync.saveFromBackendUser(
      user,
      password: '',
      isGoogleAccount: true,
    );
    final loggedIn = await _persistAuthResponse(body, fallbackEmail: fallbackEmail);
    if (loggedIn == null) {
      throw GoogleAuthException(
        GoogleAuthFailure.unknown,
        message: 'Google sign-in succeeded but session could not be saved.',
      );
    }
    return loggedIn;
  }

  /// Login flow: existing Google (or linked) accounts only.
  /// Throws [GoogleAuthException.userNotFound] with prefill when no account exists.
  Future<LocalAuthUser> loginWithGoogle() async {
    final credentials = await _signInWithGoogleUi();
    return _exchangeGoogleToken(
      accessToken: credentials.accessToken,
      flow: 'login',
      fallbackEmail: credentials.email,
    );
  }

  /// Signup flow: creates a MindSync account from Google profile when email is new.
  Future<LocalAuthUser> signupWithGoogle() async {
    final credentials = await _signInWithGoogleUi();
    return _exchangeGoogleToken(
      accessToken: credentials.accessToken,
      flow: 'signup',
      fallbackEmail: credentials.email,
    );
  }

  Map<String, dynamic>? _parseJsonBody(String body) {
    try {
      final parsed = jsonDecode(body);
      if (parsed is Map<String, dynamic>) return parsed;
    } catch (_) {}
    return null;
  }

  String? _readBackendMessage(Map<String, dynamic>? parsed) {
    if (parsed == null) return null;
    final message = parsed['message'];
    if (message is String && message.isNotEmpty) return message;
    return null;
  }

  Future<String> persistFaceImageBytes(List<int> bytes) async {
    return base64Encode(bytes);
  }

  Future<void> logout() async {
    await UserSessionCache.onLogout();
    try {
      await _googleSignIn.signOut();
    } on Object {
      // ignore
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAccessToken);
    await prefs.remove(_kRefreshToken);
    await prefs.remove(_kUsername);
    await prefs.remove(_kFirstName);
    await prefs.remove(_kLastName);
    await prefs.remove(_kProfession);
    await prefs.remove(_kEmail);
    await prefs.remove(_kFaceEnrolled);
    await prefs.remove(_kFaceData);
    await prefs.remove(_kUserId);
    await prefs.remove(_kLocalSessionUid);
    await prefs.remove(_kIsDoctor);
  }

  Future<AuthProfile?> restoreSessionIfPossible() async {
    final prefs = await SharedPreferences.getInstance();
    final localUid = prefs.getString(_kLocalSessionUid) ?? prefs.getString(_kUserId);
    if (localUid != null && localUid.isNotEmpty) {
      final record = await _localDb.getUser(localUid);
      if (record != null) {
        await _persistProfileFromAppUser(record.user);
      }
    }

    var token = prefs.getString(_kAccessToken);
    if (token == null || token.isEmpty) {
      return _getStoredProfile();
    }

    Future<http.Response> fetchMe(String t) => http
        .get(
          ApiConfig.uri('/api/auth/me/'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $t',
          },
        )
        .timeout(const Duration(seconds: 20));

    try {
      var response = await fetchMe(token);
      if (response.statusCode == 401) {
        final refreshed = await tryRefreshAccessToken();
        if (!refreshed) return _getStoredProfile();
        token = prefs.getString(_kAccessToken) ?? '';
        if (token.isEmpty) return _getStoredProfile();
        response = await fetchMe(token);
        if (response.statusCode == 401) {
          await logout();
          return null;
        }
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        await _persistProfile(body);
        final record = await _localDb.getUser(
          (body['id'] ?? '').toString(),
        );
        if (record != null) {
          await _persistProfileFromAppUser(record.user);
        }
        return _getStoredProfile();
      }
    } catch (_) {
      // offline — keep local session
    }

    return _getStoredProfile();
  }

  Future<AuthProfile?> fetchCurrentUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final localUid = prefs.getString(_kLocalSessionUid) ?? prefs.getString(_kUserId);
    if (localUid != null && localUid.isNotEmpty) {
      final record = await _localDb.getUser(localUid);
      if (record != null) {
        await _persistProfileFromAppUser(record.user);
        return _toAuthProfile(record.user);
      }
    }

    final token = prefs.getString(_kAccessToken);
    if (token == null || token.isEmpty) {
      return _getStoredProfile();
    }

    try {
      var response = await http
          .get(
            ApiConfig.uri('/api/auth/me/'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 401) {
        if (await tryRefreshAccessToken()) {
          final newToken = prefs.getString(_kAccessToken);
          if (newToken != null && newToken.isNotEmpty) {
            response = await http
                .get(
                  ApiConfig.uri('/api/auth/me/'),
                  headers: {
                    'Content-Type': 'application/json',
                    'Authorization': 'Bearer $newToken',
                  },
                )
                .timeout(const Duration(seconds: 20));
          }
        }
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        await _persistProfile(body);
      }
    } catch (_) {
      // use local cache
    }

    return _getStoredProfile();
  }

  Future<AuthProfile> updateProfile({
    required String firstName,
    required String lastName,
    required String username,
    required String email,
    required String profession,
    Uint8List? faceImageBytes,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_kAccessToken);
    if (token == null || token.isEmpty) {
      throw Exception('Please login again to update profile.');
    }

    final request = http.MultipartRequest(
      'PUT',
      ApiConfig.uri('/api/auth/profile/update/'),
    );
    request.headers['Authorization'] = 'Bearer $token';
    request.fields['first_name'] = firstName.trim();
    request.fields['last_name'] = lastName.trim();
    request.fields['username'] = username.trim();
    request.fields['email'] = email.trim();
    request.fields['profession'] = _normalizeProfession(profession);

    if (faceImageBytes != null && faceImageBytes.isNotEmpty) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'face_image',
          faceImageBytes,
          filename: 'profile.jpg',
        ),
      );
    }

    http.Response response;
    try {
      final streamed = await request.send().timeout(
        const Duration(seconds: 20),
      );
      response = await http.Response.fromStream(streamed);
    } on Exception {
      throw Exception('Unable to connect to backend for profile update.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractErrorMessage(response.body));
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    body['face_enrolled'] =
        (body['face_image'] as String?)?.isNotEmpty ?? false;
    await _persistProfile(body);

    final uid = await getStoredUserId();
    if (uid != null) {
      final record = await _localDb.getUser(uid);
      if (record != null) {
        final appUser = AuthLocalSync.appUserFromBackendMap(body);
        await _localDb.saveUserWithPassword(
          appUser,
          passwordHash: record.passwordHash,
          isGoogleAccount: record.isGoogleAccount,
        );
      }
    }

    final profile = await _getStoredProfile();
    if (profile == null) {
      throw Exception('Profile updated but failed to refresh data.');
    }
    return profile;
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_kAccessToken);
    if (token == null || token.isEmpty) {
      throw Exception('Please login again to change password.');
    }

    http.Response response;
    try {
      response = await http
          .post(
            ApiConfig.uri('/api/auth/password/change/'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'current_password': currentPassword,
              'new_password': newPassword,
            }),
          )
          .timeout(const Duration(seconds: 20));
    } on Exception {
      throw Exception('Unable to connect to backend for password change.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractErrorMessage(response.body));
    }

    final uid = await getStoredUserId();
    if (uid != null) {
      final record = await _localDb.getUser(uid);
      if (record != null && !record.isGoogleAccount) {
        await _localDb.updatePasswordHash(uid, PasswordHash.hash(newPassword));
      }
    }
  }

  String resolveMediaUrl(String? pathOrUrl) {
    if (pathOrUrl == null || pathOrUrl.isEmpty) return '';
    if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
      return pathOrUrl;
    }
    final slash = pathOrUrl.startsWith('/') ? '' : '/';
    return '${ApiConfig.baseUrl}$slash$pathOrUrl';
  }

  Future<AuthProfile?> _getStoredProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString(_kEmail);
    final firstName = prefs.getString(_kFirstName) ?? '';
    final username = prefs.getString(_kUsername) ?? '';
    if ((email == null || email.isEmpty) &&
        firstName.isEmpty &&
        username.isEmpty) {
      return null;
    }

    return AuthProfile(
      username: username,
      firstName: firstName,
      lastName: prefs.getString(_kLastName) ?? '',
      email: email ?? '',
      profession: prefs.getString(_kProfession) ?? 'other',
      faceEnrolled: prefs.getBool(_kFaceEnrolled) ?? false,
      faceImage: prefs.getString(_kFaceData),
      isDoctor: prefs.getBool(_kIsDoctor) ?? false,
      isApprovedDoctor: prefs.getBool(_kIsApprovedDoctor) ?? false,
    );
  }

  Future<String?> getStoredUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_kUserId);
    if (id == null || id.isEmpty) return null;
    return id;
  }

  Future<void> _setLocalSession(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLocalSessionUid, uid);
    await prefs.setString(_kUserId, uid);
  }

  Future<void> _persistProfileFromAppUser(AppUser user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUsername, user.username);
    await prefs.setString(_kFirstName, user.firstName);
    await prefs.setString(_kLastName, user.lastName);
    await prefs.setString(_kProfession, user.profession);
    await prefs.setString(_kEmail, user.email);
    await prefs.setBool(_kFaceEnrolled, user.faceEnrolled);
    await prefs.setString(_kFaceData, user.faceImage);
    await prefs.setBool(_kIsDoctor, user.isDoctor);
    await prefs.setString(_kUserId, user.uid);
    await prefs.setString(_kLocalSessionUid, user.uid);
  }

  Future<LocalAuthUser?> _persistAuthResponse(
    Map<String, dynamic> body, {
    required String fallbackEmail,
  }) async {
    await UserSessionCache.onUserSessionStarting();
    final user = body['user'] as Map<String, dynamic>? ?? const {};
    final access = body['access']?.toString();
    final refresh = body['refresh']?.toString();
    if (access == null ||
        access.isEmpty ||
        refresh == null ||
        refresh.isEmpty) {
      return null;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccessToken, access);
    await prefs.setString(_kRefreshToken, refresh);
    await prefs.setString(_kUsername, (user['username'] as String?) ?? '');
    final uid = (user['id'] ?? '').toString();
    await prefs.setString(_kUserId, uid);
    await prefs.setString(_kLocalSessionUid, uid);
    await prefs.setString(_kFirstName, (user['first_name'] as String?) ?? '');
    await prefs.setString(_kLastName, (user['last_name'] as String?) ?? '');
    await prefs.setString(
      _kProfession,
      (user['profession'] as String?) ?? 'other',
    );
    await prefs.setString(_kEmail, (user['email'] as String?) ?? fallbackEmail);
    await prefs.setBool(
      _kFaceEnrolled,
      (user['face_enrolled'] as bool?) ?? false,
    );
    await prefs.setString(_kFaceData, (user['face_image'] as String?) ?? '');
    await prefs.setBool(_kIsDoctor, (user['is_doctor'] as bool?) ?? false);
    await prefs.setBool(
      _kIsApprovedDoctor,
      (user['is_approved_doctor'] as bool?) ?? false,
    );

    unawaited(UserSessionCache.onUserSessionReady());

    return LocalAuthUser(
      firstName: (user['first_name'] as String?) ?? '',
      profession: (user['profession'] as String?) ?? 'other',
      email: (user['email'] as String?) ?? fallbackEmail,
      password: '',
      faceImageData: ((user['face_enrolled'] as bool?) ?? false)
          ? ((user['face_image'] as String?) ?? 'enrolled')
          : '',
    );
  }

  Future<void> _persistProfile(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUsername, (user['username'] as String?) ?? '');
    await prefs.setString(_kFirstName, (user['first_name'] as String?) ?? '');
    await prefs.setString(_kLastName, (user['last_name'] as String?) ?? '');
    await prefs.setString(
      _kProfession,
      (user['profession'] as String?) ?? 'other',
    );
    await prefs.setString(_kEmail, (user['email'] as String?) ?? '');
    await prefs.setBool(
      _kFaceEnrolled,
      (user['face_enrolled'] as bool?) ?? false,
    );
    await prefs.setString(_kFaceData, (user['face_image'] as String?) ?? '');
    await prefs.setBool(_kIsDoctor, (user['is_doctor'] as bool?) ?? false);
    await prefs.setBool(
      _kIsApprovedDoctor,
      (user['is_approved_doctor'] as bool?) ?? false,
    );
    final uid = (user['id'] ?? '').toString();
    if (uid.isNotEmpty) {
      await prefs.setString(_kUserId, uid);
      await prefs.setString(_kLocalSessionUid, uid);
    }
  }

  LocalAuthUser _toLocalAuthUser(AppUser user) {
    return LocalAuthUser(
      firstName: user.firstName,
      profession: user.profession,
      email: user.email,
      password: '',
      faceImageData: user.faceEnrolled ? user.faceImage : '',
    );
  }

  AuthProfile _toAuthProfile(AppUser user) {
    return AuthProfile(
      username: user.username,
      firstName: user.firstName,
      lastName: user.lastName,
      email: user.email,
      profession: user.profession,
      faceEnrolled: user.faceEnrolled,
      faceImage: user.faceImage.isEmpty ? null : user.faceImage,
      isDoctor: user.isDoctor,
      isApprovedDoctor: user.isDoctor,
    );
  }

  String _extractErrorMessage(String body) {
    try {
      final parsed = jsonDecode(body);
      if (parsed is Map<String, dynamic>) {
        final message = parsed['message'] ?? parsed['detail'];
        if (message is String && message.isNotEmpty) return message;
        for (final value in parsed.values) {
          if (value is List && value.isNotEmpty) {
            return value.first.toString();
          }
          if (value is String && value.isNotEmpty) {
            return value;
          }
        }
      }
    } catch (_) {}
    return 'Unable to process request. Please try again.';
  }

  Future<String> fetchAppLogo() async {
    try {
      final response = await http.get(
        ApiConfig.uri('/api/public/branding/'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['logo_url'] ?? '';
      }

      return '';
    } catch (e) {
      debugPrint('Error fetching logo: $e');
      return '';
    }
  }
}
