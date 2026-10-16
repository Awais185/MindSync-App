import 'package:flutter/material.dart';

class OnboardingGradientBackground extends StatelessWidget {
  const OnboardingGradientBackground({
    super.key,
    required this.child,
    this.variant = OnboardingBgVariant.lavender,
  });

  final Widget child;
  final OnboardingBgVariant variant;

  @override
  Widget build(BuildContext context) {
    final List<Color> colors;
    switch (variant) {
      case OnboardingBgVariant.lavender:
        colors = const [
          Color(0xFFF8F6FF),
          Color(0xFFEEF6FF),
          Color(0xFFF3F0FF),
        ];
      case OnboardingBgVariant.mint:
        colors = const [
          Color(0xFFE8FAF9),
          Color(0xFFF5F3FF),
          Color(0xFFFDFEFF),
        ];
      case OnboardingBgVariant.softWhite:
        colors = const [
          Color(0xFFFAFBFF),
          Color(0xFFF0F4FF),
          Color(0xFFF8F5FF),
        ];
    }

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: child,
    );
  }
}

enum OnboardingBgVariant { lavender, mint, softWhite }

class OnboardingPrimaryButton extends StatelessWidget {
  const OnboardingPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          gradient: const LinearGradient(
            colors: [Color(0xFF7C4DFF), Color(0xFF6F39E8)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6F39E8).withValues(alpha: 0.35),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(32),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

class OnboardingPageDots extends StatelessWidget {
  const OnboardingPageDots({
    super.key,
    required this.count,
    required this.activeIndex,
  });

  final int count;
  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == activeIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: active ? 28 : 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF6F39E8) : const Color(0xFFD9D7E4),
            borderRadius: BorderRadius.circular(8),
          ),
        );
      }),
    );
  }
}

class OnboardingPillBadge extends StatelessWidget {
  const OnboardingPillBadge({
    super.key,
    required this.label,
    this.leading,
    this.icon,
  });

  final String label;
  final Widget? leading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 8),
          ] else if (icon != null) ...[
            Icon(icon, size: 16, color: const Color(0xFF6F39E8)),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF4B5563),
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class OnboardingSignInLink extends StatelessWidget {
  const OnboardingSignInLink({
    super.key,
    required this.onSignIn,
    this.prefix = 'Already have an account? ',
  });

  final VoidCallback onSignIn;
  final String prefix;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSignIn,
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF6B7280),
            fontWeight: FontWeight.w500,
          ),
          children: [
            TextSpan(text: prefix),
            const TextSpan(
              text: 'Sign in',
              style: TextStyle(
                color: Color(0xFF6F39E8),
                fontWeight: FontWeight.w800,
                decoration: TextDecoration.underline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
