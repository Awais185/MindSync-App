import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'onboarding_splash_shared.dart';
import 'onboarding_splash_widgets.dart';

/// Splash 1 — AI-powered emotional wellness landing (Get Started).
class OnboardingSplashPageOne extends StatelessWidget {
  const OnboardingSplashPageOne({
    super.key,
    required this.onGetStarted,
    required this.onSignIn,
  });

  final VoidCallback onGetStarted;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return OnboardingGradientBackground(
      variant: OnboardingBgVariant.lavender,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
          child: Column(
            children: [
              const SizedBox(height: 8),
              OnboardingPillBadge(
                label: 'AI-POWERED EMOTIONAL WELLNESS',
                leading: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF14B8A6),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF6F39E8),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(flex: 2),
              // Animated logo orb with floating dots around it
              const _AnimatedLogoOrbWithDots(diameter: 196),
              const Spacer(),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Mind',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1F2330),
                      letterSpacing: -0.5,
                    ),
                  ),
                  Text(
                    'Sync',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF6F39E8),
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'Find Your Balance. Discover Your Mind.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF374151),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ...List.generate(
                      3,
                      (i) => Container(
                        width: 6,
                        height: 6,
                        margin: EdgeInsets.only(right: i < 2 ? 4 : 8),
                        decoration: const BoxDecoration(
                          color: Color(0xFF6F39E8),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const Text(
                      'Connecting your sanctuary...',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(flex: 2),
              OnboardingPrimaryButton(
                label: 'Get Started',
                onPressed: onGetStarted,
              ),
              const SizedBox(height: 16),
              OnboardingSignInLink(onSignIn: onSignIn),
            ],
          ),
        ),
      ),
    );
  }
}

/// Animated wrapper around [OnboardingLogoOrb] that adds:
/// - Rotating dashed rings (subtle)
/// - Floating colored dots that bob up and down with staggered timing
class _AnimatedLogoOrbWithDots extends StatefulWidget {
  const _AnimatedLogoOrbWithDots({required this.diameter});

  final double diameter;

  @override
  State<_AnimatedLogoOrbWithDots> createState() =>
      _AnimatedLogoOrbWithDotsState();
}

class _AnimatedLogoOrbWithDotsState extends State<_AnimatedLogoOrbWithDots>
    with TickerProviderStateMixin {
  late final AnimationController _bobController;
  late final AnimationController _ringController;

  // Floating dot descriptors: angle around the orb, distance offset, color,
  // size and animation phase offset (0..1) for staggered movement.
  static final List<_DotSpec> _dots = [
    _DotSpec(
      angle: -math.pi * 0.75,
      radiusFactor: 1.30,
      color: const Color(0xFF8B5CF6), // purple
      size: 10,
      phase: 0.0,
    ),
    _DotSpec(
      angle: -math.pi * 0.20,
      radiusFactor: 1.42,
      color: const Color(0xFF8B5CF6), // purple
      size: 8,
      phase: 0.35,
    ),
    _DotSpec(
      angle: -math.pi * 0.55,
      radiusFactor: 1.55,
      color: const Color(0xFF5EEAD4), // teal
      size: 9,
      phase: 0.6,
    ),
    _DotSpec(
      angle: math.pi * 0.15,
      radiusFactor: 1.55,
      color: const Color(0xFF5EEAD4), // teal
      size: 8,
      phase: 0.15,
    ),
    _DotSpec(
      angle: math.pi * 0.85,
      radiusFactor: 1.42,
      color: const Color(0xFF5EEAD4), // teal
      size: 10,
      phase: 0.8,
    ),
    _DotSpec(
      angle: math.pi * 0.35,
      radiusFactor: 1.30,
      color: const Color(0xFF8B5CF6), // purple
      size: 7,
      phase: 0.45,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _bobController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();

    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 40),
    )..repeat();
  }

  @override
  void dispose() {
    _bobController.dispose();
    _ringController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The orb itself is 196 in your code, but the visual rings extend beyond.
    // We give the wrapper extra room so dots don't get clipped.
    final orbRadius = widget.diameter / 2;
    final canvasSize = widget.diameter * 2.0;

    return SizedBox(
      width: canvasSize,
      height: canvasSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Rotating dashed rings
          AnimatedBuilder(
            animation: _ringController,
            builder: (context, _) {
              return Transform.rotate(
                angle: _ringController.value * 2 * math.pi,
                child: CustomPaint(
                  size: Size(canvasSize, canvasSize),
                  painter: _DashedRingPainter(
                    radius: orbRadius * 1.28,
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.35),
                    dashCount: 28,
                    strokeWidth: 1.6,
                  ),
                ),
              );
            },
          ),
          AnimatedBuilder(
            animation: _ringController,
            builder: (context, _) {
              return Transform.rotate(
                angle: -_ringController.value * 2 * math.pi,
                child: CustomPaint(
                  size: Size(canvasSize, canvasSize),
                  painter: _DashedRingPainter(
                    radius: orbRadius * 1.55,
                    color: const Color(0xFF5EEAD4).withValues(alpha: 0.45),
                    dashCount: 34,
                    strokeWidth: 1.4,
                  ),
                ),
              );
            },
          ),

          // The original logo orb (unchanged visuals)
          OnboardingLogoOrb(diameter: widget.diameter),

          // Floating dots around the orb
          AnimatedBuilder(
            animation: _bobController,
            builder: (context, _) {
              return Stack(
                alignment: Alignment.center,
                children: _dots.map((dot) {
                  // Staggered phase; bob amplitude ~8px.
                  final t = (_bobController.value + dot.phase) % 1.0;
                  final bob = math.sin(t * 2 * math.pi) * 8.0;

                  final distance = orbRadius * dot.radiusFactor;
                  final dx = math.cos(dot.angle) * distance;
                  final dy = math.sin(dot.angle) * distance + bob;

                  return Transform.translate(
                    offset: Offset(dx, dy),
                    child: Container(
                      width: dot.size,
                      height: dot.size,
                      decoration: BoxDecoration(
                        color: dot.color,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: dot.color.withValues(alpha: 0.45),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DotSpec {
  _DotSpec({
    required this.angle,
    required this.radiusFactor,
    required this.color,
    required this.size,
    required this.phase,
  });

  final double angle;
  final double radiusFactor;
  final Color color;
  final double size;
  final double phase;
}

/// Paints a dashed circle (used for the rotating rings).
class _DashedRingPainter extends CustomPainter {
  _DashedRingPainter({
    required this.radius,
    required this.color,
    required this.dashCount,
    required this.strokeWidth,
  });

  final double radius;
  final Color color;
  final int dashCount;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final step = (2 * math.pi) / dashCount;
    final dashSweep = step * 0.55;

    for (int i = 0; i < dashCount; i++) {
      final start = i * step;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        dashSweep,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRingPainter oldDelegate) {
    return oldDelegate.radius != radius ||
        oldDelegate.color != color ||
        oldDelegate.dashCount != dashCount ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}