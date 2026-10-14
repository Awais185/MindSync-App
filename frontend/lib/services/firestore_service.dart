import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/app_user.dart';

/// Cloud Firestore access for user profiles (primary source).
class FirestoreService {
  FirestoreService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  /// Writes user profile to `users/{uid}` (Firestore console collection).
  Future<void> saveUser(AppUser user) async {
    final payload = _toFirestorePayload(user);
    try {
      await _users.doc(user.uid).set(payload, SetOptions(merge: true));
      debugPrint('FirestoreService: saved user ${user.uid}');
    } on FirebaseException catch (e) {
      debugPrint(
        'FirestoreService: save failed (${e.code}) ${e.message}',
      );
      rethrow;
    }
  }

  Future<AppUser?> getUser(String uid) async {
    try {
      final doc = await _users.doc(uid).get();
      if (!doc.exists || doc.data() == null) return null;
      return AppUser.fromMap(doc.data()!);
    } on FirebaseException catch (e) {
      if (_isOfflineError(e)) return null;
      debugPrint('FirestoreService: get failed (${e.code})');
      rethrow;
    }
  }

  Future<void> updateUser(AppUser user) => saveUser(user);

  Map<String, dynamic> _toFirestorePayload(AppUser user) {
    final data = user.toFirestore();
    // Firestore doc limit is 1 MiB — keep large face blobs local-only.
    final face = data['faceImage'] as String? ?? '';
    if (face.length > 700000) {
      data['faceImage'] = '';
      data['faceEnrolled'] = user.faceEnrolled;
      data['faceImageStoredLocally'] = true;
    }
    data['updatedAt'] = DateTime.now().toUtc().toIso8601String();
    return data;
  }

  bool _isOfflineError(FirebaseException e) {
    return e.code == 'unavailable' ||
        e.code == 'deadline-exceeded' ||
        e.message?.toLowerCase().contains('offline') == true;
  }
}
