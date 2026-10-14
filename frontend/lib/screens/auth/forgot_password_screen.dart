import 'package:flutter/material.dart';
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
      backgroundColor: const Color(0xFFF6F6FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F6FA),
        elevation: 0,
        foregroundColor: const Color(0xFF1E2432),
        title: const Text(
          'Forgot password',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(
                child: SizedBox(
                  height: 72,
                  width: 140,
                  child: MindSyncLogo(height: 72, width: 140),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Enter the same name, email, and username as on your account. '
                'If they all match, your password will be updated.',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.35,
                  color: Color(0xFF6D6F7A),
                ),
              ),
              const SizedBox(height: 20),
              _ForgotField(
                hint: 'Full name (as registered)',
                controller: _nameController,
              ),
              const SizedBox(height: 14),
              _ForgotField(
                hint: 'Email address',
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 14),
              _ForgotField(
                hint: 'Username',
                controller: _usernameController,
              ),
              const SizedBox(height: 14),
              _ForgotField(
                hint: 'New password',
                controller: _passwordController,
                obscure: true,
              ),
              const SizedBox(height: 14),
              _ForgotField(
                hint: 'Confirm new password',
                controller: _confirmPasswordController,
                obscure: true,
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    elevation: 6,
                    shadowColor: const Color(0x4D6F39E8),
                    foregroundColor: Colors.white,
                    backgroundColor: const Color(0xFF6F39E8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: Text(
                    _loading ? 'Updating...' : 'Update password',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ForgotField extends StatelessWidget {
  const _ForgotField({
    required this.hint,
    required this.controller,
    this.obscure = false,
    this.keyboardType,
  });

  final String hint;
  final TextEditingController controller;
  final bool obscure;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
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
