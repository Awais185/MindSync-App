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

  // Changed: dropdown values instead of raw profession controller.
  String? _profession;
  String? _ageRange;

  bool _editing = false;
  bool _loading = true;
  bool _saving = false;
  bool _faceEnrolled = false;
  String _faceImageUrl = '';
  Uint8List? _newFaceImageBytes;

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
    _load();
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _username.dispose();
    _email.dispose();
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
      _profession = _normalizeProfession(profile.profession);
      // Age is not stored in the current model; keep null unless preloaded.
      _ageRange = null;
      _faceEnrolled = profile.faceEnrolled;
      _faceImageUrl = _auth.resolveMediaUrl(profile.faceImage);
    }
    setState(() => _loading = false);
  }

  /// Maps a raw stored profession string to one of the dropdown options.
  String? _normalizeProfession(String raw) {
    final v = raw.trim().toLowerCase();
    if (v.isEmpty) return null;
    for (final opt in _professionOptions) {
      if (opt.toLowerCase() == v) return opt;
    }
    if (v.contains('student')) return 'Student';
    if (v.contains('work') || v.contains('professional')) {
      return 'Working Professional';
    }
    if (v.contains('child') || v.contains('kid')) return 'Children';
    return null;
  }

  String get _fullName {
    final value = '${_firstName.text.trim()} ${_lastName.text.trim()}'.trim();
    return value.isEmpty ? 'User' : value;
  }

  String get _professionTitle {
    final value = (_profession ?? '').trim();
    if (value.isEmpty) return 'Other';
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }

  Future<void> _pickImage() async {
    if (!_editing) {
      _show('Tap Edit Profile to change your photo.');
      return;
    }
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
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
    if (_profession == null) {
      _show('Please select your profession.');
      return;
    }

    setState(() => _saving = true);
    try {
      final updated = await _auth.updateProfile(
        firstName: _firstName.text.trim(),
        lastName: _lastName.text.trim(),
        username: _username.text.trim(),
        email: _email.text.trim(),
        profession: _profession ?? 'other',
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
        _profession = _normalizeProfession(updated.profession);
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
    bool obscureCurrent = true;
    bool obscureNew = true;
    bool obscureConfirm = true;

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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: const Text(
                'Change Password',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1F2330),
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _DialogPasswordField(
                    controller: currentController,
                    label: 'Current Password',
                    obscure: obscureCurrent,
                    onToggle: () => setDialogState(
                      () => obscureCurrent = !obscureCurrent,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _DialogPasswordField(
                    controller: newController,
                    label: 'New Password',
                    obscure: obscureNew,
                    onToggle: () =>
                        setDialogState(() => obscureNew = !obscureNew),
                  ),
                  const SizedBox(height: 12),
                  _DialogPasswordField(
                    controller: confirmController,
                    label: 'Confirm Password',
                    obscure: obscureConfirm,
                    onToggle: () => setDialogState(
                      () => obscureConfirm = !obscureConfirm,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed:
                      loading ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                ElevatedButton(
                  onPressed: loading ? null : submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6F39E8),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: Text(
                    loading ? 'Saving...' : 'Save',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
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
      backgroundColor: const Color(0xFFF3F1FB),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // ---------- TOP BAR ----------
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                    child: Row(
                      children: [
                        Material(
                          color: Colors.white,
                          shape: const CircleBorder(),
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
                        const Expanded(
                          child: Center(
                            child: Text(
                              'Profile',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1F2330),
                                letterSpacing: -0.3,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 40,
                          child: _editing
                              ? null
                              : IconButton(
                                  onPressed: () =>
                                      setState(() => _editing = true),
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 20,
                                    color: Color(0xFF6F39E8),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),

                  // ---------- SCROLL BODY ----------
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                      children: [
                        // ---- AVATAR + NAME CARD ----
                        _ProfileHeaderCard(
                          bytes: _newFaceImageBytes,
                          imageUrl: _faceImageUrl,
                          fullName: _fullName,
                          professionTitle: _professionTitle,
                          faceEnrolled: _faceEnrolled,
                          editing: _editing,
                          onPickImage: _pickImage,
                        ),

                        const SizedBox(height: 20),

                        // ---- PERSONAL INFORMATION ----
                        const _SectionHeader('PERSONAL INFORMATION'),
                        _Card(
                          children: [
                            _EditableRow(
                              label: 'First Name',
                              controller: _firstName,
                              editing: _editing,
                              icon: Icons.person_outline_rounded,
                            ),
                            const _Divider(),
                            _EditableRow(
                              label: 'Last Name',
                              controller: _lastName,
                              editing: _editing,
                              icon: Icons.person_outline_rounded,
                            ),
                            const _Divider(),
                            _EditableRow(
                              label: 'Username',
                              controller: _username,
                              editing: _editing,
                              icon: Icons.alternate_email_rounded,
                            ),
                            const _Divider(),
                            _EditableRow(
                              label: 'Email',
                              controller: _email,
                              editing: _editing,
                              icon: Icons.mail_outline_rounded,
                              keyboardType: TextInputType.emailAddress,
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // ---- ACCOUNT DETAILS ----
                        const _SectionHeader('ACCOUNT DETAILS'),
                        _Card(
                          children: [
                            _DropdownRow(
                              label: 'Profession',
                              icon: Icons.work_outline_rounded,
                              value: _profession,
                              options: _professionOptions,
                              editing: _editing,
                              onChanged: (v) =>
                                  setState(() => _profession = v),
                            ),
                            const _Divider(),
                            _DropdownRow(
                              label: 'Age',
                              icon: Icons.cake_outlined,
                              value: _ageRange,
                              options: _ageOptions,
                              editing: _editing,
                              onChanged: (v) =>
                                  setState(() => _ageRange = v),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // ---- SECURITY ----
                        const _SectionHeader('SECURITY'),
                        _Card(
                          children: [
                            _TileRow(
                              icon: Icons.lock_outline_rounded,
                              title: 'Password',
                              subtitle: 'Update your account password',
                              trailing: TextButton(
                                onPressed: _showChangePasswordDialog,
                                child: const Text(
                                  'Change',
                                  style: TextStyle(
                                    color: Color(0xFF6F39E8),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                            const _Divider(),
                            _TileRow(
                              icon: Icons.face_retouching_natural,
                              title: 'Face Scan',
                              subtitle: _faceEnrolled
                                  ? 'Registered — secure entry enabled'
                                  : 'Not registered yet',
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: _faceEnrolled
                                      ? const Color(0xFFDCFCE7)
                                      : const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  _faceEnrolled ? 'Active' : 'Pending',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: _faceEnrolled
                                        ? const Color(0xFF15803D)
                                        : const Color(0xFFB45309),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // ---- BILLING ----
                        const _SectionHeader('BILLING'),
                        _Card(
                          children: [
                            _TileRow(
                              icon: Icons.receipt_long_outlined,
                              title: 'Payment History',
                              subtitle: 'View your transactions',
                              trailing: const Icon(
                                Icons.chevron_right_rounded,
                                color: Color(0xFF9B9EA9),
                              ),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const PaymentHistoryScreen(),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // ---- SAVE / EDIT BUTTON ----
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton(
                            onPressed: _saving ? null : _save,
                            style: ElevatedButton.styleFrom(
                              elevation: 0,
                              backgroundColor: const Color(0xFF6F39E8),
                              foregroundColor: Colors.white,
                              disabledBackgroundColor:
                                  const Color(0xFFD0C7EE),
                              disabledForegroundColor: Colors.white70,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
                              ),
                            ),
                            child: Text(
                              _saving
                                  ? 'Saving...'
                                  : (_editing ? 'Save Changes' : 'Edit Profile'),
                              style: const TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ),

                        if (_editing) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: TextButton(
                              onPressed: _saving
                                  ? null
                                  : () => setState(() => _editing = false),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(
                                  color: Color(0xFF6B6D79),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable widgets
// ---------------------------------------------------------------------------

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
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.3,
          color: Color(0xFF6F39E8),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(children: children),
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

class _ProfileHeaderCard extends StatelessWidget {
  const _ProfileHeaderCard({
    required this.bytes,
    required this.imageUrl,
    required this.fullName,
    required this.professionTitle,
    required this.faceEnrolled,
    required this.editing,
    required this.onPickImage,
  });

  final Uint8List? bytes;
  final String imageUrl;
  final String fullName;
  final String professionTitle;
  final bool faceEnrolled;
  final bool editing;
  final VoidCallback onPickImage;

  @override
  Widget build(BuildContext context) {
    final ImageProvider<Object>? provider = bytes != null
        ? MemoryImage(bytes!)
        : (imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF8F6FE), Color(0xFFEDE8FB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE7E4F1)),
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
                    colors: faceEnrolled
                        ? const [Color(0xFF6F39E8), Color(0xFF14B8A6)]
                        : const [
                            Color(0xFFE0D8F7),
                            Color(0xFFE0D8F7),
                          ],
                  ),
                ),
                child: CircleAvatar(
                  radius: 44,
                  backgroundColor: const Color(0xFFF1EEFB),
                  backgroundImage: provider,
                  child: provider == null
                      ? const Icon(
                          Icons.person,
                          size: 44,
                          color: Color(0xFF6F39E8),
                        )
                      : null,
                ),
              ),
              if (editing)
                GestureDetector(
                  onTap: onPickImage,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF6F39E8),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(
                      Icons.edit,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              if (faceEnrolled && !editing)
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
          const SizedBox(height: 14),
          Text(
            fullName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1F2330),
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'MindSync $professionTitle Member',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFF6D6F7A),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditableRow extends StatelessWidget {
  const _EditableRow({
    required this.label,
    required this.controller,
    required this.editing,
    this.icon,
    this.keyboardType,
  });

  final String label;
  final TextEditingController controller;
  final bool editing;
  final IconData? icon;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: const Color(0xFF9B9EA9)),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF9B9EA9),
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 4),
                editing
                    ? TextField(
                        controller: controller,
                        keyboardType: keyboardType,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1F2330),
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF5F3FC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFF6F39E8),
                              width: 1.6,
                            ),
                          ),
                        ),
                      )
                    : Text(
                        controller.text.trim().isEmpty
                            ? '-'
                            : controller.text.trim(),
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1F2330),
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DropdownRow extends StatelessWidget {
  const _DropdownRow({
    required this.label,
    required this.icon,
    required this.value,
    required this.options,
    required this.editing,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final String? value;
  final List<String> options;
  final bool editing;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF9B9EA9)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF9B9EA9),
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 4),
                editing
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F3FC),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: value,
                            isExpanded: true,
                            hint: Text(
                              'Select $label',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF9B9EA9),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            icon: const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: Color(0xFF6F39E8),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            items: options
                                .map(
                                  (o) => DropdownMenuItem<String>(
                                    value: o,
                                    child: Text(
                                      o,
                                      style: const TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1F2330),
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: onChanged,
                          ),
                        ),
                      )
                    : Text(
                        value ?? '-',
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1F2330),
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TileRow extends StatelessWidget {
  const _TileRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F3FC),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: const Color(0xFF6F39E8)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1F2330),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF8A8C98),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogPasswordField extends StatelessWidget {
  const _DialogPasswordField({
    required this.controller,
    required this.label,
    required this.obscure,
    required this.onToggle,
  });

  final TextEditingController controller;
  final String label;
  final bool obscure;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(
        fontSize: 14.5,
        fontWeight: FontWeight.w600,
        color: Color(0xFF1F2330),
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: Color(0xFF6D6F7A),
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        suffixIcon: IconButton(
          splashRadius: 18,
          icon: Icon(
            obscure
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            size: 18,
            color: const Color(0xFF9B9EA9),
          ),
          onPressed: onToggle,
        ),
        filled: true,
        fillColor: const Color(0xFFF5F3FC),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: Color(0xFF6F39E8),
            width: 1.6,
          ),
        ),
      ),
    );
  }
}