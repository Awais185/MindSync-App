import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main_shell_screen.dart';
import '../../config/api_config.dart';
import '../../models/seven_day_studio_report.dart';
import '../../services/local_auth_service.dart';
import '../../services/tracking_permissions_gate.dart';
import '../../services/user_session_cache.dart';
import '../../services/week_report_pdf.dart';
import '../../widgets/report/stitch_report_widgets.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final _auth = LocalAuthService();
  AuthProfile? _profile;
  bool _pdfBusy = false;
  bool _loading = true;
  String? _loadError;
  SevenDayStudioReport? _studio;
  Map<String, dynamic>? _weeklyReportPayload;
  List<Map<String, dynamic>> _pastReports = [];
  VoidCallback? _sessionListener;

  @override
  void initState() {
    super.initState();
    _sessionListener = _onUserSessionChanged;
    UserSessionCache.sessionGeneration.addListener(_sessionListener!);
    unawaited(TrackingPermissionsGate.startScreenTimeIfPermitted());
    unawaited(_reloadReportDataForCurrentUser());
    unawaited(_loadProfile());
  }

  @override
  void dispose() {
    if (_sessionListener != null) {
      UserSessionCache.sessionGeneration.removeListener(_sessionListener!);
    }
    super.dispose();
  }

  void _onUserSessionChanged() {
    unawaited(_reloadReportDataForCurrentUser());
    unawaited(_loadProfile());
  }

  Future<void> _reloadReportDataForCurrentUser() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
        _studio = null;
        _weeklyReportPayload = null;
        _pastReports = [];
      });
    }
    await Future.wait([
      _loadWeeklyReportPayload(),
      _loadPastReports(),
      _loadProfile(),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadWeeklyReportPayload() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth.accessToken') ?? '';
    if (token.isEmpty || !mounted) return;
    try {
      final res = await http
          .get(
            Uri.parse('${ApiConfig.baseUrl}/api/auth/reports/weekly/'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 25));
      if (!mounted) return;
      if (res.statusCode < 200 || res.statusCode >= 300) {
        setState(() => _loadError = 'Could not load report (${res.statusCode}).');
        return;
      }
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) return;
      final report = decoded['report'];
      final studioRaw = decoded['studio'];
      SevenDayStudioReport? parsed;
      if (studioRaw is Map<String, dynamic>) {
        try {
          parsed = SevenDayStudioReport.fromJson(studioRaw);
        } catch (_) {
          parsed = null;
        }
      }
      setState(() {
        _weeklyReportPayload = report is Map<String, dynamic> ? report : null;
        _studio = parsed;
        _loadError = null;
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = 'Network error loading report.');
    }
  }

  Future<void> _loadPastReports() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth.accessToken') ?? '';
    if (token.isEmpty || !mounted) return;
    try {
      final res = await http
          .get(
            Uri.parse('${ApiConfig.baseUrl}/api/auth/reports/weekly/past/'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 20));
      if (!mounted || res.statusCode < 200 || res.statusCode >= 300) return;
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) {
        final items = (decoded['results'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList();
        setState(() => _pastReports = items.take(5).toList());
      }
    } catch (_) {}
  }

  Future<void> _loadProfile() async {
    final profile = await _auth.fetchCurrentUserProfile();
    if (!mounted) return;
    setState(() => _profile = profile);
  }

  void _show(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  void _goToAnalytics() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainShellScreen(initialTab: 1)),
      (_) => false,
    );
  }

  void _goToParentWatchList() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainShellScreen(initialTab: 2)),
      (_) => false,
    );
  }

  String _reportPdfFileName() {
    final d = DateTime.now();
    return 'MindSync_Report_${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}.pdf';
  }

  String get _displayName =>
      _profile?.fullName ??
      _profile?.displayName ??
      _studio?.user.name ??
      'MindSync User';

  String get _displayEmail => _profile?.email ?? _studio?.user.email ?? '';

  String get _profileImageUrl {
    final raw = _profile?.faceImage;
    if (raw == null || raw.isEmpty) return '';
    return _auth.resolveMediaUrl(raw);
  }

  Future<Uint8List?> _loadProfileImageBytes() async {
    final profile = _profile ?? await _auth.fetchCurrentUserProfile();
    final raw = profile?.faceImage;
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('data:image')) {
      try {
        final b64 = raw.contains(',') ? raw.split(',').last : raw;
        return base64Decode(b64);
      } catch (_) {
        return null;
      }
    }
    try {
      final url = _auth.resolveMediaUrl(raw);
      if (url.isEmpty) return null;
      final res = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 12));
      if (res.statusCode >= 200 && res.statusCode < 300 && res.bodyBytes.isNotEmpty) {
        return res.bodyBytes;
      }
    } catch (_) {}
    return null;
  }

  /// Weekly report API is the single source of truth; only overlay logged-in profile.
  SevenDayStudioReport get _effectiveStudio {
    final base = _studio ??
        SevenDayStudioReport.empty(name: _displayName, email: _displayEmail);
    final name = _displayName.trim().isNotEmpty
        ? _displayName.trim()
        : base.user.name;
    final email = _displayEmail.trim().isNotEmpty
        ? _displayEmail.trim()
        : base.user.email;
    if (name == base.user.name && email == base.user.email) return base;
    return SevenDayStudioReport(
      user: StudioUser(name: name, email: email, avatar: base.user.avatar),
      range: base.range,
      summary: base.summary,
      pastReports: base.pastReports,
      dailyMentalHealth: base.dailyMentalHealth,
      contentTypeAnalytics: base.contentTypeAnalytics,
      mentalHealthInsights: base.mentalHealthInsights,
      metricCards: base.metricCards,
      wellbeing: base.wellbeing,
      charts: base.charts,
      sleepQuality: base.sleepQuality,
      riskSummary: base.riskSummary,
      aiConfidence: base.aiConfidence,
      dailySummary: base.dailySummary,
      metricsStatus: base.metricsStatus,
      clinicalSummary: base.clinicalSummary,
      conditionAveragesLine: base.conditionAveragesLine,
    );
  }

  Future<Uint8List> _buildReportPdfBytes() async {
    final studio = _effectiveStudio;
    final photo = await _loadProfileImageBytes();
    final pastItems = _pastReports.isNotEmpty
        ? _pastReports
        : studio.pastReports
            .map(
              (p) => {
                'id': p.id,
                'week_start': p.weekStart,
                'week_end': p.weekEnd,
              },
            )
            .toList();
    return WeekReportPdfBuilder.buildFromStudio(
      studio: studio.toJson(),
      name: _displayName,
      email: _displayEmail,
      profileImageBytes: photo,
      pastReports: pastItems,
      serverReport: _weeklyReportPayload,
    );
  }

  Future<void> _shareVisualReport() async {
    if (_pdfBusy) return;
    setState(() => _pdfBusy = true);
    try {
      final bytes = await _buildReportPdfBytes();
      await Share.shareXFiles(
        [
          XFile.fromData(
            bytes,
            mimeType: 'application/pdf',
            name: _reportPdfFileName(),
          ),
        ],
        subject: 'MindSync 7-day report',
      );
    } catch (e) {
      if (mounted) _show('Could not build or share report: $e');
    } finally {
      if (mounted) setState(() => _pdfBusy = false);
    }
  }

  Future<void> _exportArchivedReportPdf(int reportId) async {
    if (_pdfBusy) return;
    setState(() => _pdfBusy = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth.accessToken') ?? '';
      if (token.isEmpty) return;
      final res = await http
          .get(
            Uri.parse('${ApiConfig.baseUrl}/api/auth/reports/weekly/$reportId/'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 25));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        _show('Could not load archived report.');
        return;
      }
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final studioRaw = decoded['studio'];
      final Uint8List bytes;
      final photo = await _loadProfileImageBytes();
      if (studioRaw is Map<String, dynamic>) {
        bytes = await WeekReportPdfBuilder.buildFromStudio(
          studio: studioRaw,
          name: _displayName,
          email: _displayEmail,
          profileImageBytes: photo,
          serverReport: decoded['report'] as Map<String, dynamic>?,
        );
      } else {
        bytes = await _buildReportPdfBytes();
      }
      await Share.shareXFiles(
        [
          XFile.fromData(
            bytes,
            mimeType: 'application/pdf',
            name: _reportPdfFileName(),
          ),
        ],
        subject: 'MindSync archived report',
      );
    } catch (e) {
      _show('Could not export PDF: $e');
    } finally {
      if (mounted) setState(() => _pdfBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _goToAnalytics();
      },
      child: Scaffold(
        backgroundColor: ReportStudioTheme.bg,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_loading)
                const LinearProgressIndicator(
                  minHeight: 3,
                  color: ReportStudioTheme.purple,
                  backgroundColor: ReportStudioTheme.cardMuted,
                ),
              if (_loadError != null)
                Material(
                  color: ReportStudioTheme.cardMuted,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _loadError!,
                            style: const TextStyle(fontSize: 11, color: ReportStudioTheme.muted),
                          ),
                        ),
                        TextButton(
                          onPressed: _reloadReportDataForCurrentUser,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              Expanded(child: _buildReportBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReportBody() {
    final studio = _effectiveStudio;
    final showSparseHint = _studio == null && !studio.hasData;
    return RefreshIndicator(
      color: ReportStudioTheme.purple,
      onRefresh: _reloadReportDataForCurrentUser,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          ReportWidthShell(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                _buildHeader(),
                if (showSparseHint) ...[
                  const SizedBox(height: ReportLayout.sectionGap),
                  _buildEmptyReport(),
                ],
                const SizedBox(height: ReportLayout.sectionGap),
                StitchHeroCard(report: studio),
                const SizedBox(height: ReportLayout.sectionGap),
                _buildPastReportsCard(studio),
                const SizedBox(height: ReportLayout.sectionGap),
                _buildMentalStateCard(studio),
                const SizedBox(height: ReportLayout.sectionGap),
                StitchSixTileGrid(
                  contentChild: _buildContentTypes(studio),
                  insightsChild: _buildInsights(studio),
                  cards: studio.metricCards,
                ),
                const SizedBox(height: ReportLayout.sectionGap),
                _buildWellbeingDetail(studio),
                const SizedBox(height: ReportLayout.sectionGap),
                _buildSleepTriggerMood(studio),
                const SizedBox(height: ReportLayout.sectionGap),
                _buildDailyScreenTrend(studio),
                const SizedBox(height: ReportLayout.sectionGap),
                _buildMoodOverWeek(studio),
                const SizedBox(height: ReportLayout.sectionGap),
                _buildSleepQuality(studio),
                const SizedBox(height: ReportLayout.sectionGap),
                StitchRiskBanner(message: studio.riskSummary.message),
                const SizedBox(height: ReportLayout.sectionGap),
                StitchAiConfidenceCard(ai: studio.aiConfidence),
                const SizedBox(height: ReportLayout.sectionGap),
                _buildDailySummaryCard(studio),
                const SizedBox(height: ReportLayout.sectionGap),
                _buildClinicalSummary(studio),
                const SizedBox(height: ReportLayout.sectionGap),
                _buildWatchListButton(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWatchListButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: _goToParentWatchList,
        icon: const Icon(Icons.add, size: 20),
        label: const Text('Add to Watch List'),
        style: ElevatedButton.styleFrom(
          backgroundColor: ReportStudioTheme.purple,
          foregroundColor: Colors.white,
          elevation: 4,
          shadowColor: ReportStudioTheme.purple.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: InkWell(
            onTap: _goToAnalytics,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: ReportStudioTheme.card,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: ReportStudioTheme.ink),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: CircleAvatar(
            radius: 28,
            backgroundColor: ReportStudioTheme.cardMuted,
            backgroundImage: _profileImageUrl.isNotEmpty
                ? NetworkImage(_profileImageUrl)
                : null,
            child: _profileImageUrl.isEmpty
                ? const Icon(Icons.person, color: ReportStudioTheme.muted, size: 28)
                : null,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          '7-Day Wellbeing Report',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: ReportStudioTheme.purple,
            fontWeight: FontWeight.w800,
            fontSize: 16,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _displayName,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: ReportStudioTheme.ink,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          _displayEmail.isNotEmpty ? _displayEmail : 'No email',
          textAlign: TextAlign.center,
          style: const TextStyle(color: ReportStudioTheme.muted, fontSize: 11),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _headerPill(_pdfBusy ? '…' : 'SHARE', _pdfBusy ? () {} : _shareVisualReport),
            const SizedBox(width: 8),
            _headerPill(_pdfBusy ? '…' : 'PDF', _pdfBusy ? () {} : _shareVisualReport),
          ],
        ),
      ],
    );
  }

  Widget _headerPill(String label, VoidCallback onTap) {
    return Material(
      color: ReportStudioTheme.card,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: ReportStudioTheme.purple.withValues(alpha: 0.35)),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: ReportStudioTheme.purple,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPastReportsCard(SevenDayStudioReport studio) {
    final items = _pastReports.isNotEmpty
        ? _pastReports
        : studio.pastReports
            .map((p) => {
                  'id': p.id,
                  'week_start': p.weekStart,
                  'week_end': p.weekEnd,
                })
            .toList();
    return StitchCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Past Reports', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          if (items.isEmpty)
            const StitchEmptyText('No archived reports yet.')
          else
            ...items.map((row) {
              final id = row['id'] as int?;
              final start = (row['week_start'] ?? '').toString();
              final label = start.isNotEmpty ? 'Report $start' : 'Archived report';
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: ReportStudioTheme.cardMuted,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12)),
                    ),
                    if (id != null)
                      IconButton(
                        onPressed: _pdfBusy ? null : () => _exportArchivedReportPdf(id),
                        icon: const Icon(Icons.picture_as_pdf_outlined, color: ReportStudioTheme.purple),
                      ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildMentalStateCard(SevenDayStudioReport studio) {
    final footer = studio.conditionAveragesLine.isNotEmpty
        ? studio.conditionAveragesLine
        : 'Day 1–7 — ${_mentalStateFooter(studio)}';
    return StitchCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StitchSectionTitle('Daily Depression (7 Days)'),
          const SizedBox(height: 10),
          StitchMentalStateChart(days: studio.dailyMentalHealth, footer: footer),
        ],
      ),
    );
  }

  String _mentalStateFooter(SevenDayStudioReport studio) {
    final withData = studio.dailyMentalHealth.where((d) => d.depression != null).length;
    if (withData == 0) return 'No data available';
    if (withData < 7) return 'Partial data on $withData day(s)';
    return 'Full week data';
  }

  Widget _buildContentTypes(SevenDayStudioReport studio) {
    if (studio.contentTypeAnalytics.isEmpty) {
      return const StitchEmptyText('No data available');
    }
    return Column(
      children: studio.contentTypeAnalytics.take(4).map((c) {
        return StitchProgressRow(label: c.label, percent: c.percent);
      }).toList(),
    );
  }

  Widget _buildInsights(SevenDayStudioReport studio) {
    if (studio.mentalHealthInsights.isEmpty) {
      return const StitchEmptyText('No data available');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: studio.mentalHealthInsights.take(3).map((line) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(line, style: const TextStyle(fontSize: 12, height: 1.35)),
        );
      }).toList(),
    );
  }

  Widget _buildWellbeingDetail(SevenDayStudioReport studio) {
    final wb = studio.wellbeing;
    return StitchCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Wellbeing Detail', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    const Text('Clinical categorization', style: TextStyle(fontSize: 10, color: ReportStudioTheme.muted)),
                    const SizedBox(height: 12),
                    if (wb.message.isNotEmpty)
                      Text(wb.message, style: const TextStyle(fontSize: 12, height: 1.4)),
                  ],
                ),
              ),
              StitchRadialScore(score: wb.score),
            ],
          ),
          const SizedBox(height: 16),
          if (wb.usageCategories.isEmpty)
            const StitchEmptyText('No usage category data for this period.')
          else
            ...wb.usageCategories.map((c) {
              final warn = c.label.toLowerCase().contains('switch');
              return StitchProgressRow(label: c.label, percent: c.percent, warning: warn);
            }),
          if (wb.recommendationSections.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'AI RECOMMENDATIONS',
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: ReportStudioTheme.muted),
            ),
            const SizedBox(height: 8),
            ...wb.recommendationSections.map((sec) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(sec.title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    ...sec.bullets.map(
                      (b) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('• ', style: TextStyle(fontSize: 11, color: ReportStudioTheme.purple)),
                            Expanded(child: Text(b, style: const TextStyle(fontSize: 11, height: 1.35))),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ] else if (wb.recommendations.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'AI RECOMMENDATIONS',
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: ReportStudioTheme.muted),
            ),
            const SizedBox(height: 8),
            ...wb.recommendations.take(6).map(
              (b) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ', style: TextStyle(fontSize: 11, color: ReportStudioTheme.purple)),
                    Expanded(child: Text(b, style: const TextStyle(fontSize: 11, height: 1.35))),
                  ],
                ),
              ),
            ),
          ] else if (wb.recommendation.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ReportStudioTheme.purple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                wb.recommendation,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ReportStudioTheme.purple),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSleepTriggerMood(SevenDayStudioReport studio) {
    final sleep = studio.sleepQuality;
    final days = sleep.daily.length >= 7
        ? sleep.daily.take(7).toList()
        : sleep.daily;
    return StitchCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StitchSectionTitle('Sleep & Late-Night Activity'),
          const SizedBox(height: 6),
          Text(
            sleep.trackedNights > 0
                ? '${sleep.trackedNights} tracked night(s) · ${sleep.lateNightHours.toStringAsFixed(1)}h late-night total'
                : '${sleep.lateNightHours.toStringAsFixed(1)}h late-night screen use this week',
            style: const TextStyle(fontSize: 10, color: ReportStudioTheme.muted),
          ),
          const SizedBox(height: 10),
          StitchSleepLateNightWeek(days: days),
        ],
      ),
    );
  }

  Widget _buildDailyScreenTrend(SevenDayStudioReport studio) {
    final trend = studio.charts.dailyScreenTrend;
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final values = trend.map((p) => (p['hours'] as num?)?.toDouble() ?? 0).toList();
    final hasData = values.any((v) => v > 0);
    return StitchCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StitchSectionTitle('7 Day Screen Distribution'),
          const SizedBox(height: 10),
          if (!hasData)
            const StitchEmptyText('No screen time data available for this period.')
          else
            StitchBarChart(values: values, labels: labels),
        ],
      ),
    );
  }

  Widget _buildMoodOverWeek(SevenDayStudioReport studio) {
    return StitchCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StitchSectionTitle('Mood Over Week'),
          const SizedBox(height: 10),
          const StitchMoodWeekDashes(),
          const SizedBox(height: 8),
          Text(
            studio.riskSummary.hasRisk
                ? 'DETAILS ON MOOD FACTORS'
                : 'No risk factors detected this week',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: studio.riskSummary.hasRisk ? ReportStudioTheme.teal : ReportStudioTheme.good,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSleepQuality(SevenDayStudioReport studio) {
    final sleep = studio.sleepQuality;
    final desc = sleep.message;
    return StitchCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Sleep Quality', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              ),
              StitchStatusBadge(sleep.status),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            sleep.score != null ? '${sleep.score}/100' : '—',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(desc, style: const TextStyle(fontSize: 11, color: ReportStudioTheme.muted, height: 1.45)),
        ],
      ),
    );
  }

  Widget _buildDailySummaryCard(SevenDayStudioReport studio) {
    return StitchCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StitchDailyTable(rows: studio.dailySummary),
          const SizedBox(height: 14),
          StitchMetricsStatusRow(status: studio.metricsStatus),
          const SizedBox(height: 8),
          Text(
            studio.metricsStatus.message,
            style: TextStyle(
              fontSize: 11,
              color: studio.metricsStatus.warning > 0
                  ? ReportStudioTheme.warning
                  : ReportStudioTheme.good,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClinicalSummary(SevenDayStudioReport studio) {
    return StitchVisualSummaryCard(report: studio);
  }

  Widget _buildEmptyReport() {
    return StitchCard(
      child: Column(
        children: [
          const Icon(Icons.insights_outlined, size: 48, color: ReportStudioTheme.muted),
          const SizedBox(height: 12),
          const Text(
            'No report data yet',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const StitchEmptyText(
            'Keep using MindSync for a few days. Your 7-day wellbeing report will populate automatically.',
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _reloadReportDataForCurrentUser,
            child: const Text('Refresh'),
          ),
        ],
      ),
    );
  }
}
