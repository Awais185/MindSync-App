import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../constants/app_assets.dart';
import '../../../widgets/mindsync_logo.dart';
import 'onboarding_splash_widgets.dart';

/// Splash 3 — AI facial landmark recognition with portrait in center circle.
class OnboardingSplashPageThree extends StatelessWidget {
  const OnboardingSplashPageThree({
    super.key,
    required this.onContinue,
    required this.pageIndex,
  });

  final VoidCallback onContinue;
  final int pageIndex;

  @override
  Widget build(BuildContext context) {
    return OnboardingGradientBackground(
      variant: OnboardingBgVariant.mint,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Scale everything relative to the available height so the page
            // always fits without scrolling or overflowing on any device.
            final h = constraints.maxHeight;
            final scale = (h / 780).clamp(0.80, 1.10);

            return Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                8 * scale,
                24,
                12 * scale,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // ---- Top badges ----
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OnboardingPillBadge(
                        label: 'AI FACIAL SCAN',
                        leading: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _dot(const Color(0xFF14B8A6)),
                            const SizedBox(width: 4),
                            _dot(const Color(0xFF6F39E8)),
                          ],
                        ),
                      ),
                      SizedBox(height: 8 * scale),
                      const OnboardingPillBadge(
                        label: 'Real-Time Landmark Mesh · 68 Points',
                        icon: Icons.hub_outlined,
                      ),
                    ],
                  ),

                  // ---- Center face graphic (flexible) ----
                  Flexible(
                    flex: 5,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: const _FaceScanGraphic(),
                    ),
                  ),

                  // ---- Bottom content block ----
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MindSyncLogo(
                        height: 44 * scale,
                        width: 120 * scale,
                      ),
                      SizedBox(height: 12 * scale),
                      Text(
                        'AI Emotion & Landmark Recognition',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22 * scale,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF111827),
                          height: 1.2,
                        ),
                      ),
                      SizedBox(height: 8 * scale),
                      Text(
                        'Real-time facial landmark detection analyzes subtle '
                        'expressions to understand your stress, mood, and '
                        'wellbeing.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13 * scale,
                          height: 1.4,
                          color: const Color(0xFF6B7280),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 14 * scale),
                      OnboardingPageDots(count: 3, activeIndex: pageIndex),
                      SizedBox(height: 14 * scale),
                      OnboardingPrimaryButton(
                        label: 'Begin Facial Analysis',
                        onPressed: onContinue,
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  static Widget _dot(Color c) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
    );
  }
}

/// Face scan graphic with animated floating chips around the circle.
class _FaceScanGraphic extends StatefulWidget {
  const _FaceScanGraphic();

  @override
  State<_FaceScanGraphic> createState() => _FaceScanGraphicState();
}

class _FaceScanGraphicState extends State<_FaceScanGraphic>
    with SingleTickerProviderStateMixin {
  static const double _circleSize = 220;
  static const double _canvasWidth = 340;
  static const double _canvasHeight = 320;

  late final AnimationController _bobController;

  // 5 chips, staggered phases, positioned around the circle.
  static const List<_ChipSpec> _chips = [
    _ChipSpec(
      label: 'Wellbeing',
      icon: Icons.monitor_heart_outlined,
      color: Color(0xFF14B8A6),
      top: 10,
      left: 6,
      phase: 0.00,
    ),
    _ChipSpec(
      label: 'Parental',
      icon: Icons.wb_sunny_outlined,
      color: Color(0xFF3B82F6),
      top: 28,
      right: 4,
      phase: 0.20,
    ),
    _ChipSpec(
      label: 'Focus',
      icon: Icons.center_focus_strong_outlined,
      color: Color(0xFFF59E0B),
      top: 118,
      left: -4,
      phase: 0.40,
    ),
    _ChipSpec(
      label: 'Sleep',
      icon: Icons.nightlight_round,
      color: Color(0xFF6F39E8),
      top: 130,
      right: -4,
      phase: 0.60,
    ),
    _ChipSpec(
      label: 'Digital',
      icon: Icons.phone_iphone_rounded,
      color: Color(0xFF6F39E8),
      bottom: 12,
      left: 12,
      phase: 0.80,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _bobController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();
  }

  @override
  void dispose() {
    _bobController.dispose();
    super.dispose();
  }

  double _bobFor(double phase, {double amplitude = 6.0}) {
    final t = (_bobController.value + phase) % 1.0;
    return math.sin(t * 2 * math.pi) * amplitude;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _canvasWidth,
      height: _canvasHeight,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // ---- Center circular portrait ----
          // ---- Center circular portrait (full image, no crop) ----
Positioned(
  top: (_canvasHeight - _circleSize) / 2,
  child: Container(
    width: _circleSize,
    height: _circleSize,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 28,
          offset: const Offset(0, 12),
        ),
      ],
    ),
    child: ClipOval(
      child: Padding(
        // Small inner padding so the face doesn't touch the circle edge.
        padding: const EdgeInsets.all(10),
        child: Image.asset(
          AppAssets.facialLandmarkPortrait,
          width: _circleSize,
          height: _circleSize,
          // 'contain' shows the ENTIRE image — no side cropping.
          fit: BoxFit.contain,
          alignment: Alignment.center,
        ),
      ),
    ),
  ),
),

          // ---- Animated floating chips ----
          AnimatedBuilder(
            animation: _bobController,
            builder: (context, _) {
              return Stack(
                children: _chips.map((spec) {
                  final offset = _bobFor(spec.phase);
                  return Positioned(
                    top: spec.top != null ? spec.top! + offset : null,
                    bottom:
                        spec.bottom != null ? spec.bottom! - offset : null,
                    left: spec.left,
                    right: spec.right,
                    child: _orbitChip(spec),
                  );
                }).toList(),
              );
            },
          ),

          // ---- Floating "Emotion Recognition" pill ----
          Positioned(
            bottom: 0,
            child: AnimatedBuilder(
              animation: _bobController,
              builder: (context, _) {
                return Transform.translate(
                  offset: Offset(0, _bobFor(0.5, amplitude: 4.0)),
                  child: const OnboardingPillBadge(
                    label: 'Emotion Recognition · 98% Confidence',
                    icon: Icons.sentiment_satisfied_alt_outlined,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _orbitChip(_ChipSpec spec) {
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
          Icon(spec.icon, size: 16, color: spec.color),
          const SizedBox(width: 6),
          Text(
            spec.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: spec.color,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipSpec {
  const _ChipSpec({
    required this.label,
    required this.icon,
    required this.color,
    required this.phase,
    this.top,
    this.bottom,
    this.left,
    this.right,
  });

  final String label;
  final IconData icon;
  final Color color;
  final double phase;
  final double? top;
  final double? bottom;
  final double? left;
  final double? right;
}