import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/seven_day_studio_report.dart';
import '../../utils/mental_health_severity.dart';

/// Sample-matched light report theme (white canvas).
abstract final class ReportStudioTheme {
  static const bg = Color(0xFFFFFFFF);
  static const card = Color(0xFFFFFFFF);
  static const cardMuted = Color(0xFFF3F5F9);
  static const border = Color(0xFFE8ECF2);
  static const purple = Color(0xFF6F39E8);
  static const purpleDark = Color(0xFF5A2FD4);
  static const ink = Color(0xFF1A1D26);
  static const muted = Color(0xFF8B95A8);
  static const good = Color(0xFF22C55E);
  static const stable = Color(0xFF3B82F6);
  static const teal = Color(0xFF14B8A6);
  static const warning = Color(0xFFF59E0B);
  static const risk = Color(0xFFEF4444);
  static const riskBannerBg = Color(0xFF1B4332);
  static const riskBannerFg = Color(0xFFD8F3DC);

  static Color statusColor(String status) {
    final s = status.toLowerCase();
    if (s.contains('good') || s.contains('positive')) return good;
    if (s.contains('stable') || s.contains('normal')) return stable;
    if (s.contains('moderate')) return stable;
    if (s.contains('warning')) return warning;
    if (s.contains('risk') || s.contains('high')) return risk;
    return muted;
  }
}

/// Keeps report narrow on web/tablet — matches phone sample proportions.
abstract final class ReportLayout {
  static const maxWidth = 400.0;
  static const hPad = 20.0;
  static const sectionGap = 10.0;
}

class ReportWidthShell extends StatelessWidget {
  const ReportWidthShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    final innerW = math.min(screenW, ReportLayout.maxWidth);
    return SizedBox(
      width: screenW,
      child: Center(
        child: SizedBox(
          width: innerW,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: ReportLayout.hPad),
            child: child,
          ),
        ),
      ),
    );
  }
}

class StitchCard extends StatelessWidget {
  const StitchCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.color,
  });
  final Widget child;
  final EdgeInsets padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? ReportStudioTheme.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ReportStudioTheme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

class StitchSectionTitle extends StatelessWidget {
  const StitchSectionTitle(this.text, {super.key, this.subtitle});
  final String text;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: ReportStudioTheme.muted,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 3),
          Text(subtitle!, style: const TextStyle(fontSize: 10, color: ReportStudioTheme.muted)),
        ],
      ],
    );
  }
}

class StitchStatusBadge extends StatelessWidget {
  const StitchStatusBadge(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = ReportStudioTheme.statusColor(label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: c),
      ),
    );
  }
}

class StitchHeroCard extends StatelessWidget {
  const StitchHeroCard({super.key, required this.report});
  final SevenDayStudioReport report;

  @override
  Widget build(BuildContext context) {
    final s = report.summary;
    final wellbeing = s.wellbeingScore;
    final wellness = s.mentalWellnessIndex;
    final moodLabel = s.moodStatus.toUpperCase();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [ReportStudioTheme.purple, ReportStudioTheme.purpleDark],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'LAST 7 DAYS · MINDSYNC REPORT',
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            wellbeing?.toString() ?? '—',
                            style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              height: 1,
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.only(bottom: 4, left: 2),
                            child: Text('/100', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text('Wellbeing score', style: TextStyle(color: Colors.white70, fontSize: 11)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    wellness?.toString() ?? '—',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const Text('/100', style: TextStyle(color: Colors.white70, fontSize: 9)),
                  Text(
                    'WELLNESS INDEX',
                    style: TextStyle(fontSize: 7, color: Colors.white.withValues(alpha: 0.8)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          _heroBar('Stress', s.stress, MentalHealthSeverity.stressInsightBarColor),
          const SizedBox(height: 8),
          _heroBar('Anxiety', s.anxiety, MentalHealthSeverity.anxietyInsightBarColor),
          const SizedBox(height: 8),
          _heroBar('Depression', s.depression, MentalHealthSeverity.depressionInsightBarColor),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(color: Color(0xFF93C5FD), shape: BoxShape.circle),
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    moodLabel,
                    style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroBar(String label, int? value, Color color) {
    final v = (value ?? 0).clamp(0, 100);
    final frac = v / 100.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 9, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Text(
              value != null ? MentalHealthSeverity.displayFromPercent(v) : 'No data',
              style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: value != null ? frac : 0,
            minHeight: 5,
            backgroundColor: Colors.white.withValues(alpha: 0.22),
            color: color,
          ),
        ),
      ],
    );
  }
}

class StitchSixTileGrid extends StatelessWidget {
  const StitchSixTileGrid({
    super.key,
    required this.contentChild,
    required this.insightsChild,
    required this.cards,
  });
  final Widget contentChild;
  final Widget insightsChild;
  final StudioMetricCards cards;

  @override
  Widget build(BuildContext context) {
    final metrics = [cards.avgScreen, cards.mood, cards.sleep, cards.wellbeing];
    const gap = 8.0;
    return LayoutBuilder(
      builder: (context, c) {
        final tileW = (c.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            _tile(tileW, 'Content Type', contentChild, minH: 76),
            _tile(tileW, 'Mental Insights', insightsChild, minH: 76),
            ...metrics.map((m) => _metricTile(tileW, m)),
          ],
        );
      },
    );
  }

  Widget _tile(double width, String title, Widget body, {double minH = 72}) {
    return SizedBox(
      width: width,
      child: StitchCard(
        padding: const EdgeInsets.all(11),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minH),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.toUpperCase(),
                style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: ReportStudioTheme.muted),
              ),
              const SizedBox(height: 8),
              body,
            ],
          ),
        ),
      ),
    );
  }

  Widget _metricTile(double width, StudioMetricCard card) {
    return SizedBox(
      width: width,
      child: StitchCard(
        padding: const EdgeInsets.all(11),
        child: SizedBox(
          height: 76,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                card.label.toUpperCase(),
                style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: ReportStudioTheme.muted),
              ),
              const Spacer(),
              Text(
                card.display,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: ReportStudioTheme.ink),
              ),
              const SizedBox(height: 4),
              StitchStatusBadge(card.status),
            ],
          ),
        ),
      ),
    );
  }
}

class StitchBarChart extends StatelessWidget {
  const StitchBarChart({
    super.key,
    required this.values,
    required this.labels,
    this.barColor = ReportStudioTheme.purple,
    this.maxValue,
    this.height = 88,
  });
  final List<double> values;
  final List<String> labels;
  final Color barColor;
  final double? maxValue;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return const StitchEmptyText('No trend data');
    }
    final maxV = maxValue ?? values.fold<double>(0, math.max).clamp(0.1, double.infinity);
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(values.length, (i) {
          final h = (values[i] / maxV).clamp(0.04, 1.0);
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: h,
                        widthFactor: 0.55,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: barColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    i < labels.length ? labels[i] : '',
                    style: const TextStyle(fontSize: 8, color: ReportStudioTheme.muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class StitchRadialScore extends StatelessWidget {
  const StitchRadialScore({super.key, required this.score});
  final int? score;

  @override
  Widget build(BuildContext context) {
    final v = (score ?? 0) / 100.0;
    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: v.clamp(0.0, 1.0),
            strokeWidth: 6,
            backgroundColor: ReportStudioTheme.cardMuted,
            color: ReportStudioTheme.purple,
          ),
          Text(score?.toString() ?? '—', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class StitchEmptyText extends StatelessWidget {
  const StitchEmptyText(this.message, {super.key});
  final String message;
  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: const TextStyle(fontSize: 10, color: ReportStudioTheme.muted, height: 1.3),
    );
  }
}

class StitchMentalStateChart extends StatelessWidget {
  const StitchMentalStateChart({super.key, required this.days, this.footer});
  final List<StudioDailyMental> days;
  final String? footer;

  static const _stressColor = MentalHealthSeverity.stressInsightBarColor;
  static const _anxietyColor = MentalHealthSeverity.anxietyInsightBarColor;
  static const _depressionColor = MentalHealthSeverity.depressionInsightBarColor;

  List<StudioDailyMental> get _normalizedDays {
    if (days.length >= 7) return days.take(7).toList();
    final padded = List<StudioDailyMental>.from(days);
    while (padded.length < 7) {
      final i = padded.length;
      padded.add(
        StudioDailyMental(
          date: '',
          dayLabel: 'D${i + 1}',
          stress: null,
          anxiety: null,
          depression: null,
        ),
      );
    }
    return padded;
  }

  String _xLabel(StudioDailyMental d, int index) {
    if (d.date.length >= 10) {
      try {
        final dt = DateTime.parse(d.date);
        const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        return names[dt.weekday - 1];
      } catch (_) {}
    }
    final lbl = d.dayLabel.trim();
    if (lbl.isNotEmpty) {
      if (lbl.length <= 3) return lbl;
      if (lbl.startsWith('Day')) return 'D${index + 1}';
    }
    return 'D${index + 1}';
  }

  bool get _hasAnyData =>
      _normalizedDays.any((d) => d.stress != null || d.anxiety != null || d.depression != null);

  @override
  Widget build(BuildContext context) {
    final week = _normalizedDays;
    if (!_hasAnyData) {
      return const StitchEmptyText('No daily mental health scores for this week yet.');
    }

    final stressPts = week.map((d) => d.stress?.toDouble()).toList();
    final anxietyPts = week.map((d) => d.anxiety?.toDouble()).toList();
    final depressionPts = week.map((d) => d.depression?.toDouble()).toList();
    final xLabels = List.generate(week.length, (i) => _xLabel(week[i], i));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 6,
          children: const [
            _ChartLegendDot(label: 'Stress', color: _stressColor),
            _ChartLegendDot(label: 'Anxiety', color: _anxietyColor),
            _ChartLegendDot(label: 'Depression', color: _depressionColor),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 172,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _ChartYAxis(),
              const SizedBox(width: 6),
              Expanded(
                child: CustomPaint(
                  painter: _MentalStateAxesPainter(
                    stress: stressPts,
                    anxiety: anxietyPts,
                    depression: depressionPts,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(left: 34),
          child: Row(
            children: xLabels
                .map(
                  (l) => Expanded(
                    child: Text(
                      l,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: ReportStudioTheme.muted),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 2),
        const Padding(
          padding: EdgeInsets.only(left: 34),
          child: Text(
            'X-axis: last 7 days  ·  Y-axis: score (0–100%)',
            style: TextStyle(fontSize: 8, color: ReportStudioTheme.muted),
          ),
        ),
        if (footer != null && footer!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(footer!, style: const TextStyle(fontSize: 9, color: ReportStudioTheme.muted)),
        ],
      ],
    );
  }
}

class _ChartLegendDot extends StatelessWidget {
  const _ChartLegendDot({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: ReportStudioTheme.ink)),
      ],
    );
  }
}

class _ChartYAxis extends StatelessWidget {
  const _ChartYAxis();

  @override
  Widget build(BuildContext context) {
    const labels = ['100', '75', '50', '25', '0'];
    return SizedBox(
      width: 28,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: labels
            .map(
              (l) => Text(
                l,
                style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: ReportStudioTheme.muted),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _MentalStateAxesPainter extends CustomPainter {
  _MentalStateAxesPainter({
    required this.stress,
    required this.anxiety,
    required this.depression,
  });

  final List<double?> stress;
  final List<double?> anxiety;
  final List<double?> depression;

  @override
  void paint(Canvas canvas, Size size) {
    const gridColor = Color(0xFFE8ECF2);
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    for (var i = 0; i <= 4; i++) {
      final y = size.height * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    for (var i = 0; i < 7; i++) {
      final x = 7 <= 1 ? size.width / 2 : (i / 6) * size.width;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = gridColor.withValues(alpha: 0.55)
          ..strokeWidth = 1,
      );
    }

    _drawSeries(canvas, size, stress, MentalHealthSeverity.stressInsightBarColor);
    _drawSeries(canvas, size, anxiety, MentalHealthSeverity.anxietyInsightBarColor);
    _drawSeries(canvas, size, depression, MentalHealthSeverity.depressionInsightBarColor);
  }

  void _drawSeries(Canvas canvas, Size size, List<double?> data, Color color) {
    final n = data.length;
    if (n == 0) return;

    final points = <Offset>[];
    for (var i = 0; i < n; i++) {
      final v = data[i];
      if (v == null) continue;
      final x = n <= 1 ? size.width / 2 : (i / (n - 1)) * size.width;
      final y = size.height - (v.clamp(0, 100) / 100) * size.height;
      points.add(Offset(x, y));
    }

    if (points.length >= 2) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (var i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    for (var i = 0; i < n; i++) {
      final v = data[i];
      if (v == null) continue;
      final x = n <= 1 ? size.width / 2 : (i / (n - 1)) * size.width;
      final y = size.height - (v.clamp(0, 100) / 100) * size.height;
      final p = Offset(x, y);
      canvas.drawCircle(p, 4, Paint()..color = color);
      canvas.drawCircle(p, 2, Paint()..color = Colors.white);

      final tp = TextPainter(
        text: TextSpan(
          text: v.round().toString(),
          style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w800),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, math.max(0, y - 14)));
    }
  }

  @override
  bool shouldRepaint(covariant _MentalStateAxesPainter old) => true;
}

class StitchDailyTable extends StatelessWidget {
  const StitchDailyTable({super.key, required this.rows});
  final List<StudioDailySummaryRow> rows;

  @override
  Widget build(BuildContext context) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(1.1),
        1: FlexColumnWidth(1.4),
        2: FlexColumnWidth(0.9),
      },
      children: [
        const TableRow(
          children: [
            _Th('DAY'),
            _Th('SCREEN'),
            _Th('MOOD'),
          ],
        ),
        ...rows.map(
          (r) => TableRow(
            children: [
              _Td(r.day),
              _Td(r.screen),
              _Td(r.mood),
            ],
          ),
        ),
      ],
    );
  }
}

class _Th extends StatelessWidget {
  const _Th(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 2),
      child: Text(text, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: ReportStudioTheme.muted)),
    );
  }
}

class _Td extends StatelessWidget {
  const _Td(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(fontSize: 10, color: ReportStudioTheme.ink),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class StitchProgressRow extends StatelessWidget {
  const StitchProgressRow({
    super.key,
    required this.label,
    required this.percent,
    this.warning = false,
  });
  final String label;
  final int percent;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (warning)
                const Padding(
                  padding: EdgeInsets.only(right: 3),
                  child: Icon(Icons.warning_amber_rounded, size: 11, color: ReportStudioTheme.warning),
                ),
              Text('$percent%', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: (percent / 100).clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: ReportStudioTheme.cardMuted,
              color: warning ? ReportStudioTheme.warning : ReportStudioTheme.purple,
            ),
          ),
        ],
      ),
    );
  }
}

/// Sleep & trigger mood — weekday letters + dots (sample).
class StitchWeekdayDotStrip extends StatelessWidget {
  const StitchWeekdayDotStrip({super.key, this.labels = const ['M', 'T', 'W', 'T', 'F', 'S', 'S']});
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: labels
          .map(
            (l) => Expanded(
              child: Column(
                children: [
                  Text(l, style: const TextStyle(fontSize: 9, color: ReportStudioTheme.muted)),
                  const SizedBox(height: 6),
                  Container(
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(
                      color: ReportStudioTheme.muted,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

/// Mood over week — dashed placeholders (sample).
class StitchMoodWeekDashes extends StatelessWidget {
  const StitchMoodWeekDashes({super.key, this.count = 7});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(
        count,
        (_) => Expanded(
          child: Center(
            child: Container(
              width: 18,
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              color: ReportStudioTheme.border,
            ),
          ),
        ),
      ),
    );
  }
}

class StitchMetricsStatusRow extends StatelessWidget {
  const StitchMetricsStatusRow({super.key, required this.status});
  final StudioMetricsStatus status;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: [
        _pill('Normal', status.normal, ReportStudioTheme.stable),
        _pill('Positive', status.positive, ReportStudioTheme.good),
        _pill('Stable', status.stable, ReportStudioTheme.purple),
        _pill('Warning', status.warning, ReportStudioTheme.warning),
      ],
    );
  }

  Widget _pill(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 5, height: 5, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text('$label ($count)', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

class StitchRiskBanner extends StatelessWidget {
  const StitchRiskBanner({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: ReportStudioTheme.riskBannerBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: ReportStudioTheme.riskBannerFg, fontSize: 11, fontWeight: FontWeight.w500),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class StitchAiConfidenceCard extends StatelessWidget {
  const StitchAiConfidenceCard({super.key, required this.ai});
  final StudioAiConfidence ai;

  @override
  Widget build(BuildContext context) {
    return StitchCard(
      color: ReportStudioTheme.cardMuted,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StitchSectionTitle('AI Clinical Confidence'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              if (ai.emotion != null) _chip('Emotion: ${ai.emotion}%'),
              if (ai.behavior != null) _chip('Behavior: ${ai.behavior}%'),
              if (ai.risk != null) _chip('Risk: ${ai.risk}%'),
            ],
          ),
          if (ai.banner.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: ReportStudioTheme.purple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                ai.banner.toUpperCase(),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: ReportStudioTheme.purple),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: ReportStudioTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ReportStudioTheme.border),
      ),
      child: Text(text, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600)),
    );
  }
}

/// Visual week summary — stats, insight cards, and bars (not a text wall).
class StitchVisualSummaryCard extends StatelessWidget {
  const StitchVisualSummaryCard({super.key, required this.report});
  final SevenDayStudioReport report;

  List<String> get _insightBullets {
    final fromInsights = report.mentalHealthInsights
        .map((s) => s.trim())
        .where((s) => s.length > 12)
        .take(3)
        .toList();
    if (fromInsights.isNotEmpty) return fromInsights;

    final raw = report.clinicalSummary.trim();
    if (raw.isEmpty) return const [];
    return raw
        .split(RegExp(r'(?<=[.!?])\s+'))
        .map((s) => s.trim())
        .where((s) => s.length > 12)
        .take(4)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final s = report.summary;
    final bullets = _insightBullets;
    final screenHrs = s.screenOnMinutes > 0 ? (s.screenOnMinutes / 60).toStringAsFixed(1) : '—';

    return StitchCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome, size: 16, color: ReportStudioTheme.purple),
              SizedBox(width: 8),
              Text('Your Week at a Glance', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _statTile('Wellbeing', s.wellbeingScore?.toString() ?? '—', ReportStudioTheme.purple, Icons.favorite_rounded)),
              const SizedBox(width: 8),
              Expanded(child: _statTile('Screen', '${screenHrs}h', ReportStudioTheme.stable, Icons.smartphone_rounded)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _statTile('Video clips', '${s.analysedVideoChunks}', ReportStudioTheme.teal, Icons.videocam_rounded)),
              const SizedBox(width: 8),
              Expanded(
                child: _statTile(
                  'Mood',
                  _formatMood(s.moodStatus),
                  ReportStudioTheme.warning,
                  Icons.emoji_emotions_outlined,
                ),
              ),
            ],
          ),
          if (bullets.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'KEY INSIGHTS',
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: ReportStudioTheme.muted),
            ),
            const SizedBox(height: 8),
            ...bullets.asMap().entries.map((e) => _insightRow(e.key, e.value)),
          ],
          const SizedBox(height: 16),
          const Text(
            'CONDITION LEVELS (matches Home)',
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: ReportStudioTheme.muted),
          ),
          const SizedBox(height: 10),
          _summaryBar('Stress', s.stress, MentalHealthSeverity.stressInsightBarColor),
          const SizedBox(height: 8),
          _summaryBar('Anxiety', s.anxiety, MentalHealthSeverity.anxietyInsightBarColor),
          const SizedBox(height: 8),
          _summaryBar('Depression', s.depression, MentalHealthSeverity.depressionInsightBarColor),
        ],
      ),
    );
  }

  String _formatMood(String mood) {
    final m = mood.trim();
    if (m.isEmpty || m.toLowerCase() == 'no data') return '—';
    if (m.length <= 8) return m.toUpperCase();
    return '${m[0].toUpperCase()}${m.substring(1)}';
  }

  Widget _statTile(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(label, style: const TextStyle(fontSize: 9, color: ReportStudioTheme.muted, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _insightRow(int index, String text) {
    const icons = [Icons.lightbulb_outline, Icons.trending_up_rounded, Icons.health_and_safety_outlined, Icons.psychology_alt_outlined];
    final icon = icons[index % icons.length];
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ReportStudioTheme.cardMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: ReportStudioTheme.purple),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 12, height: 1.4, color: ReportStudioTheme.ink)),
          ),
        ],
      ),
    );
  }

  Widget _summaryBar(String label, int? value, Color color) {
    final v = value ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text(
              value != null ? MentalHealthSeverity.displayFromPercent(v) : 'No data',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: ReportStudioTheme.ink),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: value != null ? (v / 100).clamp(0.0, 1.0) : 0,
            minHeight: 7,
            backgroundColor: ReportStudioTheme.cardMuted,
            color: color,
          ),
        ),
      ],
    );
  }
}
