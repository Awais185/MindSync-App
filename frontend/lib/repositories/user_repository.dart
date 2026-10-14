// Auth flows use [LocalAuthService] (Django API + local SQLite).
// Firebase services remain in lib/services/ for future use but are not wired here.

/// Reserved for future hybrid sync. Authentication is handled by [LocalAuthService].
class UserRepository {
  const UserRepository();
}
