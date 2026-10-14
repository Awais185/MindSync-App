import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/local_auth_service.dart';
import '../payment_history_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _auth = LocalAuthService();
  final _picker = ImagePicker();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _profession = TextEditingController();

  bool _editing = false;
  bool _loading = true;
  bool _saving = false;
  bool _faceEnrolled = false;
  String _faceImageUrl = '';
  Uint8List? _newFaceImageBytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _username.dispose();
    _email.dispose();
    _profession.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final profile = await _auth.fetchCurrentUserProfile();
    if (!mounted) return;
    if (profile != null) {
      _firstName.text = profile.firstName;
      _lastName.text = profile.lastName;
      _username.text = profile.username;
      _email.text = profile.email;
      _profession.text = profile.profession;
      _faceEnrolled = profile.faceEnrolled;
      _faceImageUrl = _auth.resolveMediaUrl(profile.faceImage);
    }
    setState(() => _loading = false);
  }

  String get _fullName {
    final value = '${_firstName.text.trim()} ${_lastName.text.trim()}'.trim();
    return value.isEmpty ? 'User' : value;
  }

  String get _professionTitle {
    final value = _profession.text.trim();
    if (value.isEmpty) return 'Other';
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }

  Future<void> _pickImage() async {
    if (!_editing) return;
    final image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (image == null) return;
    final bytes = await image.readAsBytes();
    if (!mounted) return;
    setState(() {
      _newFaceImageBytes = bytes;
      _faceEnrolled = true;
    });
  }

  Future<void> _save() async {
    if (!_editing) {
      setState(() => _editing = true);
      return;
    }
    if (_firstName.text.trim().isEmpty ||
        _username.text.trim().isEmpty ||
        _email.text.trim().isEmpty) {
      _show('First name, username, and email are required.');
      return;
    }
    setState(() => _saving = true);
    try {
      final updated = await _auth.updateProfile(
        firstName: _firstName.text.trim(),
        lastName: _lastName.text.trim(),
        username: _username.text.trim(),
        email: _email.text.trim(),
        profession: _profession.text.trim().isEmpty ? 'other' : _profession.text.trim(),
        faceImageBytes: _newFaceImageBytes,
      );
      if (!mounted) return;
      setState(() {
        _editing = false;
        _saving = false;
        _newFaceImageBytes = null;
        _firstName.text = updated.firstName;
        _lastName.text = updated.lastName;
        _username.text = updated.username;
        _email.text = updated.email;
        _profession.text = updated.profession;
        _faceEnrolled = updated.faceEnrolled;
        _faceImageUrl = _auth.resolveMediaUrl(updated.faceImage);
      });
      _show('Profile updated successfully.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _show(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _show(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _showChangePasswordDialog() async {
    final currentController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    bool loading = false;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              final current = currentController.text;
              final next = newController.text;
              final confirm = confirmController.text;
              if (current.isEmpty || next.isEmpty || confirm.isEmpty) {
                _show('Please fill all password fields.');
                return;
              }
              if (next.length < 8) {
                _show('New password must be at least 8 characters.');
                return;
              }
              if (next != confirm) {
                _show('New password and confirm password do not match.');
                return;
              }
              setDialogState(() => loading = true);
              try {
                await _auth.changePassword(
                  currentPassword: current,
                  newPassword: next,
                );
                if (!mounted || !dialogContext.mounted) return;
                Navigator.of(dialogContext).pop();
                _show('Password changed successfully.');
              } catch (e) {
                if (!mounted || !dialogContext.mounted) return;
                setDialogState(() => loading = false);
                _show(e.toString().replaceFirst('Exception: ', ''));
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text('Change Password'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: currentController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Current Password'),
                  ),
                  TextField(
                    controller: newController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'New Password'),
                  ),
                  TextField(
                    controller: confirmController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Confirm Password'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: loading ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: loading ? null : submit,
                  child: Text(loading ? 'Saving...' : 'Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: const Icon(
                          Icons.arrow_back_ios,
                          size: 18,
                          color: Color(0xFF6F39E8),
                        ),
                      ),
                      const Expanded(
                        child: Center(
                          child: Text(
                            'Edit Profile',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color: Color(0xFF1C1C1E),
                            ),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _saving ? null : _save,
                        child: Text(
                          _saving ? 'Saving...' : 'Save',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF6F39E8),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 40,
                          backgroundColor: const Color(0xFF1E2A3A),
                          backgroundImage: _newFaceImageBytes != null
                              ? MemoryImage(_newFaceImageBytes!)
                              : (_faceImageUrl.isNotEmpty ? NetworkImage(_faceImageUrl) : null)
                                  as ImageProvider<Object>?,
                          child: (_newFaceImageBytes == null && _faceImageUrl.isEmpty)
                              ? const Icon(Icons.person, size: 42, color: Colors.white)
                              : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: _pickImage,
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF6F39E8),
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: const Icon(Icons.edit, size: 12, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      _fullName,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1C1C1E),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      'MindSync $_professionTitle Member',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: Color(0xFF8A8C98),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  const _SectionHeader('PERSONAL INFORMATION'),
                  _InfoCard(
                    children: [
                      _EditableInfoRow(label: 'First Name', controller: _firstName, editing: _editing),
                      const _Divider(),
                      _EditableInfoRow(label: 'Last Name', controller: _lastName, editing: _editing),
                      const _Divider(),
                      _EditableInfoRow(label: 'Username', controller: _username, editing: _editing),
                      const _Divider(),
                      _EditableInfoRow(label: 'Email Address', controller: _email, editing: _editing),
                    ],
                  ),
                  const SizedBox(height: 16),

                  const _SectionHeader('BILLING'),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.receipt_long, color: Color(0xFF6F39E8)),
                      title: const Text(
                        'Payment History',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const PaymentHistoryScreen()),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),

                  const _SectionHeader('SECURITY'),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              const Icon(Icons.lock_outline, size: 20, color: Color(0xFF6F39E8)),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Password',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF1C1C1E),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _saving ? 'Saving profile...' : 'Update your account password',
                                    style: const TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 13,
                                      color: Color(0xFF8A8C98),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1, thickness: 1, color: Color(0xFFEFEFF4)),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: OutlinedButton(
                              onPressed: _showChangePasswordDialog,
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFFE9E9EF), width: 1),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'Change Password',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF6F39E8),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  const _SectionHeader('AUTHENTICATION'),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(Icons.face_retouching_natural, size: 20, color: Color(0xFF6F39E8)),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Face Scan',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1C1C1E),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _faceEnrolled ? 'Face Registered' : 'Face Not Registered',
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 13,
                                  color: Color(0xFF8A8C98),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  const _SectionHeader('ACCOUNT SETTINGS'),
                  _InfoCard(
                    children: [
                      _EditableInfoRow(label: 'Profession', controller: _profession, editing: _editing),
                      const _Divider(),
                      _EditableInfoRow(label: 'Email Address', controller: _email, editing: _editing),
                    ],
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6F39E8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        _saving ? 'Saving...' : (_editing ? 'Save Changes' : 'Edit Profile'),
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
          color: Color(0xFF8A8C98),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(children: children),
      ),
    );
  }
}

class _EditableInfoRow extends StatelessWidget {
  const _EditableInfoRow({
    required this.label,
    required this.controller,
    required this.editing,
  });

  final String label;
  final TextEditingController controller;
  final bool editing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF6C6E7A),
              ),
            ),
          ),
          Expanded(
            child: editing
                ? TextField(
                    controller: controller,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      filled: true,
                      fillColor: const Color(0xFFF5F6FA),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  )
                : Text(
                    controller.text.trim().isEmpty ? '-' : controller.text.trim(),
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1C1C1E),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      thickness: 0.5,
      color: Color(0xFFEFEFF4),
    );
  }
}