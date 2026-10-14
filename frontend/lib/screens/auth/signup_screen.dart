import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:typed_data';
import '../main_shell_screen.dart';
import '../../models/google_auth_models.dart';
import '../../services/local_auth_service.dart';
import '../../services/screen_time_service.dart';
import '../../services/tracking_permissions_gate.dart';
import '../../widgets/mindsync_logo.dart';
import 'face_capture_screen.dart';
import 'login_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key, this.googlePrefill});

  /// When set (e.g. redirected from Google login), pre-fills signup fields.
  final GoogleSignupPrefill? googlePrefill;

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _firstNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _professionController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _auth = LocalAuthService();
  bool _agreed = false;
  bool _loading = false;
  String? _facePath;
  Uint8List? _faceBytes;

  @override
  void initState() {
    super.initState();
    final prefill = widget.googlePrefill;
    if (prefill != null) {
      _firstNameController.text = prefill.firstName.isNotEmpty
          ? prefill.firstName
          : prefill.displayName.split(' ').first;
      _usernameController.text = prefill.email.split('@').first;
      _emailController.text = prefill.email;
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _usernameController.dispose();
    _professionController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _captureFace() async {
    final image = await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const FaceCaptureScreen()));
    if (image == null) return;
    final bytes = await image.readAsBytes();
    final saved = await _auth.persistFaceImageBytes(bytes);
    if (image == null) return;
    if (!mounted) return;
    setState(() {
      _facePath = saved;
      _faceBytes = bytes;
    });
  }

  Future<void> _createAccount() async {
    final firstName = _firstNameController.text.trim();
    final username = _usernameController.text.trim();
    final profession = _professionController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmPasswordController.text;

    if (firstName.isEmpty ||
        username.isEmpty ||
        profession.isEmpty ||
        email.isEmpty ||
        password.isEmpty) {
      _show('Please fill all required fields.');
      return;
    }
    if (password != confirm) {
      _show('Password and Confirm Password do not match.');
      return;
    }
    if (_facePath == null) {
      _show('Please capture your face photo first.');
      return;
    }
    if (!_agreed) {
      _show('Please agree to the Terms of Sanctuary.');
      return;
    }

    setState(() => _loading = true);
    LocalAuthUser? loggedInUser;
    try {
      loggedInUser = await _auth.signup(
        firstName: firstName,
        username: username,
        profession: profession,
        email: email,
        password: password,
        faceImageBytes: _faceBytes,
      );
    } catch (e) {
      if (!context.mounted) return;
      setState(() => _loading = false);
      _show(e.toString().replaceFirst('Exception: ', ''));
      return;
    }

    if (!context.mounted) return;
    if (!await TrackingPermissionsGate.isFullyGranted()) {
      final trackingOk =
          await TrackingPermissionsGate.runMandatoryAfterAuthenticatedSession(
        context,
        _auth,
      );
      if (!trackingOk) {
        if (!context.mounted) return;
        setState(() => _loading = false);
        _show('Permissions are required to use MindSync.');
        return;
      }
    }

    final userId = await _auth.getStoredUserId();
    await ScreenTimeService.instance.setTrackingUser(userId);

    final profile = await _auth.fetchCurrentUserProfile();
    ScreenTimeService.instance.setFaceVerified(profile?.faceEnrolled ?? false);
    ScreenTimeService.instance.setFaceMatchPercent(50);
    if (!kIsWeb && userId != null && userId.isNotEmpty) {
      try {
        await ScreenTimeService.instance.resetUsageBaselinesForNewUser(userId);
      } catch (_) {}
    }

    await TrackingPermissionsGate.startScreenTimeIfPermitted();
    if (!context.mounted) return;
    _show('Welcome! Tracking runs in the background when fully set up.');
    setState(() => _loading = false);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainShellScreen()),
    );
  }

  Future<void> _continueWithGoogle() async {
    if (_loading) return;
    setState(() => _loading = true);
    LocalAuthUser user;
    try {
      user = await _auth.signupWithGoogle();
    } on GoogleAuthException catch (e) {
      if (!context.mounted) return;
      setState(() => _loading = false);
      if (e.failure == GoogleAuthFailure.cancelled) return;
      _show(e.message ?? e.toString());
      return;
    } catch (e) {
      if (!context.mounted) return;
      setState(() => _loading = false);
      _show(e.toString().replaceFirst('Exception: ', ''));
      return;
    }

    if (!context.mounted) return;
    await _finishGoogleSignup(user);
  }

  Future<void> _finishGoogleSignup(LocalAuthUser user) async {
    if (!await TrackingPermissionsGate.isFullyGranted()) {
      final trackingOk =
          await TrackingPermissionsGate.runMandatoryAfterAuthenticatedSession(
        context,
        _auth,
      );
      if (!trackingOk) {
        if (!context.mounted) return;
        setState(() => _loading = false);
        _show('Permissions are required to use MindSync.');
        return;
      }
    }

    final userId = await _auth.getStoredUserId();
    await ScreenTimeService.instance.setTrackingUser(userId);

    final profile = await _auth.fetchCurrentUserProfile();
    ScreenTimeService.instance.setFaceVerified(profile?.faceEnrolled ?? false);
    ScreenTimeService.instance.setFaceMatchPercent(50);
    if (!kIsWeb && userId != null && userId.isNotEmpty) {
      try {
        await ScreenTimeService.instance.resetUsageBaselinesForNewUser(userId);
      } catch (_) {}
    }

    await TrackingPermissionsGate.startScreenTimeIfPermitted();
    if (!context.mounted) return;
    final enrollMsg = !(profile?.faceEnrolled ?? false)
        ? 'Welcome! Complete Face Scan from More to enroll your face for full tracking.'
        : 'Welcome to MindSync!';
    _show(enrollMsg);
    setState(() => _loading = false);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainShellScreen()),
    );
  }

  void _show(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6FA),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(
                height: 83,
                width: 167,
                child: MindSyncLogo(height: 83, width: 167),
              ),
              const SizedBox(height: 6),
              const Text(
                'Begin your journey to a luminous mind.',
                style: TextStyle(color: Color(0xFF6D6F7A), fontSize: 15),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: const Color(0xFFDACEF6),
                      backgroundImage: _faceBytes != null
                          ? MemoryImage(_faceBytes!)
                          : null,
                      child: _faceBytes == null
                          ? const Icon(
                              Icons.person,
                              size: 34,
                              color: Color(0xFF6F39E8),
                            )
                          : null,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'FACE ENROLLMENT',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    const Text(
                      'For secure, hands-free entry',
                      style: TextStyle(fontSize: 11, color: Color(0xFF8F919B)),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F2F7),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.add_a_photo,
                            size: 16,
                            color: Color(0xFF6F39E8),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _facePath == null
                                  ? 'Capture Profile Photo'
                                  : 'Profile Photo Captured',
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF5F6270),
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _captureFace,
                            child: Text(
                              _facePath == null ? 'Capture' : 'Captured',
                              style: TextStyle(
                                color: Color(0xFF6F39E8),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    _SignField(
                      label: 'FIRST NAME',
                      hint: 'First Name',
                      controller: _firstNameController,
                    ),
                    const SizedBox(height: 9),
                    _SignField(
                      label: 'USERNAME',
                      hint: 'Username',
                      controller: _usernameController,
                    ),
                    const SizedBox(height: 9),
                    _SignField(
                      label: 'PROFESSION',
                      hint: 'Profession',
                      controller: _professionController,
                    ),
                    const SizedBox(height: 9),
                    _SignField(
                      label: 'EMAIL',
                      hint: 'Email',
                      controller: _emailController,
                    ),
                    const SizedBox(height: 9),
                    _SignField(
                      label: 'PASSWORD',
                      hint: 'Password',
                      controller: _passwordController,
                      obscure: true,
                    ),
                    const SizedBox(height: 9),
                    _SignField(
                      label: '',
                      hint: 'Confirm Password',
                      controller: _confirmPasswordController,
                      obscure: true,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: Checkbox(
                            value: _agreed,
                            onChanged: (v) =>
                                setState(() => _agreed = v ?? false),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'I agree to the Terms of Sanctuary',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF6B6D79),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _createAccount,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6F39E8),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                        child: Text(
                          _loading ? 'Creating...' : 'Create Account',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'OR CONTINUE WITH',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6F7382),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _SocialButton(
                      title: 'Continue with Google',
                      icon: Icons.g_mobiledata_rounded,
                      onTap: _continueWithGoogle,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Already have an account?',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF666A79),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                builder: (_) => const LoginScreen(),
                              ),
                            );
                          },
                          child: const Text(
                            'Login',
                            style: TextStyle(
                              color: Color(0xFF6F39E8),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignField extends StatelessWidget {
  const _SignField({
    required this.label,
    required this.hint,
    required this.controller,
    this.obscure = false,
  });
  final String label;
  final String hint;
  final TextEditingController controller;
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF6F39E8),
                letterSpacing: 1.1,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        TextField(
          controller: controller,
          obscureText: obscure,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: const Color(0xFFF1F2F7),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({required this.title, this.icon, this.onTap});

  final String title;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(25),
        child: Container(
          width: double.infinity,
          height: 50,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: const Color(0xFFE3E4EB)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 24, color: const Color(0xFF2A2D3A)),
                const SizedBox(width: 10),
              ],
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2A2D3A),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
