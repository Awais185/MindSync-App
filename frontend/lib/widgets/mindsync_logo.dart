import 'package:flutter/material.dart';

import '../services/app_public_service.dart';

class MindSyncLogo extends StatefulWidget {
  const MindSyncLogo({
    super.key,
    this.height = 40,
    this.width,
    this.fit = BoxFit.contain,
  });

  final double height;
  final double? width;
  final BoxFit fit;

  @override
  State<MindSyncLogo> createState() => _MindSyncLogoState();
}

class _MindSyncLogoState extends State<MindSyncLogo> {
  @override
  void initState() {
    super.initState();
    AppPublicService.instance.loadBranding();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppBrandingData>(
      valueListenable: AppPublicService.instance.branding,
      builder: (context, branding, _) {
        if (branding.logoUrl.isNotEmpty) {
          return Image.network(
            branding.logoUrl,
            height: widget.height,
            width: widget.width,
            fit: widget.fit,
            errorBuilder: (context, error, stackTrace) => _fallbackLogo(),
          );
        }
        return _fallbackLogo();
      },
    );
  }

  Widget _fallbackLogo() {
    return SizedBox(
      height: widget.height,
      width: widget.width ?? widget.height,
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


class MindSyncTitle extends StatefulWidget {
  const MindSyncTitle({
    super.key,
    this.style,
    this.textAlign,
    this.fallback = 'MindSync',
  });

  final TextStyle? style;
  final TextAlign? textAlign;
  final String fallback;

  @override
  State<MindSyncTitle> createState() => _MindSyncTitleState();
}

class _MindSyncTitleState extends State<MindSyncTitle> {
  @override
  void initState() {
    super.initState();
    AppPublicService.instance.loadBranding();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppBrandingData>(
      valueListenable: AppPublicService.instance.branding,
      builder: (context, branding, _) {
        final title = branding.appName.trim().isEmpty
            ? widget.fallback
            : branding.appName;
        return Text(
          title,
          style: widget.style,
          textAlign: widget.textAlign,
        );
      },
    );
  }
}
