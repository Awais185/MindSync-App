import 'package:flutter_test/flutter_test.dart';
import 'package:mindsync/services/local_auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalAuthService', () {
    test('instance is a singleton', () {
      expect(identical(LocalAuthService.instance, LocalAuthService()), isTrue);
    });

    test('getAccessToken reads stored JWT', () async {
      SharedPreferences.setMockInitialValues({
        'auth.accessToken': 'test-access-token',
      });
      final token = await LocalAuthService.instance.getAccessToken();
      expect(token, 'test-access-token');
    });

    test('restoreSessionIfPossible returns cached profile when /me is unreachable',
        () async {
      SharedPreferences.setMockInitialValues({
        'auth.accessToken': 'offline-token',
        'auth.email': 'user@example.com',
        'auth.firstName': 'Test',
        'auth.username': 'testuser',
        'auth.profession': 'student',
        'auth.faceEnrolled': false,
      });

      final profile = await LocalAuthService.instance.restoreSessionIfPossible();
      expect(profile, isNotNull);
      expect(profile!.email, 'user@example.com');
      expect(profile.firstName, 'Test');
    });

    test('tryRefreshAccessToken returns false without refresh token', () async {
      SharedPreferences.setMockInitialValues({
        'auth.accessToken': 'only-access',
      });
      final ok = await LocalAuthService.instance.tryRefreshAccessToken();
      expect(ok, isFalse);
    });
  });
}
