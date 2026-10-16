import 'package:flutter/material.dart';

import 'onboarding_splash_page_one.dart';
import 'onboarding_splash_page_three.dart';
import 'onboarding_splash_page_two.dart';

/// Three-screen first-launch onboarding (replaces legacy carousel + welcome landing).
class OnboardingSplashFlow extends StatefulWidget {
  const OnboardingSplashFlow({
    super.key,
    required this.onFinished,
    required this.onSignIn,
  });

  final VoidCallback onFinished;
  final VoidCallback onSignIn;

  @override
  State<OnboardingSplashFlow> createState() => _OnboardingSplashFlowState();
}

class _OnboardingSplashFlowState extends State<OnboardingSplashFlow> {
  final PageController _controller = PageController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    _controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _controller,
        physics: const ClampingScrollPhysics(),
        children: [
          OnboardingSplashPageOne(
            onGetStarted: () => _goTo(1),
            onSignIn: widget.onSignIn,
          ),
          OnboardingSplashPageTwo(
            onSkip: widget.onFinished,
            onContinue: () => _goTo(2),
            onSignIn: widget.onSignIn,
            pageIndex: 1,
          ),
          OnboardingSplashPageThree(
            onContinue: widget.onFinished,
            pageIndex: 2,
          ),
        ],
      ),
    );
  }
}
