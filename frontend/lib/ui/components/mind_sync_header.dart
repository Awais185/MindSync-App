import 'package:flutter/material.dart';

import 'mindsync_app_header.dart';

/// Legacy name — use [MindSyncAppHeader]. Supports pushed screens with a back button.
class MindSyncHeader extends StatelessWidget {
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
  Widget build(BuildContext context) {
    if (showSettingsIconInsteadOfProfile) {
      return MindSyncAppHeader(onBack: onBack);
    }
    return MindSyncAppHeader(onBack: onBack);
  }
}
