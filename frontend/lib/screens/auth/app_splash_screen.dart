import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants/app_assets.dart';

/// Cold-start splash: white screen, centered logo, gentle fade-in, then [onFinished].
class AppSplashScreen extends StatefulWidget {
  const AppSplashScreen({
    super.key,
    required this.onFinished,
    this.maxDuration = const Duration(seconds: 5),
  });

  final VoidCallback onFinished;
  final Duration maxDuration;

  @override
  State<AppSplashScreen> createState() => _AppSplashScreenState();
}

class _AppSplashScreenState extends State<AppSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _logoScale;
  Timer? _maxTimer;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.white,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );

    _controller = AnimationController(
      vsync: this,
      duration: widget.maxDuration,
    );

    _logoOpacity = Tween<double>(begin: 0.35, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
    );

    _logoScale = Tween<double>(begin: 0.92, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    unawaited(_controller.forward());
    _maxTimer = Timer(widget.maxDuration + const Duration(milliseconds: 200), _complete);

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _complete();
      }
    });
  }

  void _complete() {
    if (_finished || !mounted) return;
    _finished = true;
    _maxTimer?.cancel();
    widget.onFinished();
  }

  @override
  void dispose() {
    _maxTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Center(
            child: Opacity(
              opacity: _logoOpacity.value,
              child: Transform.scale(
                scale: _logoScale.value,
                child: child,
              ),
            ),
          );
        },
        child: Image.asset(
          AppAssets.mindSyncLogo,
          height: 140,
          width: 140,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          gaplessPlayback: true,
        ),
      ),
    );
  }
}
