import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main_shell_screen.dart';
import '../../config/api_config.dart';
import '../../models/google_auth_models.dart';
import '../../services/auth_api_exception.dart';
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
  bool _obscurePassword = true;

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
    LocalAuthUser user;
    try {
      user = await _auth.login(email, password);
    } on AuthApiException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _show(e.message);
      return;
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
    final userIdEarly = await _auth.getStoredUserId();
    await ScreenTimeService.instance.persistDevicePermissionGrants(
      userId: userIdEarly,
    );
    if (!await TrackingPermissionsGate.isFullyGranted(userIdEarly)) {
      final trackingOk =
          await TrackingPermissionsGate.runMandatoryAfterAuthenticatedSession(
        context,
        _auth,
      );
      if (!trackingOk) {
        if (!mounted) return;
        setState(() => _loading = false);
        _show('Sign in again to finish setup.');
        return;
      }
    }

    final userId = await _auth.getStoredUserId();
    await ScreenTimeService.instance.setTrackingUser(userId);
    await ScreenTimeService.instance.persistDevicePermissionGrants(userId: userId);

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
      backgroundColor: const Color(0xFFF3F1FB),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),

              // ---------- CENTERED LOGO (same size as Signup) ----------
              const Center(
                child: SizedBox(
                  height: 78,
                  width: 160,
                  child: MindSyncLogo(height: 78, width: 160),
                ),
              ),
              const SizedBox(height: 10),
              const Center(
                child: Text(
                  'The Sanctuary for your Mind',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: Color(0xFF6D6F7A),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ---------- WELCOME HEADER ----------
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Text(
                  'Welcome back',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1F2330),
                    letterSpacing: -0.4,
                    height: 1.15,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Text(
                  'Sign in to continue your journey',
                  style: TextStyle(
                    fontSize: 13.5,
                    color: Color(0xFF6D6F7A),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ---------- ACCOUNT DETAILS HEADER ----------
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 10),
                child: Text(
                  'ACCOUNT DETAILS',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.3,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF6F39E8),
                  ),
                ),
              ),

              // ---------- EMAIL ----------
              _AuthField(
                label: 'EMAIL',
                hint: 'you@example.com',
                icon: Icons.mail_outline_rounded,
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),

              // ---------- PASSWORD ----------
              _AuthField(
                label: 'PASSWORD',
                hint: 'Enter your password',
                icon: Icons.lock_outline_rounded,
                controller: _passwordController,
                obscure: _obscurePassword,
                trailing: IconButton(
                  splashRadius: 20,
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20,
                    color: const Color(0xFF9B9EA9),
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              const SizedBox(height: 6),

              // ---------- REMEMBER ME + FORGOT ----------
              Row(
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () =>
                          setState(() => _rememberMe = !_rememberMe),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 6,
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 22,
                              height: 22,
                              child: Checkbox(
                                value: _rememberMe,
                                onChanged: (v) =>
                                    setState(() => _rememberMe = v ?? false),
                                activeColor: const Color(0xFF6F39E8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                side: const BorderSide(
                                  color: Color(0xFFB8BCC8),
                                  width: 1.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Remember me',
                              style: TextStyle(
                                fontSize: 13.5,
                                color: Color(0xFF5F6270),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
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
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // ---------- LOGIN BUTTON ----------
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _loading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    foregroundColor: Colors.white,
                    backgroundColor: const Color(0xFF6F39E8),
                    disabledBackgroundColor: const Color(0xFFD0C7EE),
                    disabledForegroundColor: Colors.white70,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: Text(
                    _loading ? 'Logging in...' : 'Login',
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // ---------- SIGNUP LINK ----------
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "Don't have an account?",
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF666A79),
                      fontWeight: FontWeight.w500,
                    ),
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
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // ---------- DIVIDER ----------
              Row(
                children: [
                  const Expanded(child: Divider(color: Color(0xFFE0DEEA))),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'OR CONTINUE WITH',
                      style: TextStyle(
                        fontSize: 11,
                        color: const Color(0xFF6F7382),
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                  const Expanded(child: Divider(color: Color(0xFFE0DEEA))),
                ],
              ),
              const SizedBox(height: 14),

              // ---------- GOOGLE ----------
              _SocialButton(
                title: 'Continue with Google',
                background: Colors.white,
                textColor: const Color(0xFF2A2D3A),
                icon: Icons.g_mobiledata_rounded,
                onTap: _loading ? null : _loginWithGoogle,
              ),
              const SizedBox(height: 10),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable widgets
// ---------------------------------------------------------------------------

class _AuthField extends StatelessWidget {
  const _AuthField({
    required this.label,
    required this.hint,
    required this.controller,
    this.icon,
    this.obscure = false,
    this.keyboardType,
    this.trailing,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final IconData? icon;
  final bool obscure;
  final TextInputType? keyboardType;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF6F39E8),
              letterSpacing: 1.1,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          style: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1F2330),
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              color: Color(0xFF9B9EA9),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            prefixIcon: icon != null
                ? Icon(icon, size: 20, color: const Color(0xFF9B9EA9))
                : null,
            suffixIcon: trailing,
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFE7E4F1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFE7E4F1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(
                color: Color(0xFF6F39E8),
                width: 1.6,
              ),
            ),
          ),
        ),
      ],
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
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          height: 54,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE3E4EB)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, color: textColor, size: 26),
                const SizedBox(width: 8),
              ],
              Text(
                title,
                style: TextStyle(
                  color: textColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}