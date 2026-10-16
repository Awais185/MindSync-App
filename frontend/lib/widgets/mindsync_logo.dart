import 'package:flutter/material.dart';

import '../constants/app_assets.dart';
import '../services/app_public_service.dart';

class MindSyncLogo extends StatelessWidget {
  const MindSyncLogo({
    super.key,
    this.height = 40,
    this.width,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,   // ← NEW
  });

  final double height;
  final double? width;
  final BoxFit fit;
  final Alignment alignment;              // ← NEW

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      AppAssets.mindSyncLogo,
      height: height,
      width: width,
      fit: fit,
      alignment: alignment,               // ← NEW
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => _iconFallback(),
    );
  }

  Widget _iconFallback() {
    return SizedBox(
      height: height,
      width: width ?? height,
      child: const FittedBox(
        fit: BoxFit.contain,
        child: Icon(
          Icons.psychology,
          color: Color(0xFF6F39E8),
        ),
      ),
    );
  }
}