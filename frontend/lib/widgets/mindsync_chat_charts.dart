import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Parsed chart spec from chat API or embedded JSON blocks.
class MindSyncChartSpec {
  MindSyncChartSpec({
    required this.type,
    required this.title,
    required this.labels,
    required this.values,
    this.seriesLabel = '',
    this.series = const [],
  });

  final String type;
  final String title;
  final List<String> labels;
  final List<double> values;
  final String seriesLabel;
  final List<List<double>> series;

  factory MindSyncChartSpec.fromMap(Map<String, dynamic> map) {
    final labels =
        (map['labels'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList();
    final values =
        (map['values'] as List<dynamic>? ?? const [])
            .map((e) => (e as num?)?.toDouble() ?? 0)
            .toList();
    final rawSeries = map['series'] as List<dynamic>? ?? const [];
    final series = rawSeries
        .whereType<List>()
        .map(
          (row) => row.map((e) => (e as num?)?.toDouble() ?? 0).toList(),
        )
        .toList();
    return MindSyncChartSpec(
      type: (map['type'] ?? 'bar').toString(),
      title: (map['title'] ?? 'Chart').toString(),
      labels: labels,
      values: values,
      seriesLabel: (map['series_label'] ?? '').toString(),
      series: series,
    );
  }

  static List<MindSyncChartSpec> listFromDynamic(List<dynamic>? raw) {
    if (raw == null) return const [];
    return raw
        .whereType<Map>()
        .map((e) => MindSyncChartSpec.fromMap(Map<String, dynamic>.from(e)))
        .where((c) => c.labels.isNotEmpty && c.values.isNotEmpty)
        .toList();
  }
}

class MindSyncChatChartCard extends StatelessWidget {
  const MindSyncChatChartCard({super.key, required this.spec});

  final MindSyncChartSpec spec;

  static const _accent = Color(0xFF6F39E8);
  static const _secondary = Color(0xFF0E9186);
  static const _tertiary = Color(0xFF2E6FD2);
  static const _muted = Color(0xFF8A8D99);
  static const _cardBg = Color(0xFFF9F9FC);

  static const _palette = [
    _accent,
    _secondary,
    _tertiary,
    Color(0xFFE09100),
    Color(0xFFB3261E),
    Color(0xFF4A6FA5),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            spec.title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF20222B),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: spec.type == 'donut' ? 180 : 160,
            width: double.infinity,
            child: switch (spec.type) {
              'line' => _LineChartBody(spec: spec),
              'donut' => _DonutChartBody(spec: spec, palette: _palette),
              _ => _BarChartBody(spec: spec, palette: _palette),
            },
          ),
          if (spec.type == 'donut') ...[
            const SizedBox(height: 8),
            _DonutLegend(spec: spec, palette: _palette),
          ],
        ],
      ),
    );
  }
}

class _BarChartBody extends StatelessWidget {
  const _BarChartBody({required this.spec, required this.palette});
  final MindSyncChartSpec spec;
  final List<Color> palette;

  @override
  Widget build(BuildContext context) {
    final maxV = spec.values.isEmpty
        ? 1.0
        : spec.values.reduce(math.max).clamp(0.01, double.infinity);
    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(spec.labels.length, (i) {
              final v = i < spec.values.length ? spec.values[i] : 0.0;
              final color = palette[i % palette.length];
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        height: (v / maxV * 100).clamp(4, 100),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: List.generate(spec.labels.length, (i) {
            return Expanded(
              child: Text(
                spec.labels[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: MindSyncChatChartCard._muted),
              ),
            );
          }),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '0',
              style: TextStyle(fontSize: 11, color: MindSyncChatChartCard._muted),
            ),
            Text(
              maxV.toStringAsFixed(maxV >= 10 ? 0 : 1),
              style: TextStyle(fontSize: 11, color: MindSyncChatChartCard._muted),
            ),
          ],
        ),
      ],
    );
  }
}

class _LineChartBody extends StatelessWidget {
  const _LineChartBody({required this.spec});
  final MindSyncChartSpec spec;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LineChartPainter(
        labels: spec.labels,
        values: spec.values,
        lineColor: MindSyncChatChartCard._accent,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({
    required this.labels,
    required this.values,
    required this.lineColor,
  });

  final List<String> labels;
  final List<double> values;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxV = values.reduce(math.max).clamp(0.01, double.infinity);
    final minV = values.reduce(math.min);
    final range = (maxV - minV).clamp(0.01, double.infinity);

    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = const Color(0xFF8A8D99).withValues(alpha: 0.12)
          ..strokeWidth = 1,
      );
    }

    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1
          ? size.width / 2
          : (size.width * i / (values.length - 1));
      final norm = (values[i] - minV) / range;
      final y = size.height - (norm * (size.height - 16)) - 8;
      points.add(Offset(x, y));
    }

    if (points.length >= 2) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (var i = 0; i < points.length - 1; i++) {
        final p0 = points[i];
        final p1 = points[i + 1];
        final cx = (p0.dx + p1.dx) / 2;
        path.cubicTo(cx, p0.dy, cx, p1.dy, p1.dx, p1.dy);
      }
      final fill = Path.from(path)
        ..lineTo(points.last.dx, size.height)
        ..lineTo(points.first.dx, size.height)
        ..close();
      canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              lineColor.withValues(alpha: 0.15),
              lineColor.withValues(alpha: 0.02),
            ],
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = lineColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round,
      );
    }

    for (final p in points) {
      canvas.drawCircle(p, 4, Paint()..color = lineColor);
      canvas.drawCircle(p, 2, Paint()..color = Colors.white);
    }

    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i < labels.length; i++) {
      if (i >= points.length) break;
      tp.text = TextSpan(
        text: labels[i],
        style: const TextStyle(fontSize: 10, color: Color(0xFF8A8D99)),
      );
      tp.layout(maxWidth: size.width / labels.length);
      tp.paint(
        canvas,
        Offset(
          (points[i].dx - tp.width / 2).clamp(0, size.width - tp.width),
          size.height - 14,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) => true;
}

class _DonutChartBody extends StatelessWidget {
  const _DonutChartBody({required this.spec, required this.palette});
  final MindSyncChartSpec spec;
  final List<Color> palette;

  @override
  Widget build(BuildContext context) {
    final total = spec.values.fold<double>(0, (a, b) => a + b);
    final dominantIdx = spec.values.isEmpty
        ? 0
        : spec.values.indexWhere((v) => v == spec.values.reduce(math.max));
    final dominantLabel = spec.labels[dominantIdx.clamp(0, spec.labels.length - 1)];
    final pct = total <= 0 ? 0.0 : (spec.values[dominantIdx] / total * 100);

    return CustomPaint(
      painter: _DonutPainter(values: spec.values, palette: palette),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              dominantLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF20222B),
              ),
            ),
            Text(
              '${pct.toStringAsFixed(0)}%',
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF8A8D99),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.values, required this.palette});
  final List<double> values;
  final List<Color> palette;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return;
    final rect = Rect.fromLTWH(8, 8, size.width - 16, size.height - 16);
    var start = -math.pi / 2;
    const gap = 0.04;
    for (var i = 0; i < values.length; i++) {
      final sweep = (values[i] / total) * (2 * math.pi - gap * values.length);
      canvas.drawArc(
        rect,
        start,
        sweep,
        true,
        Paint()
          ..color = palette[i % palette.length]
          ..style = PaintingStyle.fill,
      );
      start += sweep + gap;
    }
    canvas.drawCircle(
      rect.center,
      rect.width * 0.28,
      Paint()..color = MindSyncChatChartCard._cardBg,
    );
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) => true;
}

class _DonutLegend extends StatelessWidget {
  const _DonutLegend({required this.spec, required this.palette});
  final MindSyncChartSpec spec;
  final List<Color> palette;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: List.generate(spec.labels.length, (i) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: palette[i % palette.length],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              spec.labels[i],
              style: const TextStyle(fontSize: 11, color: Color(0xFF8A8D99)),
            ),
          ],
        );
      }),
    );
  }
}
