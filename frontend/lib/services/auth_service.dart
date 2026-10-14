import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config/google_auth_config.dart';

/// Firebase Authentication wrapper (email/password + Google).
class AuthService {
  AuthService({FirebaseAuth? firebaseAuth, GoogleSignIn? googleSignIn})
      : _auth = firebaseAuth ?? FirebaseAuth.instance,
        _googleSignIn = googleSignIn ?? _defaultGoogleSignIn;

  static const String _googleWebClientId = GoogleAuthConfig.webClientId;

  static final GoogleSignIn _defaultGoogleSignIn = GoogleSignIn(
    scopes: const <String>['email', 'profile'],
    clientId: kIsWeb && _googleWebClientId.trim().isNotEmpty
        ? _googleWebClientId.trim()
        : null,
    serverClientId: !kIsWeb && _googleWebClientId.trim().isNotEmpty
        ? _googleWebClientId.trim()
        : null,
  );

  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;

  User? get currentUser => _auth.currentUser;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  Future<UserCredential> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      return await _auth.createUserWithEmailAndPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw Exception(_messageFromFirebaseAuth(e));
    }
  }

  /// Sign-up / cloud provisioning only. App login uses local SQLite, not this method.
  @Deprecated('Use UserRepository.signIn for login (local DB only).')
  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw Exception(_messageFromFirebaseAuth(e));
    }
  }

  Future<UserCredential> signInWithGoogle() async {
    try {
      await _googleSignIn.signOut();
      final account = await _googleSignIn.signIn();
      if (account == null) {
        throw Exception('Google sign-in was cancelled.');
      }

      final googleAuth = await account.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      return await _auth.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      throw Exception(_messageFromFirebaseAuth(e));
    } on Exception {
      rethrow;
    } catch (_) {
      throw Exception('Unable to sign in with Google right now.');
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim().toLowerCase());
    } on FirebaseAuthException catch (e) {
      throw Exception(_messageFromFirebaseAuth(e));
    }
  }

  Future<String?> getIdToken({bool forceRefresh = false}) async {
    final user = _auth.currentUser;
    if (user == null) return null;
    try {
      return await user.getIdToken(forceRefresh);
    } on Exception {
      return null;
    }
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } on Object {
      // Web may lack client ID; still clear Firebase session.
    }
    await _auth.signOut();
  }

  String _messageFromFirebaseAuth(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'An account already exists for this email.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Invalid email or password.';
      case 'weak-password':
        return 'Password is too weak. Use at least 6 characters.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait and try again.';
      default:
        return e.message ?? 'Authentication failed. Please try again.';
    }
  }
}
