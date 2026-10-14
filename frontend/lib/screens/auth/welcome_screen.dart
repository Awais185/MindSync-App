import 'package:flutter/material.dart';
import '../../services/app_public_service.dart';
import '../../widgets/mindsync_logo.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, required this.onGetStarted});

  final VoidCallback onGetStarted;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  late final AppPublicService _publicService;

  @override
  void initState() {
    super.initState();
    _publicService = AppPublicService.instance;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEDE8FA),
      body: SafeArea(
        child: Stack(
          children: [
            // Skip Button
            Positioned(
              top: 16,
              right: 20,
              child: TextButton(
                onPressed: widget.onGetStarted,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: const Text(
                  'Skip',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6F39E8),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),

            // Main Content
            LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                    child: Column(
                      children: [
                        const SizedBox(height: 4),

                        // Dynamic backend logo
                        const SizedBox(
                          height: 100,
                          width: 150,
                          child: MindSyncLogo(height: 90, width: 140),
                        ),

                        const SizedBox(height: 10),

                        // Subtitle
                        ValueListenableBuilder<AppBrandingData>(
                          valueListenable: _publicService.branding,
                          builder: (context, branding, child) => Text(
                            branding.welcomeTagline,
                            style: const TextStyle(
                              fontSize: 16,
                              color: Color(0xFF686A76),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),

                        const SizedBox(height: 36),

                        // Divider line
                        Container(
                          width: 60,
                          height: 5,
                          decoration: BoxDecoration(
                            color: const Color(0xFFD9D7E4),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),

                        const SizedBox(height: 28),

                        // Personalized Insight Card
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(32),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.04),
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
                                      color: const Color(0xFFE8F0FE),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.auto_awesome,
                                      color: Color(0xFF3A74D9),
                                      size: 16,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  const Text(
                                    'PERSONALIZED INSIGHT',
                                    style: TextStyle(
                                      letterSpacing: 1.2,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 11,
                                      color: Color(0xFF2E5FB8),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              const Text(
                                '"The first step towards wellness is understanding the rhythm of your heart and mind."',
                                style: TextStyle(
                                  fontSize: 15,
                                  height: 1.45,
                                  color: Color(0xFF2B2D39),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Next → disclaimer step
                        SizedBox(
                          width: double.infinity,
                          height: 60,
                          child: ElevatedButton(
                            onPressed: widget.onGetStarted,
                            style: ElevatedButton.styleFrom(
                              elevation: 0,
                              foregroundColor: Colors.white,
                              backgroundColor: const Color(0xFF6F39E8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(40),
                              ),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Next',
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

                        const SizedBox(height: 20),

                        // Terms of Service Text
                        const Text(
                          'By continuing, you agree to our Terms of Service',
                          style: TextStyle(
                            color: Color(0xFF8E909C),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),

                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
