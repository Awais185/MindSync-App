import 'package:flutter/material.dart';

import '../../widgets/mindsync_logo.dart';
import '../../services/local_auth_service.dart';

class MindSyncHeader extends StatefulWidget {
  const MindSyncHeader({
    super.key,
    this.onBack,
    this.onProfileTap,
    this.profileAvatarImageUrl,
    this.showSettingsIconInsteadOfProfile = false,
  });

  final VoidCallback? onBack;
  final VoidCallback? onProfileTap;
  final String? profileAvatarImageUrl;
  final bool showSettingsIconInsteadOfProfile;

  @override
  State<MindSyncHeader> createState() => _MindSyncHeaderState();
}

class _MindSyncHeaderState extends State<MindSyncHeader> {
  final _auth = LocalAuthService();
  String? _faceImageUrl;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadIfNeeded();
  }

  Future<void> _loadIfNeeded() async {
    if (widget.profileAvatarImageUrl != null) {
      setState(() {
        _faceImageUrl = widget.profileAvatarImageUrl;
        _loading = false;
      });
      return;
    }
    final profile = await _auth.fetchCurrentUserProfile();
    if (!mounted) return;
    setState(() {
      _faceImageUrl = profile?.faceImage;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final avatarUrl = _faceImageUrl == null
        ? null
        : widget.profileAvatarImageUrl ?? _faceImageUrl;

    return SizedBox(
      height: 56,
      child: Row(
        children: [
          if (widget.onBack != null)
            IconButton(
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 5),
            child: MindSyncLogo(height: 100, width: 150),
          ),
          const Spacer(),
          widget.showSettingsIconInsteadOfProfile
              ? IconButton(
                  onPressed: widget.onProfileTap,
                  icon: const Icon(Icons.settings_outlined, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                )
              : InkWell(
                  onTap: widget.onProfileTap,
                  borderRadius: BorderRadius.circular(16),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: const Color(0xFFEEE8FF),
                    child: (_loading || avatarUrl == null)
                        ? const Icon(
                            Icons.person,
                            size: 18,
                            color: Color(0xFF6F39E8),
                          )
                        : CircleAvatar(
                            radius: 16,
                            backgroundImage: avatarUrl.isNotEmpty
                                ? NetworkImage(_auth.resolveMediaUrl(avatarUrl))
                                : null,
                            child: avatarUrl.isEmpty
                                ? const Icon(
                                    Icons.person,
                                    size: 18,
                                    color: Color(0xFF6F39E8),
                                  )
                                : null,
                          ),
                  ),
                ),
        ],
      ),
    );
  }
}
