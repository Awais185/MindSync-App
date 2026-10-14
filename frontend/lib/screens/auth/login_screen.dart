import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main_shell_screen.dart';
import '../../config/api_config.dart';
import '../../models/google_auth_models.dart';
import '../../services/local_auth_service.dart';
import '../../services/screen_time_service.dart';
import '../../services/tracking_permissions_gate.dart';
import '../../widgets/mindsync_logo.dart';
import 'forgot_password_screen.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _kRememberMe = 'auth.rememberMe';
  static const _kRememberedEmail = 'auth.rememberedEmail';
  static const _kRememberedPassword = 'auth.rememberedPassword';
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _auth = LocalAuthService();
  bool _loading = false;
  bool _rememberMe = false;

  @override
  void initState() {
    super.initState();
    _loadRememberedCredentials();
  }

  Future<void> _loadRememberedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final remember = prefs.getBool(_kRememberMe) ?? false;
    if (!remember) return;
    _emailController.text = prefs.getString(_kRememberedEmail) ?? '';
    _passwordController.text = prefs.getString(_kRememberedPassword) ?? '';
    if (!mounted) return;
    setState(() => _rememberMe = true);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      _show('Please enter email and password.');
      return;
    }
    setState(() => _loading = true);
    LocalAuthUser? user;
    try {
      user = await _auth.login(email, password);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      final msg = e.toString().replaceFirst('Exception: ', '');
      _show(
        msg.contains('Cannot reach MindSync server')
            ? '$msg\n\nServer: ${ApiConfig.baseUrl}'
            : msg,
      );
      return;
    }
    if (!mounted) return;
    if (user == null) {
      setState(() => _loading = false);
      _show(
        'Invalid email or password. Use the same email/username as in the '
        'MindSync database, with the server running.',
      );
      return;
    }

    await _persistRememberedCredentials(email: email, password: password);
    await _finishLogin(user);
  }

  Future<void> _loginWithGoogle() async {
    if (_loading) return;
    setState(() => _loading = true);
    LocalAuthUser user;
    try {
      user = await _auth.loginWithGoogle();
    } on GoogleAuthException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (e.failure == GoogleAuthFailure.cancelled) return;
      if (e.failure == GoogleAuthFailure.userNotFound && e.prefill != null) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SignupScreen(googlePrefill: e.prefill),
          ),
        );
        _show('No account found. Complete signup with your Google profile.');
        return;
      }
      _show(e.message ?? e.toString());
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _show(e.toString().replaceFirst('Exception: ', ''));
      return;
    }

    if (!mounted) return;
    await _finishLogin(user);
  }

  Future<void> _persistRememberedCredentials({
    required String email,
    required String password,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kRememberMe, _rememberMe);
    if (_rememberMe) {
      await prefs.setString(_kRememberedEmail, email);
      await prefs.setString(_kRememberedPassword, password);
    } else {
      await prefs.remove(_kRememberedEmail);
      await prefs.remove(_kRememberedPassword);
    }
  }

  Future<void> _finishLogin(LocalAuthUser user) async {
    if (!context.mounted) return;
    if (!await TrackingPermissionsGate.isFullyGranted()) {
      final trackingOk =
          await TrackingPermissionsGate.runMandatoryAfterAuthenticatedSession(
        context,
        _auth,
      );
      if (!trackingOk) {
        if (!mounted) return;
        setState(() => _loading = false);
        _show('Permissions are required to use MindSync.');
        return;
      }
    }

    final userId = await _auth.getStoredUserId();
    await ScreenTimeService.instance.setTrackingUser(userId);

    final profile = await _auth.fetchCurrentUserProfile();
    final enrolled =
        (profile?.faceEnrolled ?? false) || user.faceImageData.isNotEmpty;
    ScreenTimeService.instance.setFaceVerified(enrolled);
    ScreenTimeService.instance.setFaceMatchPercent(50);
    await TrackingPermissionsGate.startScreenTimeIfPermitted();
    if (mounted && !enrolled) {
      _show(
        'Complete Face Scan from More to enroll your face for full tracking.',
      );
    }
    if (!mounted) return;
    setState(() => _loading = false);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainShellScreen()),
    );
  }

  void _show(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6FA),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
          child: Column(
            children: [
              const SizedBox(height: 12),
              const SizedBox(
                height: 93,
                width: 167,
                child: MindSyncLogo(height: 93, width: 167),
              ),
              const SizedBox(height: 6),
              const Text(
                'The Sanctuary for your Mind',
                style: TextStyle(fontSize: 17, color: Color(0xFF7A7C89)),
              ),
              const SizedBox(height: 22),
              _AuthField(hint: 'Email Address', controller: _emailController),
              const SizedBox(height: 14),
              _AuthField(
                hint: 'Password',
                controller: _passwordController,
                obscure: true,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: Checkbox(
                      value: _rememberMe,
                      onChanged: (v) =>
                          setState(() => _rememberMe = v ?? false),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('Remember me', style: TextStyle(fontSize: 14.5)),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ForgotPasswordScreen(),
                        ),
                      );
                    },
                    child: const Text(
                      'Forgot password?',
                      style: TextStyle(
                        color: Color(0xFF6F39E8),
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton(
                  onPressed: _loading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    elevation: 8,
                    shadowColor: const Color(0x4D6F39E8),
                    foregroundColor: Colors.white,
                    backgroundColor: const Color(0xFF6F39E8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: Text(
                    _loading ? 'Logging in...' : 'Login',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "Don't have an account?",
                    style: TextStyle(fontSize: 13, color: Color(0xFF727583)),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SignupScreen()),
                      );
                    },
                    child: const Text(
                      'Create account',
                      style: TextStyle(
                        color: Color(0xFF6F39E8),
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Row(
                children: [
                  Expanded(child: Divider(color: Color(0xFFDCDEE4))),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'OR CONTINUE WITH',
                      style: TextStyle(color: Color(0xFF9D9FAA), fontSize: 12),
                    ),
                  ),
                  Expanded(child: Divider(color: Color(0xFFDCDEE4))),
                ],
              ),
              const SizedBox(height: 16),
              _SocialButton(
                title: 'Continue with Google',
                background: Colors.white,
                textColor: const Color(0xFF2A2D3A),
                icon: Icons.g_mobiledata_rounded,
                onTap: _loginWithGoogle,
              ),
              const SizedBox(height: 12),
              _SocialButton(
                title: 'Apple',
                background: const Color(0xFF131923),
                textColor: Colors.white,
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthField extends StatelessWidget {
  const _AuthField({
    required this.hint,
    required this.controller,
    this.obscure = false,
  });
  final String hint;
  final TextEditingController controller;
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF9093A1), fontSize: 15),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
        filled: true,
        fillColor: const Color(0xFFF0F2F6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.title,
    required this.background,
    required this.textColor,
    this.icon,
    this.onTap,
  });

  final String title;
  final Color background;
  final Color textColor;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(27),
        child: Container(
          width: double.infinity,
          height: 54,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(27),
            border: Border.all(color: const Color(0xFFE4E5EC)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, color: textColor, size: 24),
                const SizedBox(width: 10),
              ],
              Text(
                title,
                style: TextStyle(
                  color: textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
