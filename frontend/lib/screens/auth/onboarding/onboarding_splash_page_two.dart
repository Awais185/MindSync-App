import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'onboarding_splash_shared.dart';
import 'onboarding_splash_widgets.dart';

/// Splash 2 — Connect your mind / sanctuary core.
class OnboardingSplashPageTwo extends StatelessWidget {
  const OnboardingSplashPageTwo({
    super.key,
    required this.onSkip,
    required this.onContinue,
    required this.onSignIn,
    required this.pageIndex,
  });

  final VoidCallback onSkip;
  final VoidCallback onContinue;
  final VoidCallback onSignIn;
  final int pageIndex;

  @override
  Widget build(BuildContext context) {
    return OnboardingGradientBackground(
      variant: OnboardingBgVariant.softWhite,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ---- Top row: Skip only (MindSync header removed) ----
              Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: onSkip,
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.9),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                        side: const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                    ),
                    child: const Text(
                      'Skip',
                      style: TextStyle(
                        color: Color(0xFF374151),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Center(
                  child: const _SanctuaryOrbitGraphic(),
                ),
              ),
              OnboardingPillBadge(
                label: 'Every step brings you closer to inner clarity.',
                leading: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF22C55E),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Column(
                children: [
                  const Text(
                    'Connect Your Mind,',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      height: 1.2,
                      color: Color(0xFF111827),
                    ),
                  ),
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Color(0xFF6F39E8), Color(0xFF14B8A6)],
                    ).createShader(bounds),
                    child: const Text(
                      'Transform Your Life',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Understand Yourself. Grow Every Day.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF6B7280),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 20),
              OnboardingPageDots(count: 3, activeIndex: pageIndex),
              const SizedBox(height: 20),
              OnboardingPrimaryButton(
                label: 'Begin Your Journey',
                onPressed: onContinue,
              ),
              const SizedBox(height: 14),
              OnboardingSignInLink(
                onSignIn: onSignIn,
                prefix: 'Already have a sanctuary account? ',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Orbit graphic with animated floating chips.
class _SanctuaryOrbitGraphic extends StatefulWidget {
  const _SanctuaryOrbitGraphic();

  @override
  State<_SanctuaryOrbitGraphic> createState() =>
      _SanctuaryOrbitGraphicState();
}

class _SanctuaryOrbitGraphicState extends State<_SanctuaryOrbitGraphic>
    with TickerProviderStateMixin {
  late final AnimationController _bobController;
  late final AnimationController _ringController;

  // Phase offsets give staggered motion so chips don't all move in sync.
  static const double _wellbeingPhase = 0.0;
  static const double _parentalPhase = 0.33;
  static const double _digitalPhase = 0.66;

  @override
  void initState() {
    super.initState();
    _bobController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();

    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 45),
    )..repeat();
  }

  @override
  void dispose() {
    _bobController.dispose();
    _ringController.dispose();
    super.dispose();
  }

  double _bobFor(double phase, {double amplitude = 7.0}) {
    final t = (_bobController.value + phase) % 1.0;
    return math.sin(t * 2 * math.pi) * amplitude;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 320,
      height: 300,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer static ring
          Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFFE5E7EB),
                width: 1.5,
              ),
            ),
          ),

          // Rotating dashed teal ring
          AnimatedBuilder(
            animation: _ringController,
            builder: (context, _) {
              return Transform.rotate(
                angle: _ringController.value * 2 * math.pi,
                child: CustomPaint(
                  size: const Size(260, 260),
                  painter: _DashedRingPainter(
                    radius: 100,
                    color: const Color(0xFF99F6E4).withValues(alpha: 0.9),
                    dashCount: 30,
                    strokeWidth: 1.4,
                  ),
                ),
              );
            },
          ),

          // Inner glow disc with MindSync logo in the center
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Colors.white,
                  const Color(0xFFE9D5FF).withValues(alpha: 0.5),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6F39E8).withValues(alpha: 0.15),
                  blurRadius: 30,
                ),
              ],
            ),
            child: const Center(
              child: SizedBox(
                width: 78,
                height: 78,
                // Reuse the existing MindSync orb logo widget.
                // If your OnboardingLogoOrb accepts a diameter, this renders
                // the MindSync head-icon + wordmark inside the center disc.
                child: OnboardingLogoOrb(diameter: 78),
              ),
            ),
          ),

          // Animated floating chips
          AnimatedBuilder(
            animation: _bobController,
            builder: (context, _) {
              return Stack(
                children: [
                  Positioned(
                    top: 36 + _bobFor(_wellbeingPhase),
                    left: 8,
                    child: _orbitChip(
                      'WELLBEING',
                      '94% Balanced',
                      Icons.monitor_heart_outlined,
                      const Color(0xFF14B8A6),
                    ),
                  ),
                  Positioned(
                    top: 48 + _bobFor(_parentalPhase),
                    right: 4,
                    child: _orbitChip(
                      'PARENTAL',
                      'control',
                      Icons.wb_sunny_outlined,
                      const Color(0xFF3B82F6),
                    ),
                  ),
                  Positioned(
                    bottom: 40 + _bobFor(_digitalPhase),
                    left: 16,
                    child: _orbitChip(
                      'DIGITAL',
                      'Behaviour',
                      Icons.nightlight_round,
                      const Color(0xFF6F39E8),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _orbitChip(
    String title,
    String subtitle,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                  color: color,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF374151),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Paints a dashed circle (used for the rotating teal ring).
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