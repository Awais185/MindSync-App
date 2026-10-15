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
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                child: Column(
                  children: [
                    const SizedBox(height: 4),

                    const SizedBox(
                      height: 100,
                      width: 150,
                      child: MindSyncLogo(height: 90, width: 140),
                    ),

                    const SizedBox(height: 10),

                    ValueListenableBuilder<AppBrandingData>(
                      valueListenable: publicService.branding,
                      builder: (context, branding, _) => Text(
                        branding.welcomeTagline,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Color(0xFF686A76),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),

                    const SizedBox(height: 28),

                    Container(
                      width: 60,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD9D7E4),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),

                    const SizedBox(height: 24),

                    const Text(
                      'Before you begin',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1F2330),
                        height: 1.2,
                      ),
                    ),

                    const SizedBox(height: 8),

                    const Text(
                      'Please read and acknowledge this important notice',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF686A76),
                        fontWeight: FontWeight.w500,
                      ),
                    ),

                    const SizedBox(height: 24),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF3E8FF),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.info_outline_rounded,
                                  color: Color(0xFF6F39E8),
                                  size: 16,
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                'IMPORTANT DISCLAIMER',
                                style: TextStyle(
                                  letterSpacing: 1.2,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                  color: Color(0xFF6F39E8),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'MindSync uses AI to analyze behavioral patterns and provide '
                            'mental wellness insights. The results are generated by machine '
                            'learning models and, although designed for high accuracy, they '
                            'may not always be accurate or complete.',
                            style: TextStyle(
                              fontSize: 15,
                              height: 1.5,
                              color: Color(0xFF2B2D39),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text.rich(
                            TextSpan(
                              style: const TextStyle(
                                fontSize: 15,
                                height: 1.5,
                                color: Color(0xFF2B2D39),
                                fontWeight: FontWeight.w500,
                              ),
                              children: const [
                                TextSpan(text: 'MindSync is '),
                                TextSpan(
                                  text: 'not a medical or diagnostic tool',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                                TextSpan(
                                  text:
                                      ' and does not provide professional medical advice, '
                                      'diagnosis, or treatment. If you have concerns about '
                                      'your mental health, please consult a qualified '
                                      'healthcare professional.',
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'By continuing, you acknowledge that MindSync\'s insights are '
                            'intended to support self-awareness and should not replace '
                            'professional judgment.',
                            style: TextStyle(
                              fontSize: 15,
                              height: 1.5,
                              color: Color(0xFF2B2D39),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    Material(
                      color: Colors.white.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        onTap: () => setState(() => _agreed = !_agreed),
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
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
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'I have read and agree to the disclaimer above. '
                                  'I understand that MindSync insights are informational only.',
                                  style: TextStyle(
                                    fontSize: 14,
                                    height: 1.45,
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

                    const SizedBox(height: 28),

                    SizedBox(
                      width: double.infinity,
                      height: 60,
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
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                            SizedBox(width: 12),
                            Icon(Icons.arrow_forward_rounded, size: 20),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
