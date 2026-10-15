import 'package:flutter/material.dart';

import '../../widgets/mindsync_logo.dart';

/// Two intro slides shown once before the welcome screen (first install).
class FirstLaunchCarouselScreen extends StatefulWidget {
  const FirstLaunchCarouselScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<FirstLaunchCarouselScreen> createState() =>
      _FirstLaunchCarouselScreenState();
}

class _FirstLaunchCarouselScreenState extends State<FirstLaunchCarouselScreen> {
  final PageController _controller = PageController();
  int _page = 0;

  static const _slides = [
    (
      title: 'Understand your digital rhythm',
      body:
          'MindSync connects screen time, mood, and face insights so you can spot patterns early.',
      icon: Icons.insights_rounded,
    ),
    (
      title: 'Wellness that works with you',
      body:
          'Gentle nudges, optional parental tools, and AI chat — built around your privacy and control.',
      icon: Icons.favorite_rounded,
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < _slides.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    } else {
      widget.onFinished();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEDE8FA),
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: widget.onFinished,
                child: const Text(
                  'Skip',
                  style: TextStyle(
                    color: Color(0xFF6F39E8),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const MindSyncLogo(height: 72, width: 120),
            const SizedBox(height: 8),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, index) {
                  final slide = _slides[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          slide.icon,
                          size: 64,
                          color: const Color(0xFF6F39E8),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          slide.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF2B2D39),
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          slide.body,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 15,
                            height: 1.45,
                            color: Color(0xFF686A76),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _slides.length,
                (i) => Container(
                  width: _page == i ? 22 : 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: _page == i
                        ? const Color(0xFF6F39E8)
                        : const Color(0xFFD9D7E4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  onPressed: _next,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF6F39E8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(40),
                    ),
                  ),
                  child: Text(
                    _page < _slides.length - 1 ? 'Next' : 'Get started',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
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
