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
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _auth = LocalAuthService();

  String? _profession;
  String? _ageRange;
  bool _agreed = false;
  bool _loading = false;
  String? _facePath;
  Uint8List? _faceBytes;

  static const _professionOptions = <String>[
    'Children',
    'Student',
    'Working Professional',
  ];

  static const _ageOptions = <String>[
    '4 - 15 years',
    '16 - 30 years',
    '30+ years',
  ];

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

  // Kept as a getter so dispose() still works without a declared field.
  TextEditingController get _professionController => TextEditingController();

  Future<void> _captureFace() async {
    final image = await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const FaceCaptureScreen()));
    if (image == null) return;
    final bytes = await image.readAsBytes();
    final saved = await _auth.persistFaceImageBytes(bytes);
    if (!mounted) return;
    setState(() {
      _facePath = saved;
      _faceBytes = bytes;
    });
  }

  Future<void> _createAccount() async {
    final firstName = _firstNameController.text.trim();
    final username = _usernameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmPasswordController.text;

    if (firstName.isEmpty ||
        username.isEmpty ||
        email.isEmpty ||
        password.isEmpty) {
      _show('Please fill all required fields.');
      return;
    }
    if (_profession == null) {
      _show('Please select your profession.');
      return;
    }
    if (_ageRange == null) {
      _show('Please select your age range.');
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
    try {
      await _auth.signup(
        firstName: firstName,
        username: username,
        profession: _profession!,
        ageRange: _ageRange!,
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
    final userId = await _auth.getStoredUserId();
    await ScreenTimeService.instance.persistDevicePermissionGrants(userId: userId);
    if (!await TrackingPermissionsGate.isFullyGranted(userId)) {
      final trackingOk =
          await TrackingPermissionsGate.runMandatoryAfterAuthenticatedSession(
        context,
        _auth,
      );
      if (!trackingOk) {
        if (!context.mounted) return;
        setState(() => _loading = false);
        _show('Sign in again to finish setup.');
        return;
      }
    }

    await ScreenTimeService.instance.setTrackingUser(userId);

    final profile = await _auth.fetchCurrentUserProfile();
    ScreenTimeService.instance.setFaceVerified(profile?.faceEnrolled ?? false);
    ScreenTimeService.instance.setFaceMatchPercent(50);
    if (!kIsWeb && userId != null && userId.isNotEmpty) {
      try {
        await ScreenTimeService.instance.resetUsageBaselinesForNewUser(userId);
      } catch (_) {}
    }

    await ScreenTimeService.instance.persistDevicePermissionGrants(userId: userId);
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
    final userId = await _auth.getStoredUserId();
    await ScreenTimeService.instance.persistDevicePermissionGrants(userId: userId);
    if (!await TrackingPermissionsGate.isFullyGranted(userId)) {
      final trackingOk =
          await TrackingPermissionsGate.runMandatoryAfterAuthenticatedSession(
        context,
        _auth,
      );
      if (!trackingOk) {
        if (!context.mounted) return;
        setState(() => _loading = false);
        _show('Sign in again to finish setup.');
        return;
      }
    }

    await ScreenTimeService.instance.setTrackingUser(userId);

    final profile = await _auth.fetchCurrentUserProfile();
    ScreenTimeService.instance.setFaceVerified(profile?.faceEnrolled ?? false);
    ScreenTimeService.instance.setFaceMatchPercent(50);
    if (!kIsWeb && userId != null && userId.isNotEmpty) {
      try {
        await ScreenTimeService.instance.resetUsageBaselinesForNewUser(userId);
      } catch (_) {}
    }

    await ScreenTimeService.instance.persistDevicePermissionGrants(userId: userId);
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
      backgroundColor: const Color(0xFFF3F1FB),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ---------- CENTERED LOGO ----------
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
                  'Begin your journey to a luminous mind',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF6D6F7A),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ---------- FACE ENROLLMENT CARD ----------
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: _faceBytes != null
                                  ? [
                                      const Color(0xFF6F39E8),
                                      const Color(0xFF14B8A6),
                                    ]
                                  : [
                                      const Color(0xFFE0D8F7),
                                      const Color(0xFFE0D8F7),
                                    ],
                            ),
                          ),
                          child: CircleAvatar(
                            radius: 36,
                            backgroundColor: const Color(0xFFF1EEFB),
                            backgroundImage: _faceBytes != null
                                ? MemoryImage(_faceBytes!)
                                : null,
                            child: _faceBytes == null
                                ? const Icon(
                                    Icons.face_retouching_natural,
                                    size: 36,
                                    color: Color(0xFF6F39E8),
                                  )
                                : null,
                          ),
                        ),
                        if (_faceBytes != null)
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Color(0xFF22C55E),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Face Enrollment',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: Color(0xFF1F2330),
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Required for secure, hands-free entry',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF8F919B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: OutlinedButton.icon(
                        onPressed: _captureFace,
                        icon: Icon(
                          _facePath == null
                              ? Icons.add_a_photo_outlined
                              : Icons.refresh_rounded,
                          size: 18,
                        ),
                        label: Text(
                          _facePath == null
                              ? 'Capture Profile Photo'
                              : 'Recapture Photo',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF6F39E8),
                          side: const BorderSide(
                            color: Color(0xFFD6CCF4),
                            width: 1.4,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 22),

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

              // ---------- FORM FIELDS ----------
              _SignField(
                label: 'FIRST NAME',
                hint: 'Enter your first name',
                icon: Icons.person_outline_rounded,
                controller: _firstNameController,
              ),
              const SizedBox(height: 12),
              _SignField(
                label: 'USERNAME',
                hint: 'Choose a username',
                icon: Icons.alternate_email_rounded,
                controller: _usernameController,
              ),
              const SizedBox(height: 12),
              _SignField(
                label: 'EMAIL',
                hint: 'you@example.com',
                icon: Icons.mail_outline_rounded,
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),

              // ---------- PROFESSION DROPDOWN ----------
              _DropdownField(
                label: 'PROFESSION',
                hint: 'Select profession',
                icon: Icons.work_outline_rounded,
                value: _profession,
                options: _professionOptions,
                onChanged: (v) => setState(() => _profession = v),
              ),
              const SizedBox(height: 12),

              // ---------- AGE DROPDOWN ----------
              _DropdownField(
                label: 'AGE',
                hint: 'Select age range',
                icon: Icons.cake_outlined,
                value: _ageRange,
                options: _ageOptions,
                onChanged: (v) => setState(() => _ageRange = v),
              ),
              const SizedBox(height: 12),

              _SignField(
                label: 'PASSWORD',
                hint: 'Create a strong password',
                icon: Icons.lock_outline_rounded,
                controller: _passwordController,
                obscure: true,
              ),
              const SizedBox(height: 12),
              _SignField(
                label: 'CONFIRM PASSWORD',
                hint: 'Re-enter your password',
                icon: Icons.lock_person_outlined,
                controller: _confirmPasswordController,
                obscure: true,
              ),
              const SizedBox(height: 16),

              // ---------- TERMS RADIO ----------
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => setState(() => _agreed = !_agreed),
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Radio<bool>(
                          value: true,
                          groupValue: _agreed,
                          onChanged: (v) =>
                              setState(() => _agreed = v ?? false),
                          activeColor: const Color(0xFF6F39E8),
                        ),
                        const Expanded(
                          child: Text(
                            'I agree to the Terms of Sanctuary and Privacy Policy.',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Color(0xFF5F6270),
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ---------- CREATE ACCOUNT ----------
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: (_loading || !_agreed) ? null : _createAccount,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6F39E8),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFD0C7EE),
                    disabledForegroundColor: Colors.white70,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: Text(
                    _loading ? 'Creating...' : 'Create Account',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15.5,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 22),

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

              // ---------- GOOGLE SIGNUP ----------
              _SocialButton(
                title: 'Continue with Google',
                icon: Icons.g_mobiledata_rounded,
                onTap: _loading ? null : _continueWithGoogle,
              ),

              const SizedBox(height: 18),

              // ---------- LOGIN LINK ----------
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
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                ],
              ),
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

class _SignField extends StatelessWidget {
  const _SignField({
    required this.label,
    required this.hint,
    required this.controller,
    this.icon,
    this.obscure = false,
    this.keyboardType,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final IconData? icon;
  final bool obscure;
  final TextInputType? keyboardType;

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

class _DropdownField extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.hint,
    required this.icon,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final IconData icon;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

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
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE7E4F1)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              hint: Row(
                children: [
                  Icon(icon, size: 20, color: const Color(0xFF9B9EA9)),
                  const SizedBox(width: 12),
                  Text(
                    hint,
                    style: const TextStyle(
                      color: Color(0xFF9B9EA9),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              icon: const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: Color(0xFF6F39E8),
                ),
              ),
              borderRadius: BorderRadius.circular(16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              items: options
                  .map(
                    (o) => DropdownMenuItem<String>(
                      value: o,
                      child: Row(
                        children: [
                          Icon(icon, size: 20, color: const Color(0xFF6F39E8)),
                          const SizedBox(width: 12),
                          Text(
                            o,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1F2330),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              onChanged: onChanged,
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
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          height: 54,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE3E4EB)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 28, color: const Color(0xFF2A2D3A)),
                const SizedBox(width: 6),
              ],
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
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