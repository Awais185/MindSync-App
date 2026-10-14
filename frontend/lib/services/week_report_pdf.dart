import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Optional sections mirroring on-screen report cards not covered by core metrics.
class WeekReportPdfExtras {
  const WeekReportPdfExtras({
    this.dateRangeLabel,
    this.mentalHealthSummary,
    this.contentTypeItems = const [],
    this.contentTypeDailyLines = const [],
    this.emotionPositive = 0,
    this.emotionNeutral = 0,
    this.emotionNegative = 0,
    this.hasEmotionData = false,
    this.riskSummary,
    this.riskAlertLines = const [],
    this.conditionDayLines = const [],
    this.conditionAveragesLine,
    this.clinicalSummary,
    this.dailyScreenSummary,
    this.dailyScreenInsight,
    this.deviceSummaryLine,
    this.appUsageBars = const [],
    this.aiInsightLines = const [],
    this.chunkScreenSummary,
    this.weekTotalHours,
    this.weekDailyAverageHours,
    this.lateNightByDayLabels = const [],
  });

  final String? dateRangeLabel;
  final String? mentalHealthSummary;
  final List<Map<String, dynamic>> contentTypeItems;
  final List<String> contentTypeDailyLines;
  final double emotionPositive;
  final double emotionNeutral;
  final double emotionNegative;
  final bool hasEmotionData;
  final String? riskSummary;
  final List<String> riskAlertLines;
  final List<String> conditionDayLines;
  final String? conditionAveragesLine;
  final String? clinicalSummary;
  final String? dailyScreenSummary;
  final String? dailyScreenInsight;
  final String? deviceSummaryLine;
  final List<MapEntry<String, double>> appUsageBars;
  final List<String> aiInsightLines;
  final String? chunkScreenSummary;
  final double? weekTotalHours;
  final double? weekDailyAverageHours;
  final List<String> lateNightByDayLabels;
}

/// Visual 7-day report PDF — mirrors in-app Report screen layout (cards + charts).
class WeekReportPdfBuilder {
  static PdfColor _hex(String hex) => PdfColor.fromHex(hex.replaceFirst('#', ''));

  static const _brand = '#4A6FA5';
  static const _accent = '#6F39E8';
  static const _ink = '#1A2C3E';
  static const _muted = '#6B7A8A';
  static const _border = '#E6E8EF';
  static const _screenBar = '#4A6FA5';
  static const _moodBar = '#9B6BB3';

  static const _cardFill = '#F7F8FA';

  static Future<Uint8List> build({
    required String name,
    required String email,
    required String? dynamicTitle,
    required String? dynamicBody,
    required int sleepQualityScore,
    required double dayScreenHours,
    required int lateNightWeekSeconds,
    required int lateNightOpensWeek,
    required List<int> lateNightByDaySeconds,
    required List<String> lateNightAppLines,
    required List<double> dailyScreenHours,
    required List<double> moodSeries,
    required int wellbeingScore,
    required int moodStability,
    required double socialMediaPercent,
    required double entertainmentPercent,
    required double educationalPercent,
    required double appSwitchingPercent,
    Map<String, dynamic>? serverReport,
    WeekReportPdfExtras extras = const WeekReportPdfExtras(),
  }) async {
    final doc = pw.Document();
    final generated =
        '${DateTime.now().toUtc().toIso8601String().split('.').first}Z';
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    String fmtHm(int sec) {
      if (sec <= 0) return '0m';
      final h = sec ~/ 3600;
      final m = (sec % 3600) ~/ 60;
      if (h <= 0) return '${m}m';
      return '${h}h ${m}m';
    }

    pw.Widget card(pw.Widget child, {PdfColor? fill}) {
      return pw.Container(
        width: double.infinity,
        margin: const pw.EdgeInsets.only(bottom: 10),
        padding: const pw.EdgeInsets.all(14),
        decoration: pw.BoxDecoration(
          color: fill ?? _hex(_cardFill),
          borderRadius: pw.BorderRadius.circular(14),
        ),
        child: child,
      );
    }

    pw.Widget sectionTitle(String text) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Text(
            text,
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: _hex(_ink),
            ),
          ),
        );

    pw.Widget bodyText(String text) => pw.Text(
          text,
          style: pw.TextStyle(fontSize: 11, height: 1.35, color: _hex(_muted)),
        );

    pw.Widget kpiBox(
      String label,
      String value,
      String unit,
      String status,
      PdfColor statusColor,
    ) {
      return pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: PdfColors.white,
            borderRadius: pw.BorderRadius.circular(12),
            border: pw.Border.all(color: _hex(_border)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(label, style: pw.TextStyle(fontSize: 9, color: _hex(_muted))),
              pw.SizedBox(height: 4),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    value,
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                      color: _hex(_ink),
                    ),
                  ),
                  if (unit.isNotEmpty)
                    pw.Text(
                      unit,
                      style: pw.TextStyle(fontSize: 8, color: _hex(_muted)),
                    ),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Text(
                  status,
                  style: pw.TextStyle(fontSize: 8, color: statusColor),
                ),
              ),
            ],
          ),
        ),
      );
    }

    pw.Widget barRow(
      List<double> values,
      List<String> labels,
      PdfColor color, {
      double maxHeight = 70,
    }) {
      final maxV = values.isEmpty ? 1.0 : values.reduce((a, b) => a > b ? a : b);
      return pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: List.generate(values.length, (i) {
          final v = values[i];
          final h = (v / (maxV + 0.01)) * maxHeight;
          return pw.Expanded(
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Container(
                  height: h.clamp(4, maxHeight),
                  width: 16,
                  decoration: pw.BoxDecoration(
                    color: color,
                    borderRadius: pw.BorderRadius.circular(3),
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  labels[i],
                  style: pw.TextStyle(fontSize: 7, color: _hex(_muted)),
                  textAlign: pw.TextAlign.center,
                ),
              ],
            ),
          );
        }),
      );
    }

    pw.Widget categoryBar(String label, double percent, PdfColor color) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(label, style: pw.TextStyle(fontSize: 9, color: _hex(_ink))),
              pw.Text(
                '${percent.toStringAsFixed(0)}%',
                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
              ),
            ],
          ),
          pw.SizedBox(height: 3),
          pw.Container(
            height: 6,
            decoration: pw.BoxDecoration(
              color: PdfColors.grey200,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Align(
              alignment: pw.Alignment.centerLeft,
              child: pw.Container(
                width: (percent / 100 * 480).clamp(0, 480),
                height: 6,
                decoration: pw.BoxDecoration(
                  color: color,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ],
      );
    }

    final dayStatus = dayScreenHours > 5
        ? 'High'
        : (dayScreenHours > 3 ? 'Moderate' : 'Good');
    final dayColor = dayScreenHours > 5
        ? _hex('#E65A4F')
        : (dayScreenHours > 3 ? _hex('#E6A017') : _hex('#2E8B57'));

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(16),
        build: (ctx) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: _hex(_brand),
              borderRadius: pw.BorderRadius.circular(14),
            ),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'MindSync',
                        style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        '7-Day Wellbeing Report',
                        style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 6),
                      pw.Text(
                        name,
                        style: const pw.TextStyle(color: PdfColors.white, fontSize: 12),
                      ),
                      if (email.isNotEmpty)
                        pw.Text(
                          email,
                          style: pw.TextStyle(
                            color: PdfColors.grey300,
                            fontSize: 9,
                          ),
                        ),
                      if (extras.dateRangeLabel != null &&
                          extras.dateRangeLabel!.trim().isNotEmpty)
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(top: 6),
                          child: pw.Text(
                            extras.dateRangeLabel!.trim(),
                            style: pw.TextStyle(
                              color: PdfColors.grey300,
                              fontSize: 10,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                pw.Text(
                  'Generated\n$generated',
                  style: pw.TextStyle(color: PdfColors.grey300, fontSize: 8),
                  textAlign: pw.TextAlign.right,
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 14),
          if (extras.deviceSummaryLine != null &&
              extras.deviceSummaryLine!.trim().isNotEmpty)
            card(
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  sectionTitle('Screen Time Summary'),
                  bodyText(extras.deviceSummaryLine!.trim()),
                  if (extras.weekTotalHours != null &&
                      extras.weekDailyAverageHours != null) ...[
                    pw.SizedBox(height: 6),
                    bodyText(
                      'Total: ${extras.weekTotalHours!.toStringAsFixed(1)} h · '
                      'Daily average: ${extras.weekDailyAverageHours!.toStringAsFixed(1)} h',
                    ),
                  ],
                  if (extras.chunkScreenSummary != null &&
                      extras.chunkScreenSummary!.trim().isNotEmpty) ...[
                    pw.SizedBox(height: 6),
                    bodyText(extras.chunkScreenSummary!.trim()),
                  ],
                ],
              ),
            ),
          if (extras.appUsageBars.isNotEmpty)
            card(
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  sectionTitle('App Usage Breakdown'),
                  ...extras.appUsageBars.take(8).map(
                        (entry) => pw.Padding(
                          padding: const pw.EdgeInsets.only(bottom: 6),
                          child: categoryBar(
                            entry.key,
                            entry.value,
                            _hex(_screenBar),
                          ),
                        ),
                      ),
                ],
              ),
            ),
          if (dynamicBody != null && dynamicBody.trim().isNotEmpty)
            card(
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    children: [
                      pw.Container(
                        width: 8,
                        height: 8,
                        decoration: pw.BoxDecoration(
                          color: _hex(_accent),
                          shape: pw.BoxShape.circle,
                        ),
                      ),
                      pw.SizedBox(width: 8),
                      pw.Text(
                        (dynamicTitle != null && dynamicTitle.trim().isNotEmpty)
                            ? dynamicTitle.trim()
                            : '7-day MindSync summary',
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                          color: _hex(_ink),
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    dynamicBody.trim(),
                    style: pw.TextStyle(fontSize: 11, height: 1.4, color: _hex(_muted)),
                  ),
                ],
              ),
              fill: _hex('#F4F0FF'),
            ),
          sectionTitle('Key metrics'),
          pw.Row(
            children: [
              kpiBox(
                'Avg Screen',
                dayScreenHours.toStringAsFixed(1),
                'h',
                dayStatus,
                dayColor,
              ),
              pw.SizedBox(width: 8),
              kpiBox(
                'Mood',
                '$moodStability',
                '',
                moodStability > 70 ? 'Stable' : 'Moderate',
                moodStability > 70 ? _hex('#2E8B57') : _hex('#E6A017'),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            children: [
              kpiBox(
                'Sleep',
                '$sleepQualityScore',
                '',
                sleepQualityScore > 70 ? 'Good' : 'Fair',
                sleepQualityScore > 70 ? _hex('#2E8B57') : _hex('#E6A017'),
              ),
              pw.SizedBox(width: 8),
              kpiBox(
                'Wellbeing',
                '$wellbeingScore',
                '',
                wellbeingScore > 70 ? 'Good' : 'Fair',
                wellbeingScore > 70 ? _hex('#2E8B57') : _hex('#E6A017'),
              ),
            ],
          ),
          card(
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    sectionTitle('Wellbeing Score'),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: pw.BoxDecoration(
                        color: _hex('#E8F5E9'),
                        borderRadius: pw.BorderRadius.circular(10),
                      ),
                      child: pw.Text(
                        wellbeingScore > 70 ? 'Good' : 'Fair',
                        style: pw.TextStyle(fontSize: 8, color: _hex('#2E8B57')),
                      ),
                    ),
                  ],
                ),
                pw.Text(
                  '$wellbeingScore / 100',
                  style: pw.TextStyle(
                    fontSize: 28,
                    fontWeight: pw.FontWeight.bold,
                    color: _hex(_brand),
                  ),
                ),
                pw.SizedBox(height: 8),
                categoryBar('Social Media', socialMediaPercent, _hex(_screenBar)),
                pw.SizedBox(height: 6),
                categoryBar('Entertainment', entertainmentPercent, _hex(_moodBar)),
                pw.SizedBox(height: 6),
                categoryBar('Educational', educationalPercent, _hex('#2E8B57')),
                pw.SizedBox(height: 6),
                categoryBar('App Switching', appSwitchingPercent, _hex('#E6A017')),
              ],
            ),
          ),
          card(
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                sectionTitle('Screen Time vs Mood'),
                barRow(
                  dailyScreenHours,
                  days.map((d) => d[0]).toList(),
                  _hex(_screenBar),
                ),
                pw.SizedBox(height: 6),
                barRow(
                  moodSeries,
                  days.map((d) => d[0]).toList(),
                  _hex(_moodBar),
                ),
                pw.SizedBox(height: 6),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Container(width: 10, height: 10, color: _hex(_screenBar)),
                    pw.SizedBox(width: 4),
                    pw.Text('Screen', style: pw.TextStyle(fontSize: 8)),
                    pw.SizedBox(width: 12),
                    pw.Container(width: 10, height: 10, color: _hex(_moodBar)),
                    pw.SizedBox(width: 4),
                    pw.Text('Mood', style: pw.TextStyle(fontSize: 8)),
                  ],
                ),
              ],
            ),
          ),
          card(
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                sectionTitle('Daily Screen Trend (hours)'),
                barRow(dailyScreenHours, days, _hex(_screenBar), maxHeight: 80),
              ],
            ),
          ),
          card(
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                sectionTitle('Mood Over the Week'),
                barRow(moodSeries, days, _hex(_moodBar), maxHeight: 80),
                if (extras.riskSummary != null &&
                    extras.riskSummary!.trim().isNotEmpty) ...[
                  pw.SizedBox(height: 8),
                  bodyText(extras.riskSummary!.trim()),
                ],
              ],
            ),
          ),
          if (extras.mentalHealthSummary != null &&
              extras.mentalHealthSummary!.trim().isNotEmpty)
            card(
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  sectionTitle('Behavioural Insights'),
                  bodyText(extras.mentalHealthSummary!.trim()),
                  if (extras.hasEmotionData) ...[
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'Emotional state distribution',
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: _hex(_ink),
                      ),
                    ),
                    pw.SizedBox(height: 6),
                    categoryBar('Positive', extras.emotionPositive, _hex('#2E8B57')),
                    pw.SizedBox(height: 4),
                    categoryBar('Neutral', extras.emotionNeutral, _hex(_screenBar)),
                    pw.SizedBox(height: 4),
                    categoryBar('Negative', extras.emotionNegative, _hex('#B3261E')),
                  ],
                ],
              ),
            ),
          if (extras.contentTypeItems.isNotEmpty)
            card(
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  sectionTitle('Content Watched Breakdown'),
                  ...extras.contentTypeItems.take(5).map((row) {
                    final label =
                        (row['label'] ?? row['category'] ?? 'Other').toString();
                    final pct = (row['percent'] as num?)?.toDouble() ?? 0;
                    return pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 4),
                      child: categoryBar(label, pct, _hex('#14B8A6')),
                    );
                  }),
                  if (extras.contentTypeDailyLines.isNotEmpty) ...[
                    pw.SizedBox(height: 6),
                    pw.Text(
                      'Daily top content',
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: _hex(_ink),
                      ),
                    ),
                    ...extras.contentTypeDailyLines.take(7).map(
                          (line) => pw.Padding(
                            padding: const pw.EdgeInsets.only(top: 2),
                            child: bodyText('• $line'),
                          ),
                        ),
                  ],
                ],
              ),
            ),
          if (extras.riskSummary != null || extras.riskAlertLines.isNotEmpty)
            card(
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  sectionTitle('Risk Summary'),
                  bodyText(
                    (extras.riskSummary != null &&
                            extras.riskSummary!.trim().isNotEmpty)
                        ? extras.riskSummary!.trim()
                        : 'No risk factors detected this week',
                  ),
                  ...extras.riskAlertLines.take(8).map(
                        (line) => pw.Padding(
                          padding: const pw.EdgeInsets.only(top: 3),
                          child: pw.Text(
                            '• $line',
                            style: pw.TextStyle(
                              fontSize: 11,
                              color: _hex('#B3261E'),
                            ),
                          ),
                        ),
                      ),
                ],
              ),
            ),
          if (extras.conditionDayLines.isNotEmpty)
            card(
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  sectionTitle('Stress, Anxiety & Depression (7 Days)'),
                  ...extras.conditionDayLines.take(7).map(
                        (line) => pw.Padding(
                          padding: const pw.EdgeInsets.only(bottom: 3),
                          child: bodyText(line),
                        ),
                      ),
                  if (extras.conditionAveragesLine != null &&
                      extras.conditionAveragesLine!.trim().isNotEmpty) ...[
                    pw.SizedBox(height: 6),
                    pw.Text(
                      extras.conditionAveragesLine!.trim(),
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: _hex(_ink),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          card(
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                sectionTitle('Sleep Quality'),
                pw.Text(
                  'Score: $sleepQualityScore / 100',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: _hex(_ink),
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'Late-night use (10 PM–5 AM): ${fmtHm(lateNightWeekSeconds)} · '
                  'Opens: $lateNightOpensWeek',
                  style: pw.TextStyle(fontSize: 11, color: _hex(_muted)),
                ),
                if (lateNightByDaySeconds.any((s) => s > 0)) ...[
                  pw.SizedBox(height: 8),
                  pw.Text(
                    'Late-night activity by day',
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: _hex(_ink),
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  barRow(
                    lateNightByDaySeconds
                        .take(7)
                        .map((s) => s / 60.0)
                        .toList(),
                    extras.lateNightByDayLabels.isNotEmpty
                        ? extras.lateNightByDayLabels
                        : days,
                    _hex('#4A6FA5'),
                    maxHeight: 50,
                  ),
                ],
                if (lateNightAppLines.isNotEmpty) ...[
                  pw.SizedBox(height: 6),
                  pw.Text('Top late-night apps:', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  ...lateNightAppLines.take(6).map(
                        (line) => pw.Padding(
                          padding: const pw.EdgeInsets.only(top: 2),
                          child: pw.Text('• $line', style: pw.TextStyle(fontSize: 8, color: _hex(_muted))),
                        ),
                      ),
                ],
              ],
            ),
          ),
          if (extras.dailyScreenSummary != null &&
              extras.dailyScreenSummary!.trim().isNotEmpty)
            card(
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  sectionTitle('Daily Screen Trend'),
                  bodyText(extras.dailyScreenSummary!.trim()),
                  if (extras.dailyScreenInsight != null &&
                      extras.dailyScreenInsight!.trim().isNotEmpty) ...[
                    pw.SizedBox(height: 6),
                    bodyText(extras.dailyScreenInsight!.trim()),
                  ],
                ],
              ),
            ),
          if (extras.clinicalSummary != null &&
              extras.clinicalSummary!.trim().isNotEmpty)
            card(
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  sectionTitle('Clinical Summary'),
                  bodyText(extras.clinicalSummary!.trim()),
                ],
              ),
            ),
          if (extras.aiInsightLines.isNotEmpty)
            card(
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  sectionTitle('AI Insights'),
                  ...extras.aiInsightLines.take(12).map(
                        (line) => pw.Padding(
                          padding: const pw.EdgeInsets.only(bottom: 3),
                          child: bodyText('• $line'),
                        ),
                      ),
                ],
              ),
            ),
          card(
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                sectionTitle('Daily Summary'),
                pw.Table(
                  border: pw.TableBorder.all(color: _hex(_border), width: 0.5),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(2),
                    1: const pw.FlexColumnWidth(2),
                    2: const pw.FlexColumnWidth(2),
                  },
                  children: [
                    pw.TableRow(
                      decoration: pw.BoxDecoration(color: PdfColors.grey100),
                      children: [
                        _cell('Day', bold: true),
                        _cell('Screen', bold: true),
                        _cell('Mood', bold: true),
                      ],
                    ),
                    ...List.generate(7, (i) {
                      final screen = i < dailyScreenHours.length ? dailyScreenHours[i] : 0.0;
                      final mood = i < moodSeries.length ? moodSeries[i] : 0.0;
                      return pw.TableRow(
                        children: [
                          _cell(days[i]),
                          _cell('${screen.toStringAsFixed(1)}h'),
                          _cell(mood.toStringAsFixed(1)),
                        ],
                      );
                    }),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (serverReport != null && serverReport.isNotEmpty) {
      final sevenDay = (serverReport['seven_day_data'] as List<dynamic>?) ?? const [];
      final analytics = serverReport['analytics'] as Map<String, dynamic>? ?? {};
      final insights = (serverReport['ai_insights'] as List<dynamic>?) ?? const [];
      final risk = serverReport['risk_level'] as Map<String, dynamic>? ?? {};
      final moodWeekly = serverReport['mood_weekly'] as Map<String, dynamic>? ?? {};
      final moodDays = (moodWeekly['days'] as List<dynamic>?) ?? const [];

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(16),
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              sectionTitle('7-Day Day-by-Day Breakdown'),
              ...sevenDay.take(14).map((raw) {
                final d = raw is Map<String, dynamic> ? raw : <String, dynamic>{};
                final date = (d['date'] ?? '').toString();
                final screen = (d['total_screen_time'] as num?)?.toInt() ?? 0;
                final stress = (d['stress_level'] as num?)?.toInt() ?? 0;
                return card(
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(date, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                      pw.Text('Screen: ${(screen / 3600).toStringAsFixed(1)}h · Stress index: $stress',
                          style: pw.TextStyle(fontSize: 9, color: _hex(_muted))),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      );

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(16),
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              sectionTitle('Analytics Trends'),
              if (analytics['stress_trend'] is List)
                card(
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Stress trend', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                      pw.Text(
                        (analytics['stress_trend'] as List).map((e) => e.toString()).join(', '),
                        style: pw.TextStyle(fontSize: 8, color: _hex(_muted)),
                      ),
                    ],
                  ),
                ),
              if (risk.isNotEmpty)
                card(
                  pw.Text(
                    'Risk: ${risk['level'] ?? ''} (${risk['score'] ?? ''})',
                    style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                  ),
                ),
              sectionTitle('AI Insights'),
              ...insights.take(12).map(
                    (line) => pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 4),
                      child: pw.Text('• ${line.toString()}', style: pw.TextStyle(fontSize: 9)),
                    ),
                  ),
            ],
          ),
        ),
      );

      if (moodDays.isNotEmpty) {
        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(16),
            build: (ctx) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                sectionTitle('Weekly Mood Architecture'),
                pw.Text(
                  'Dominant: ${moodWeekly['dominant_mood'] ?? ''}',
                  style: pw.TextStyle(fontSize: 10, color: _hex(_accent)),
                ),
                pw.SizedBox(height: 8),
                ...moodDays.map((raw) {
                  final d = raw is Map<String, dynamic> ? raw : <String, dynamic>{};
                  final media = (d['media'] as List<dynamic>?) ?? const [];
                  return card(
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          '${d['date'] ?? ''}: ${d['label'] ?? '—'} (${d['entries'] ?? 0} captures)',
                          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                        ),
                        if (media.isNotEmpty)
                          pw.Text(
                            media
                                .map((m) => '${(m as Map)['type']}: ${(m)['url']}')
                                .join('\n'),
                            style: pw.TextStyle(fontSize: 7, color: _hex(_muted)),
                          ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      }
    }

    final out = await doc.save();
    return Uint8List.fromList(out);
  }

  static pw.Widget _cell(String text, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  /// Stitch-style PDF — full report matching in-app layout (top → summary).
  static Future<Uint8List> buildFromStudio({
    required Map<String, dynamic> studio,
    required String name,
    required String email,
    Uint8List? profileImageBytes,
    List<Map<String, dynamic>> pastReports = const [],
    Map<String, dynamic>? serverReport,
  }) async {
    final Map<String, dynamic> s = studio;

    final summary = s['summary'] as Map<String, dynamic>? ?? {};
    final range = s['range'] as Map<String, dynamic>? ?? {};
    final metricCards = s['metric_cards'] as Map<String, dynamic>? ?? {};
    final wellbeing = s['wellbeing'] as Map<String, dynamic>? ?? {};
    final sleep = s['sleep_quality'] as Map<String, dynamic>? ?? {};
    final risk = s['risk_summary'] as Map<String, dynamic>? ?? {};
    final ai = s['ai_confidence'] as Map<String, dynamic>? ?? {};
    final metricsStatus = s['metrics_status'] as Map<String, dynamic>? ?? {};
    final charts = s['charts'] as Map<String, dynamic>? ?? {};
    final clinical = (s['clinical_summary'] ?? '').toString();
    final conditionLine = (s['condition_averages_line'] ?? '').toString();

    final doc = pw.Document();
    final generated =
        '${DateTime.now().toUtc().toIso8601String().split('.').first}Z';

    pw.Widget card(pw.Widget child, {PdfColor? fill}) => pw.Container(
          width: double.infinity,
          margin: const pw.EdgeInsets.only(bottom: 10),
          padding: const pw.EdgeInsets.all(14),
          decoration: pw.BoxDecoration(
            color: fill ?? PdfColors.white,
            borderRadius: pw.BorderRadius.circular(14),
            border: pw.Border.all(color: _hex(_border)),
          ),
          child: child,
        );

    pw.Widget sectionTitle(String text) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Text(
            text.toUpperCase(),
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 0.5,
              color: _hex(_muted),
            ),
          ),
        );

    pw.Widget bodyText(String text) => pw.Text(
          text,
          style: pw.TextStyle(fontSize: 10, height: 1.35, color: _hex(_muted)),
        );

    final wellbeingScore = summary['wellbeing_score'];
    final wellnessIdx = summary['mental_wellness_index'];
    final stress = summary['stress'] as int?;
    final anxiety = summary['anxiety'] as int?;
    final depression = summary['depression'] as int?;
    final moodStatus = (summary['mood_status'] ?? 'No data').toString();
    final rangeLabel = (range['label'] ?? 'Last 7 days').toString();
    final startDate = (range['start_date'] ?? '').toString();
    final endDate = (range['end_date'] ?? '').toString();
    final dateLine = startDate.isNotEmpty && endDate.isNotEmpty
        ? '$startDate — $endDate'
        : rangeLabel;

    final screenTrend = (charts['daily_screen_trend'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final screenHours = screenTrend
        .map((e) => (e['hours'] as num?)?.toDouble() ?? 0)
        .toList();
    final dayLabels = List.generate(
      screenHours.isEmpty ? 7 : screenHours.length,
      (i) => ['M', 'T', 'W', 'T', 'F', 'S', 'S'][i % 7],
    );

    final dailyMental = (s['daily_mental_health'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();

    final contentItems = (s['content_type_analytics'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final insights = (s['mental_health_insights'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .where((e) => e.trim().isNotEmpty)
        .toList();

    final usageCats = (wellbeing['usage_categories'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();

    final dailySummary = (s['daily_summary'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();

    final pastFromStudio = (s['past_reports'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final pastItems = pastReports.isNotEmpty ? pastReports : pastFromStudio;

    final chunks = summary['analysed_video_chunks'] ?? 0;
    final screenMinNum = summary['screen_on_minutes'] is num
        ? (summary['screen_on_minutes'] as num)
        : 0;
    final screenHrs = screenMinNum > 0
        ? (screenMinNum / 60).toStringAsFixed(1)
        : '—';

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(16),
        build: (ctx) => [
          // —— Header (matches app top) ——
          card(
            pw.Column(
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    if (profileImageBytes != null && profileImageBytes.isNotEmpty)
                      pw.ClipRRect(
                        horizontalRadius: 22,
                        verticalRadius: 22,
                        child: pw.Image(
                          pw.MemoryImage(profileImageBytes),
                          width: 44,
                          height: 44,
                          fit: pw.BoxFit.cover,
                        ),
                      )
                    else
                      pw.Container(
                        width: 44,
                        height: 44,
                        decoration: pw.BoxDecoration(
                          color: _hex('#F3F5F9'),
                          shape: pw.BoxShape.circle,
                        ),
                        child: pw.Center(
                          child: pw.Text(
                            'MS',
                            style: pw.TextStyle(
                              fontSize: 12,
                              fontWeight: pw.FontWeight.bold,
                              color: _hex(_muted),
                            ),
                          ),
                        ),
                      ),
                    pw.SizedBox(width: 12),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            '7-Day Wellbeing Report',
                            style: pw.TextStyle(
                              fontSize: 14,
                              fontWeight: pw.FontWeight.bold,
                              color: _hex(_accent),
                            ),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            name,
                            style: pw.TextStyle(
                              fontSize: 12,
                              fontWeight: pw.FontWeight.bold,
                              color: _hex(_ink),
                            ),
                          ),
                          if (email.isNotEmpty)
                            pw.Text(email, style: pw.TextStyle(fontSize: 9, color: _hex(_muted))),
                          pw.Text(dateLine, style: pw.TextStyle(fontSize: 8, color: _hex(_muted))),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // —— Hero card ——
          pw.Container(
            width: double.infinity,
            margin: const pw.EdgeInsets.only(bottom: 10),
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              gradient: pw.LinearGradient(
                colors: [_hex(_accent), _hex('#4A1FB8')],
              ),
              borderRadius: pw.BorderRadius.circular(16),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  '${rangeLabel.toUpperCase()} · MINDSYNC REPORT',
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          '${wellbeingScore ?? '—'}/100',
                          style: pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 28,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Text(
                          'Wellbeing score',
                          style: pw.TextStyle(color: PdfColors.grey300, fontSize: 9),
                        ),
                      ],
                    ),
                    pw.Spacer(),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          '${wellnessIdx ?? '—'}/100',
                          style: pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Text(
                          'WELLNESS INDEX',
                          style: pw.TextStyle(color: PdfColors.grey300, fontSize: 7),
                        ),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 12),
                _pdfHeroBar('Stress', stress, _hex('#3B82F6')),
                pw.SizedBox(height: 6),
                _pdfHeroBar('Anxiety', anxiety, _hex('#14B8A6')),
                pw.SizedBox(height: 6),
                _pdfHeroBar('Depression', depression, _hex('#F59E0B')),
                pw.SizedBox(height: 8),
                pw.Text(
                  'MOOD: ${moodStatus.toUpperCase()}',
                  style: pw.TextStyle(color: PdfColors.grey300, fontSize: 8),
                ),
              ],
            ),
          ),

          // —— Past reports ——
          if (pastItems.isNotEmpty)
            card(
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Past Reports',
                    style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 8),
                  ...pastItems.take(5).map((row) {
                    final start = (row['week_start'] ?? '').toString();
                    return pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 4),
                      child: pw.Text(
                        start.isNotEmpty ? 'Report $start' : 'Archived report',
                        style: pw.TextStyle(fontSize: 10, color: _hex(_ink)),
                      ),
                    );
                  }),
                ],
              ),
            ),

          // —— Mental state chart ——
          card(
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                sectionTitle('Mental State (7 Days)'),
                _pdfMentalChart(dailyMental),
                if (conditionLine.isNotEmpty) ...[
                  pw.SizedBox(height: 6),
                  pw.Text(
                    conditionLine,
                    style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ],
            ),
          ),

          // —— 6-tile grid ——
          card(
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: _pdfMiniTile(
                        'Content Type',
                        contentItems.isEmpty
                            ? 'No data'
                            : contentItems
                                .take(3)
                                .map((c) => '${c['label']}: ${c['percent']}%')
                                .join('\n'),
                      ),
                    ),
                    pw.SizedBox(width: 8),
                    pw.Expanded(
                      child: _pdfMiniTile(
                        'Mental Insights',
                        insights.isEmpty ? 'No data' : insights.take(3).join('\n'),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 8),
                pw.Row(
                  children: [
                    pw.Expanded(
                      child: _pdfKpi(
                        'Avg Screen',
                        _fmtMetric(metricCards['avg_screen'] as Map<String, dynamic>?),
                        _fmtStatus(metricCards['avg_screen'] as Map<String, dynamic>?),
                      ),
                    ),
                    pw.SizedBox(width: 8),
                    pw.Expanded(
                      child: _pdfKpi(
                        'Mood',
                        _fmtMetric(metricCards['mood'] as Map<String, dynamic>?),
                        _fmtStatus(metricCards['mood'] as Map<String, dynamic>?),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 8),
                pw.Row(
                  children: [
                    pw.Expanded(
                      child: _pdfKpi(
                        'Sleep',
                        _fmtMetric(metricCards['sleep'] as Map<String, dynamic>?),
                        _fmtStatus(metricCards['sleep'] as Map<String, dynamic>?),
                      ),
                    ),
                    pw.SizedBox(width: 8),
                    pw.Expanded(
                      child: _pdfKpi(
                        'Wellbeing',
                        _fmtMetric(metricCards['wellbeing'] as Map<String, dynamic>?),
                        _fmtStatus(metricCards['wellbeing'] as Map<String, dynamic>?),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // —— Wellbeing detail ——
          card(
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Wellbeing Detail', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                bodyText((wellbeing['message'] ?? '').toString()),
                pw.SizedBox(height: 6),
                pw.Text(
                  'Score: ${wellbeing['score'] ?? '—'} / 100',
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                ),
                if (usageCats.isNotEmpty) ...[
                  pw.SizedBox(height: 8),
                  ...usageCats.map((c) => _pdfUsageBar(
                        (c['label'] ?? '').toString(),
                        (c['percent'] as num?)?.toInt() ?? 0,
                      )),
                ],
                if ((wellbeing['recommendation'] ?? '').toString().isNotEmpty)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 8),
                    child: pw.Container(
                      width: double.infinity,
                      padding: const pw.EdgeInsets.all(10),
                      decoration: pw.BoxDecoration(
                        color: _hex('#EDE9FB'),
                        borderRadius: pw.BorderRadius.circular(10),
                      ),
                      child: pw.Text(
                        wellbeing['recommendation'].toString(),
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: _hex(_accent),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // —— Sleep & trigger mood ——
          card(
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                sectionTitle('Sleep & Trigger Mood'),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                  children: dayLabels
                      .map(
                        (l) => pw.Column(
                          children: [
                            pw.Text(l, style: pw.TextStyle(fontSize: 8, color: _hex(_muted))),
                            pw.SizedBox(height: 4),
                            pw.Container(
                              width: 5,
                              height: 5,
                              decoration: pw.BoxDecoration(
                                color: _hex(_muted),
                                shape: pw.BoxShape.circle,
                              ),
                            ),
                          ],
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),

          // —— Screen distribution ——
          card(
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                sectionTitle('7 Day Screen Distribution'),
                if (screenHours.isEmpty || screenHours.every((v) => v <= 0))
                  bodyText('No screen time data available for this period.')
                else
                  _pdfBarRow(screenHours, dayLabels, _hex(_accent)),
              ],
            ),
          ),

          // —— Mood over week ——
          card(
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                sectionTitle('Mood Over Week'),
                pw.Row(
                  children: List.generate(
                    7,
                    (_) => pw.Expanded(
                      child: pw.Container(
                        height: 2,
                        margin: const pw.EdgeInsets.symmetric(horizontal: 2),
                        color: _hex(_border),
                      ),
                    ),
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  (risk['has_risk'] == true)
                      ? 'DETAILS ON MOOD FACTORS'
                      : 'No risk factors detected this week',
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: _hex((risk['has_risk'] == true) ? '#14B8A6' : '#22C55E'),
                  ),
                ),
              ],
            ),
          ),

          // —— Sleep quality ——
          card(
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  children: [
                    pw.Expanded(
                      child: pw.Text(
                        'Sleep Quality',
                        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                    pw.Text(
                      (sleep['status'] ?? 'No Data').toString().toUpperCase(),
                      style: pw.TextStyle(fontSize: 8, color: _hex(_accent)),
                    ),
                  ],
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  '${sleep['score'] ?? '—'} / 100',
                  style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 4),
                bodyText((sleep['message'] ?? '').toString()),
              ],
            ),
          ),

          // —— Risk banner ——
          pw.Container(
            width: double.infinity,
            margin: const pw.EdgeInsets.only(bottom: 10),
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: pw.BoxDecoration(
              color: _hex('#1B4332'),
              borderRadius: pw.BorderRadius.circular(10),
            ),
            child: pw.Text(
              (risk['message'] ?? 'No risk factors detected this week.').toString(),
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(color: PdfColors.white, fontSize: 10),
            ),
          ),

          // —— AI confidence ——
          card(
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                sectionTitle('AI Clinical Confidence'),
                pw.Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (ai['emotion'] != null) _pdfChip('Emotion: ${ai['emotion']}%'),
                    if (ai['behavior'] != null) _pdfChip('Behavior: ${ai['behavior']}%'),
                    if (ai['risk'] != null) _pdfChip('Risk: ${ai['risk']}%'),
                  ],
                ),
                if ((ai['banner'] ?? '').toString().isNotEmpty) ...[
                  pw.SizedBox(height: 6),
                  pw.Text(
                    ai['banner'].toString().toUpperCase(),
                    style: pw.TextStyle(fontSize: 8, color: _hex(_accent)),
                  ),
                ],
              ],
            ),
            fill: _hex('#F3F5F9'),
          ),

          // —— Daily summary table ——
          if (dailySummary.isNotEmpty)
            card(
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  sectionTitle('Daily Summary'),
                  pw.Table(
                    border: pw.TableBorder.all(color: _hex(_border)),
                    children: [
                      pw.TableRow(
                        decoration: pw.BoxDecoration(color: PdfColors.grey100),
                        children: [
                          _cell('DAY', bold: true),
                          _cell('SCREEN', bold: true),
                          _cell('MOOD', bold: true),
                        ],
                      ),
                      ...dailySummary.take(7).map(
                            (r) => pw.TableRow(
                              children: [
                                _cell((r['day'] ?? '').toString()),
                                _cell((r['screen'] ?? '').toString()),
                                _cell((r['mood'] ?? '').toString()),
                              ],
                            ),
                          ),
                    ],
                  ),
                  pw.SizedBox(height: 10),
                  pw.Text(
                    'Normal: ${metricsStatus['normal'] ?? 0} · Positive: ${metricsStatus['positive'] ?? 0} · '
                    'Stable: ${metricsStatus['stable'] ?? 0} · Warning: ${metricsStatus['warning'] ?? 0}',
                    style: pw.TextStyle(fontSize: 9, color: _hex(_muted)),
                  ),
                  pw.SizedBox(height: 4),
                  bodyText((metricsStatus['message'] ?? '').toString()),
                ],
              ),
            ),

          // —— Visual summary (matches StitchVisualSummaryCard) ——
          card(
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  children: [
                    pw.Text('✦', style: pw.TextStyle(fontSize: 12, color: _hex(_accent))),
                    pw.SizedBox(width: 6),
                    pw.Text(
                      'Your Week at a Glance',
                      style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
                pw.SizedBox(height: 12),
                pw.Row(
                  children: [
                    pw.Expanded(child: _pdfStatTile('Wellbeing', '${wellbeingScore ?? '—'}', _hex(_accent))),
                    pw.SizedBox(width: 8),
                    pw.Expanded(child: _pdfStatTile('Screen', '${screenHrs}h', _hex('#3B82F6'))),
                  ],
                ),
                pw.SizedBox(height: 8),
                pw.Row(
                  children: [
                    pw.Expanded(child: _pdfStatTile('Video clips', '$chunks', _hex('#14B8A6'))),
                    pw.SizedBox(width: 8),
                    pw.Expanded(
                      child: _pdfStatTile(
                        'Mood',
                        moodStatus.length > 8 ? moodStatus.substring(0, 8) : moodStatus,
                        _hex('#F59E0B'),
                      ),
                    ),
                  ],
                ),
                if (insights.isNotEmpty) ...[
                  pw.SizedBox(height: 12),
                  sectionTitle('Key Insights'),
                  ...insights.take(4).map(
                        (line) => pw.Container(
                          width: double.infinity,
                          margin: const pw.EdgeInsets.only(bottom: 6),
                          padding: const pw.EdgeInsets.all(10),
                          decoration: pw.BoxDecoration(
                            color: _hex('#F3F5F9'),
                            borderRadius: pw.BorderRadius.circular(10),
                          ),
                          child: bodyText(line),
                        ),
                      ),
                ],
                if (insights.isEmpty && clinical.isNotEmpty) ...[
                  pw.SizedBox(height: 12),
                  sectionTitle('Key Insights'),
                  ...clinical
                      .split(RegExp(r'(?<=[.!?])\s+'))
                      .where((s) => s.trim().length > 12)
                      .take(4)
                      .map(
                        (line) => pw.Container(
                          width: double.infinity,
                          margin: const pw.EdgeInsets.only(bottom: 6),
                          padding: const pw.EdgeInsets.all(10),
                          decoration: pw.BoxDecoration(
                            color: _hex('#F3F5F9'),
                            borderRadius: pw.BorderRadius.circular(10),
                          ),
                          child: bodyText(line.trim()),
                        ),
                      ),
                ],
                pw.SizedBox(height: 12),
                sectionTitle('Condition Levels'),
                _pdfConditionBar('Stress', stress, _hex('#3B82F6')),
                pw.SizedBox(height: 6),
                _pdfConditionBar('Anxiety', anxiety, _hex('#14B8A6')),
                pw.SizedBox(height: 6),
                _pdfConditionBar('Depression', depression, _hex('#F59E0B')),
              ],
            ),
          ),

          pw.SizedBox(height: 4),
          pw.Text(
            'Generated $generated · MindSync 7-Day Report',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 8, color: _hex(_muted)),
          ),
        ],
      ),
    );

    final out = await doc.save();
    return Uint8List.fromList(out);
  }

  static String _fmtMetric(Map<String, dynamic>? m) {
    if (m == null) return '—';
    return (m['display'] ?? '—').toString();
  }

  static String _fmtStatus(Map<String, dynamic>? m) =>
      (m?['status'] ?? 'No Data').toString();

  static String _severityLabel(int? v) {
    if (v == null) return 'No data';
    if (v >= 85) return 'High';
    if (v >= 70) return 'Moderate';
    if (v >= 50) return 'Mild';
    return 'Normal';
  }

  static String _pctLabel(int? value) =>
      value == null ? 'No data' : '$value% ${_severityLabel(value)}';

  static pw.Widget _pdfHeroBar(String label, int? value, PdfColor color) {
    final v = (value ?? 0).clamp(0, 100);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          children: [
            pw.Text(label, style: const pw.TextStyle(color: PdfColors.white, fontSize: 8)),
            pw.Spacer(),
            pw.Text(
              _pctLabel(value),
              style: const pw.TextStyle(color: PdfColors.white, fontSize: 8),
            ),
          ],
        ),
        pw.SizedBox(height: 3),
        pw.Container(
          height: 5,
          decoration: pw.BoxDecoration(
            color: PdfColors.white,
            borderRadius: pw.BorderRadius.circular(3),
          ),
          child: pw.Row(
            children: [
              pw.Expanded(
                flex: value != null ? v : 0,
                child: pw.Container(
                  decoration: pw.BoxDecoration(
                    color: color,
                    borderRadius: pw.BorderRadius.circular(3),
                  ),
                ),
              ),
              pw.Expanded(flex: value != null ? (100 - v) : 100, child: pw.SizedBox()),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _pdfConditionBar(String label, int? value, PdfColor color) {
    final v = (value ?? 0).clamp(0, 100);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          children: [
            pw.Text(label, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            pw.Spacer(),
            pw.Text(_pctLabel(value), style: pw.TextStyle(fontSize: 9)),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Container(
          height: 7,
          decoration: pw.BoxDecoration(
            color: _hex('#F3F5F9'),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Row(
            children: [
              pw.Expanded(
                flex: value != null ? v : 0,
                child: pw.Container(
                  decoration: pw.BoxDecoration(
                    color: color,
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                ),
              ),
              pw.Expanded(flex: value != null ? (100 - v) : 100, child: pw.SizedBox()),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _pdfUsageBar(String label, int percent) {
    final v = percent.clamp(0, 100);
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Expanded(child: pw.Text(label, style: pw.TextStyle(fontSize: 9))),
              pw.Text('$percent%', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            ],
          ),
          pw.SizedBox(height: 3),
          pw.Container(
            height: 5,
            decoration: pw.BoxDecoration(
              color: _hex('#F3F5F9'),
              borderRadius: pw.BorderRadius.circular(3),
            ),
            child: pw.Row(
              children: [
                pw.Expanded(
                  flex: v,
                  child: pw.Container(
                    decoration: pw.BoxDecoration(
                      color: _hex(_accent),
                      borderRadius: pw.BorderRadius.circular(3),
                    ),
                  ),
                ),
                pw.Expanded(flex: 100 - v, child: pw.SizedBox()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _pdfBarRow(List<double> values, List<String> labels, PdfColor color) {
    final maxV = values.isEmpty ? 1.0 : values.reduce((a, b) => a > b ? a : b);
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: List.generate(values.length, (i) {
        final h = (values[i] / (maxV + 0.01)) * 70;
        return pw.Expanded(
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Container(
                height: h.clamp(4, 70),
                width: 14,
                decoration: pw.BoxDecoration(
                  color: color,
                  borderRadius: pw.BorderRadius.circular(3),
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                labels[i],
                style: pw.TextStyle(fontSize: 7, color: _hex(_muted)),
                textAlign: pw.TextAlign.center,
              ),
            ],
          ),
        );
      }),
    );
  }

  static pw.Widget _pdfMentalChart(List<Map<String, dynamic>> dailyMental) {
    final days = dailyMental.length >= 7
        ? dailyMental.take(7).toList()
        : [
            ...dailyMental,
            ...List.generate(
              7 - dailyMental.length,
              (i) => {
                'day_label': 'D${dailyMental.length + i + 1}',
                'stress': null,
                'anxiety': null,
                'depression': null,
              },
            ),
          ];

    final hasData = days.any(
      (d) => d['stress'] != null || d['anxiety'] != null || d['depression'] != null,
    );
    if (!hasData) {
      return pw.Text(
        'No daily mental health scores for this week yet.',
        style: pw.TextStyle(fontSize: 9, color: _hex(_muted)),
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          children: [
            _pdfLegendDot('Stress', _hex('#3B82F6')),
            pw.SizedBox(width: 10),
            _pdfLegendDot('Anxiety', _hex('#14B8A6')),
            pw.SizedBox(width: 10),
            _pdfLegendDot('Depression', _hex('#F59E0B')),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(color: _hex(_border)),
          columnWidths: {
            0: const pw.FlexColumnWidth(1.2),
            1: const pw.FlexColumnWidth(1),
            2: const pw.FlexColumnWidth(1),
            3: const pw.FlexColumnWidth(1),
          },
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: PdfColors.grey100),
              children: [
                _cell('DAY', bold: true),
                _cell('STRESS', bold: true),
                _cell('ANXIETY', bold: true),
                _cell('DEPR.', bold: true),
              ],
            ),
            ...days.map((d) {
              final day = (d['day_label'] ?? d['date'] ?? '').toString();
              return pw.TableRow(
                children: [
                  _cell(day.isNotEmpty ? day : '—'),
                  _cell(d['stress']?.toString() ?? '—'),
                  _cell(d['anxiety']?.toString() ?? '—'),
                  _cell(d['depression']?.toString() ?? '—'),
                ],
              );
            }),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          'Y-axis: score 0–100%  ·  X-axis: last 7 days',
          style: pw.TextStyle(fontSize: 7, color: _hex(_muted)),
        ),
      ],
    );
  }

  static pw.Widget _pdfLegendDot(String label, PdfColor color) {
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Container(
          width: 7,
          height: 7,
          decoration: pw.BoxDecoration(color: color, shape: pw.BoxShape.circle),
        ),
        pw.SizedBox(width: 4),
        pw.Text(label, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
      ],
    );
  }

  static pw.Widget _pdfMiniTile(String title, String body) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: _hex('#F3F5F9'),
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title.toUpperCase(),
            style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: _hex(_muted)),
          ),
          pw.SizedBox(height: 6),
          pw.Text(body, style: pw.TextStyle(fontSize: 8, height: 1.3)),
        ],
      ),
    );
  }

  static pw.Widget _pdfStatTile(String label, String value, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: _hex(_border)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            value,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: color),
          ),
          pw.SizedBox(height: 2),
          pw.Text(label, style: pw.TextStyle(fontSize: 8, color: _hex(_muted))),
        ],
      ),
    );
  }

  static pw.Widget _pdfChip(String text) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: _hex(_border)),
      ),
      child: pw.Text(text, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
    );
  }

  static pw.Widget _pdfKpi(String label, String value, String status) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label.toUpperCase(), style: pw.TextStyle(fontSize: 8, color: _hex(_muted))),
          pw.SizedBox(height: 4),
          pw.Text(value, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text(status, style: pw.TextStyle(fontSize: 8, color: _hex(_accent))),
        ],
      ),
    );
  }
}
