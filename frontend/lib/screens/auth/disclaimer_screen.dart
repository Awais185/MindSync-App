import 'package:flutter/material.dart';

import '../../services/app_public_service.dart';
import '../../widgets/mindsync_logo.dart';

/// AI disclaimer — second onboarding step (after [WelcomeScreen], before login).
class DisclaimerScreen extends StatefulWidget {
  const DisclaimerScreen({super.key, required this.onAccepted});

  final VoidCallback onAccepted;

  @override
  State<DisclaimerScreen> createState() => _DisclaimerScreenState();
}

class _DisclaimerScreenState extends State<DisclaimerScreen> {
  bool _agreed = false;

  static const _points = <_DisclaimerPoint>[
    _DisclaimerPoint(
      icon: Icons.psychology_outlined,
      title: 'AI-Powered Insights',
      body:
          'MindSync analyzes your behavioral patterns using AI to surface '
          'wellness insights. Results may not always be fully accurate.',
    ),
    _DisclaimerPoint(
      icon: Icons.health_and_safety_outlined,
      title: 'Not a Medical Tool',
      body:
          'MindSync does not provide medical advice, diagnosis, or treatment. '
          'It supports self-awareness only.',
    ),
    _DisclaimerPoint(
      icon: Icons.support_agent_outlined,
      title: 'Seek Professional Help',
      body:
          'For any mental health concerns, please consult a qualified '
          'healthcare professional.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final publicService = AppPublicService.instance;

    return Scaffold(
      backgroundColor: const Color(0xFFEDE8FA),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  children: [
                    // ---- Logo ----
                    const SizedBox(
                      height: 80,
                      width: 130,
                      child: MindSyncLogo(height: 70, width: 120),
                    ),
                    const SizedBox(height: 6),

                    // ---- Tagline ----
                    ValueListenableBuilder<AppBrandingData>(
                      valueListenable: publicService.branding,
                      builder: (context, branding, _) => Text(
                        branding.welcomeTagline,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF686A76),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ---- Title ----
                    const Text(
                      'Before you begin',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1F2330),
                        height: 1.15,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'A quick note on how MindSync works',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: Color(0xFF686A76),
                        fontWeight: FontWeight.w500,
                      ),
                    ),

                    const SizedBox(height: 22),

                    // ---- Disclaimer card with icon points ----
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF6F39E8)
                                .withValues(alpha: 0.08),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF3E8FF),
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: const Icon(
                                  Icons.info_outline_rounded,
                                  color: Color(0xFF6F39E8),
                                  size: 17,
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                'IMPORTANT DISCLAIMER',
                                style: TextStyle(
                                  letterSpacing: 1.1,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                  color: Color(0xFF6F39E8),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          ...List.generate(_points.length, (i) {
                            return Padding(
                              padding: EdgeInsets.only(
                                bottom: i == _points.length - 1 ? 0 : 14,
                              ),
                              child: _pointRow(_points[i]),
                            );
                          }),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ---- Compact agree checkbox ----
                    Material(
                      color: Colors.white.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        onTap: () => setState(() => _agreed = !_agreed),
                        borderRadius: BorderRadius.circular(18),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 22,
                                height: 22,
                                child: Checkbox(
                                  value: _agreed,
                                  onChanged: (value) {
                                    setState(() => _agreed = value ?? false);
                                  },
                                  activeColor: const Color(0xFF6F39E8),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  side: const BorderSide(
                                    color: Color(0xFFB8BCC8),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'I understand and agree to the disclaimer above.',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    height: 1.35,
                                    color: Color(0xFF2B2D39),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 22),

                    // ---- Primary button ----
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _agreed ? widget.onAccepted : null,
                        style: ElevatedButton.styleFrom(
                          elevation: 0,
                          foregroundColor: Colors.white,
                          backgroundColor: const Color(0xFF6F39E8),
                          disabledBackgroundColor: const Color(0xFFC4B5E8),
                          disabledForegroundColor: Colors.white70,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(40),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Get Started',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4,
                              ),
                            ),
                            SizedBox(width: 10),
                            Icon(Icons.arrow_forward_rounded, size: 20),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pointRow(_DisclaimerPoint point) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFFF5F3FF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            point.icon,
            size: 17,
            color: const Color(0xFF6F39E8),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                point.title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1F2330),
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                point.body,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: Color(0xFF5B5E6B),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DisclaimerPoint {
  const _DisclaimerPoint({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}