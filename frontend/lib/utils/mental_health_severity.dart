import 'package:flutter/material.dart';

/// Rule-based severity labels for mental health percentage scores (0–100).
///
/// 0–49% → Normal
/// 50–69% → Mild
/// 70–84% → Moderate
/// 85–100% → High
class MentalHealthSeverity {
  MentalHealthSeverity._();

  static const Color percentTextColor = Color(0xFF1A2130);
  static const Color progressBarColor = Color(0xFF1A2130);
  static const Color progressBarBackground = Color(0xFFEFF0F5);

  /// Home App Usage progress track — shared by Mental Health Insights bars.
  static const double homeProgressBarMinHeight = 5;
  static const double homeProgressBarBorderRadius = 10;

  /// Distinct fill colors for Home Mental Health Insights (Stress / Anxiety / Depression).
  static const Color stressInsightBarColor = Color(0xFF3B82F6);
  static const Color anxietyInsightBarColor = Color(0xFF14B8A6);
  static const Color depressionInsightBarColor = Color(0xFFF59E0B);

  static double _clampPercent(num percent) =>
      percent.toDouble().clamp(0.0, 100.0);

  static String labelFromPercent(num percent) {
    final p = _clampPercent(percent);
    if (p >= 85) return 'High';
    if (p >= 70) return 'Moderate';
    if (p >= 50) return 'Mild';
    return 'Normal';
  }

  static int percentRounded(num percent) => _clampPercent(percent).round();

  /// Plain string without arrow: `75% Moderate`.
  static String displayFromPercent(num percent) {
    final rounded = percentRounded(percent);
    return '$rounded% ${labelFromPercent(rounded)}';
  }

  static String displayFromPercentOrNull(num? percent) {
    if (percent == null) return 'No data';
    return displayFromPercent(percent);
  }

  /// Severity label color — red family only (High = strong, others = lighter red).
  static Color labelColorFromPercent(num percent) {
    switch (labelFromPercent(percent)) {
      case 'High':
        return const Color(0xFFB3261E);
      case 'Moderate':
        return const Color(0xFFE57373);
      case 'Mild':
        return const Color(0xFFEF9A9A);
      default:
        return const Color(0xFFFFCDD2);
    }
  }

  static const double labelGap = 2;

  static TextSpan scoreTextSpan(
    num percent, {
    double fontSize = 13,
    FontWeight fontWeight = FontWeight.w600,
    FontWeight labelFontWeight = FontWeight.w800,
    Color? percentColor,
  }) {
    final rounded = percentRounded(percent);
    final label = labelFromPercent(percent);
    return TextSpan(
      style: TextStyle(fontSize: fontSize, height: 1.15),
      children: [
        TextSpan(
          text: '$rounded%',
          style: TextStyle(
            fontWeight: fontWeight,
            color: percentColor ?? percentTextColor,
          ),
        ),
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: SizedBox(width: labelGap),
        ),
        TextSpan(
          text: label,
          style: TextStyle(
            fontWeight: labelFontWeight,
            color: labelColorFromPercent(percent),
          ),
        ),
      ],
    );
  }
}

/// Percent in dark text; severity label in red tone (bolder weight).
class MentalHealthScoreDisplay extends StatelessWidget {
  const MentalHealthScoreDisplay({
    super.key,
    required this.percent,
    this.fontSize = 13,
    this.fontWeight = FontWeight.w600,
    this.labelFontWeight = FontWeight.w800,
    this.maxLines = 1,
    this.textAlign,
  });

  final num percent;
  final double fontSize;
  final FontWeight fontWeight;
  final FontWeight labelFontWeight;
  final int? maxLines;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final rounded = MentalHealthSeverity.percentRounded(percent);
    final label = MentalHealthSeverity.labelFromPercent(percent);

    return Text.rich(
      TextSpan(
        style: TextStyle(fontSize: fontSize, height: 1.15),
        children: [
          TextSpan(
            text: '$rounded%',
            style: TextStyle(
              fontWeight: fontWeight,
              color: MentalHealthSeverity.percentTextColor,
            ),
          ),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: SizedBox(width: MentalHealthSeverity.labelGap),
          ),
          TextSpan(
            text: label,
            style: TextStyle(
              fontWeight: labelFontWeight,
              color: MentalHealthSeverity.labelColorFromPercent(percent),
            ),
          ),
        ],
      ),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: textAlign,
    );
  }
}
