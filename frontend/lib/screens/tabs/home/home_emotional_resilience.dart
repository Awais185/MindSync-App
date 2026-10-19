import 'package:flutter/material.dart';

import '../../../services/wellness_dashboard_service.dart';

/// 3-day segmented emotional resilience bar (inside Mental Health card).
class HomeEmotionalResilienceSegmentBar extends StatelessWidget {
  const HomeEmotionalResilienceSegmentBar({
    required this.days,
    this.compact = false,
  });

  final List<EmotionalResilienceDay> days;
  final bool compact;

  static Color _segmentColor(String tone, {required bool hasData}) {
    if (!hasData) return const Color(0xFFE8E9EF);
    switch (tone) {
      case 'positive':
        return const Color(0xFF37B48A);
      case 'stress':
        return const Color(0xFFE6A017);
      case 'low':
        return const Color(0xFF5B7FD6);
      default:
        return const Color(0xFF9B8EC4);
    }
  }

  @override
  Widget build(BuildContext context) {
    final slots = days.length >= kHomeWellnessWindowDays
        ? days.sublist(days.length - kHomeWellnessWindowDays)
        : days;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!compact) ...[
          const Text(
            'Emotional Resilience',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A2130),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '3-day rolling · emotion model from background video',
            style: TextStyle(
              fontSize: 11.5,
              color: Color(0xFF8A8D99),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < slots.length; i++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: i == 0 ? 0 : 4,
                    right: i == slots.length - 1 ? 0 : 4,
                  ),
                  child: Text(
                    slots[i].emotionLabel,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      color: slots[i].samples > 0
                          ? const Color(0xFF374151)
                          : const Color(0xFF9CA3AF),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 10,
          child: Row(
            children: [
              for (var i = 0; i < slots.length; i++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: i == 0 ? 0 : 2,
                      right: i == slots.length - 1 ? 0 : 2,
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: _segmentColor(
                          slots[i].tone,
                          hasData: slots[i].samples > 0,
                        ),
                        borderRadius: BorderRadius.horizontal(
                          left: i == 0
                              ? const Radius.circular(6)
                              : Radius.zero,
                          right: i == slots.length - 1
                              ? const Radius.circular(6)
                              : Radius.zero,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < slots.length; i++)
              Expanded(
                child: Text(
                  slots[i].dayName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
