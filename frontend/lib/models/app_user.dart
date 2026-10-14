/// Canonical user record synced across Firebase Auth, Firestore, and SQLite.
class AppUser {
  const AppUser({
    required this.uid,
    required this.name,
    required this.email,
    required this.createdAt,
    this.firstName = '',
    this.lastName = '',
    this.username = '',
    this.profession = 'other',
    this.faceImage = '',
    this.faceEnrolled = false,
    this.isDoctor = false,
  });

  final String uid;
  final String name;
  final String email;
  final DateTime createdAt;
  final String firstName;
  final String lastName;
  final String username;
  final String profession;
  final String faceImage;
  final bool faceEnrolled;
  final bool isDoctor;

  String get displayName {
    if (firstName.trim().isNotEmpty) return firstName.trim();
    if (name.trim().isNotEmpty) return name.trim();
    if (username.trim().isNotEmpty) return username.trim();
    if (email.trim().isNotEmpty) return email.trim().split('@').first;
    return 'User';
  }

  String get fullName {
    final first = firstName.trim().isNotEmpty ? firstName.trim() : name.trim();
    final last = lastName.trim();
    if (first.isEmpty && last.isEmpty) return displayName;
    return '$first $last'.trim();
  }

  AppUser copyWith({
    String? uid,
    String? name,
    String? email,
    DateTime? createdAt,
    String? firstName,
    String? lastName,
    String? username,
    String? profession,
    String? faceImage,
    bool? faceEnrolled,
    bool? isDoctor,
  }) {
    return AppUser(
      uid: uid ?? this.uid,
      name: name ?? this.name,
      email: email ?? this.email,
      createdAt: createdAt ?? this.createdAt,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      username: username ?? this.username,
      profession: profession ?? this.profession,
      faceImage: faceImage ?? this.faceImage,
      faceEnrolled: faceEnrolled ?? this.faceEnrolled,
      isDoctor: isDoctor ?? this.isDoctor,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      'email': email,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'firstName': firstName,
      'lastName': lastName,
      'username': username,
      'profession': profession,
      'faceImage': faceImage,
      'faceEnrolled': faceEnrolled ? 1 : 0,
      'isDoctor': isDoctor ? 1 : 0,
    };
  }

  Map<String, dynamic> toFirestore() {
    return {
      'uid': uid,
      'name': name,
      'email': email,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'firstName': firstName,
      'lastName': lastName,
      'username': username,
      'profession': profession,
      'faceImage': faceImage,
      'faceEnrolled': faceEnrolled,
      'isDoctor': isDoctor,
    };
  }

  factory AppUser.fromMap(Map<String, dynamic> map) {
    final createdRaw = map['createdAt'];
    DateTime createdAt;
    if (createdRaw is String) {
      createdAt = DateTime.tryParse(createdRaw) ?? DateTime.now().toUtc();
    } else {
      createdAt = DateTime.now().toUtc();
    }

    final faceEnrolledRaw = map['faceEnrolled'];
    final isDoctorRaw = map['isDoctor'];

    return AppUser(
      uid: (map['uid'] as String?) ?? '',
      name: (map['name'] as String?) ?? '',
      email: (map['email'] as String?) ?? '',
      createdAt: createdAt,
      firstName: (map['firstName'] as String?) ?? '',
      lastName: (map['lastName'] as String?) ?? '',
      username: (map['username'] as String?) ?? '',
      profession: (map['profession'] as String?) ?? 'other',
      faceImage: (map['faceImage'] as String?) ?? '',
      faceEnrolled: faceEnrolledRaw is bool
          ? faceEnrolledRaw
          : (faceEnrolledRaw == 1 || faceEnrolledRaw == true),
      isDoctor: isDoctorRaw is bool
          ? isDoctorRaw
          : (isDoctorRaw == 1 || isDoctorRaw == true),
    );
  }

  /// Firestore is primary; [local] fills gaps when cloud fields are empty.
  static AppUser merge({required AppUser? cloud, required AppUser? local}) {
    if (cloud == null && local == null) {
      throw ArgumentError('At least one user source is required.');
    }
    if (cloud == null) return local!;
    if (local == null) return cloud;

    String pick(String cloudValue, String localValue) {
      final c = cloudValue.trim();
      if (c.isNotEmpty) return c;
      return localValue.trim();
    }

    return AppUser(
      uid: pick(cloud.uid, local.uid),
      name: pick(cloud.name, local.name),
      email: pick(cloud.email, local.email),
      createdAt: cloud.createdAt.isAfter(local.createdAt)
          ? cloud.createdAt
          : local.createdAt,
      firstName: pick(cloud.firstName, local.firstName),
      lastName: pick(cloud.lastName, local.lastName),
      username: pick(cloud.username, local.username),
      profession: pick(cloud.profession, local.profession),
      faceImage: pick(cloud.faceImage, local.faceImage),
      faceEnrolled: cloud.faceEnrolled || local.faceEnrolled,
      isDoctor: cloud.isDoctor || local.isDoctor,
    );
  }
}
