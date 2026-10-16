import 'package:flutter/material.dart';
import '../../services/auth_api_exception.dart';
import '../../services/local_auth_service.dart';
import '../../widgets/mindsync_logo.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _auth = LocalAuthService();
  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final fullName = _nameController.text.trim();
    final email = _emailController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmPasswordController.text;

    if (fullName.isEmpty ||
        email.isEmpty ||
        username.isEmpty ||
        password.isEmpty ||
        confirm.isEmpty) {
      _show('Please fill in all fields.');
      return;
    }
    if (password.length < 8) {
      _show('New password must be at least 8 characters.');
      return;
    }
    if (password != confirm) {
      _show('New password and confirm password do not match.');
      return;
    }

    setState(() => _loading = true);
    try {
      await _auth.resetPasswordWithIdentity(
        email: email,
        username: username,
        fullName: fullName,
        newPassword: password,
        confirmPassword: confirm,
      );
      if (!mounted) return;
      setState(() => _loading = false);
      _show('Password updated. You can log in with your new password.');
      Navigator.of(context).pop();
    } on AuthApiException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _show(e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _show(e.toString().replaceFirst('Exception: ', ''));
    }
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
              // ---------- BACK BUTTON ----------
              Align(
                alignment: Alignment.centerLeft,
                child: Material(
                  color: Colors.white,
                  shape: const CircleBorder(),
                  elevation: 0,
                  child: InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    customBorder: const CircleBorder(),
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(
                        Icons.arrow_back_rounded,
                        size: 20,
                        color: Color(0xFF1F2330),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // ---------- CENTERED LOGO (same size as Login/Signup) ----------
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
                  'Reset your password',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: Color(0xFF6D6F7A),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ---------- HEADER ----------
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Text(
                  'Forgot password?',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1F2330),
                    letterSpacing: -0.4,
                    height: 1.15,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Text(
                  'Verify your identity to set a new password.',
                  style: TextStyle(
                    fontSize: 13.5,
                    color: Color(0xFF6D6F7A),
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ---------- IDENTITY VERIFICATION SECTION ----------
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 10),
                child: Text(
                  'IDENTITY VERIFICATION',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.3,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF6F39E8),
                  ),
                ),
              ),

              _ForgotField(
                label: 'FULL NAME',
                hint: 'First name (same as signup)',
                icon: Icons.badge_outlined,
                controller: _nameController,
              ),
              const SizedBox(height: 12),
              _ForgotField(
                label: 'EMAIL',
                hint: 'you@example.com',
                icon: Icons.mail_outline_rounded,
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              _ForgotField(
                label: 'USERNAME',
                hint: 'Your username',
                icon: Icons.alternate_email_rounded,
                controller: _usernameController,
              ),

              const SizedBox(height: 22),

              // ---------- NEW PASSWORD SECTION ----------
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 10),
                child: Text(
                  'NEW PASSWORD',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.3,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF6F39E8),
                  ),
                ),
              ),

              // Field 1 — no duplicate label (section header covers it)
              _ForgotField(
                label: '',
                hint: 'Enter new password (min 8 characters)',
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
              const SizedBox(height: 12),
              // Field 2 — no duplicate label either
              _ForgotField(
                label: '',
                hint: 'Re-enter new password',
                icon: Icons.lock_person_outlined,
                controller: _confirmPasswordController,
                obscure: _obscureConfirm,
                trailing: IconButton(
                  splashRadius: 20,
                  icon: Icon(
                    _obscureConfirm
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20,
                    color: const Color(0xFF9B9EA9),
                  ),
                  onPressed: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                ),
              ),

              const SizedBox(height: 24),

              // ---------- UPDATE BUTTON ----------
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
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
                    _loading ? 'Updating...' : 'Update Password',
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ---------- BACK TO LOGIN ----------
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Remembered your password?',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF666A79),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
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

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable field widget
// ---------------------------------------------------------------------------

class _ForgotField extends StatelessWidget {
  const _ForgotField({
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
    final hasLabel = label.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasLabel)
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