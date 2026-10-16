import 'package:flutter/material.dart';

import '../../../constants/app_assets.dart';
import '../../../widgets/mindsync_logo.dart';

class OnboardingBrandHeader extends StatelessWidget {
  const OnboardingBrandHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(6),
          child: Image.asset(
            AppAssets.mindSyncLogo,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(width: 10),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'MindSync',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A1C24),
                height: 1.1,
              ),
            ),
            Text(
              'SANCTUARY CORE',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
                color: Color(0xFF6F39E8),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class OnboardingLogoOrb extends StatelessWidget {
  const OnboardingLogoOrb({super.key, this.diameter = 200});

  final double diameter;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: diameter + 80,
      height: diameter + 80,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _dashedRing(diameter + 56, const Color(0xFFB8E8E8), 1.2),
          _dashedRing(diameter + 28, const Color(0xFFD4C4F8), 1),
          Positioned(
            top: 24,
            right: 28,
            child: _orbitDot(const Color(0xFF2DD4BF)),
          ),
          Positioned(
            left: 20,
            bottom: 48,
            child: _orbitDot(const Color(0xFF6F39E8)),
          ),
          Positioned(
            right: 48,
            bottom: 28,
            child: _orbitDot(const Color(0xFF93C5FD)),
          ),
          Container(
            width: diameter,
            height: diameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6F39E8).withValues(alpha: 0.18),
                  blurRadius: 40,
                  spreadRadius: 4,
                ),
              ],
            ),
            padding: EdgeInsets.all(diameter * 0.18),
            child: const MindSyncLogo(fit: BoxFit.contain),
          ),
        ],
      ),
    );
  }

  Widget _dashedRing(double size, Color color, double stroke) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _DashedCirclePainter(color: color, strokeWidth: stroke),
      ),
    );
  }

  Widget _orbitDot(Color c) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
    );
  }
}

class _DashedCirclePainter extends CustomPainter {
  _DashedCirclePainter({required this.color, required this.strokeWidth});

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    const dash = 6.0;
    const gap = 8.0;
    final r = size.width / 2 - strokeWidth;
    final center = Offset(size.width / 2, size.height / 2);
    final circumference = 2 * 3.14159 * r;
    final count = (circumference / (dash + gap)).floor();
    for (var i = 0; i < count; i++) {
      final start = i * (dash + gap) / r;
      final sweep = dash / r;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r),
        start,
        sweep,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
