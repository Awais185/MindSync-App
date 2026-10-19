import 'package:flutter/material.dart';

import '../../services/behaviour_study_day_service.dart';

class BehaviourStudyDayScreen extends StatefulWidget {
  const BehaviourStudyDayScreen({super.key});

  @override
  State<BehaviourStudyDayScreen> createState() => _BehaviourStudyDayScreenState();
}

class _BehaviourStudyDayScreenState extends State<BehaviourStudyDayScreen> {
  bool _loading = true;
  BehaviourStudyDayData _data = BehaviourStudyDayData.empty;

  static const _outcomeColors = {
    'stress': Color(0xFF3B82F6),
    'emotion': Color(0xFF9B8EC4),
    'depression': Color(0xFFF59E0B),
    'normal': Color(0xFF22C55E),
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await BehaviourStudyDayService.instance.fetch();
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F6FA),
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF6F39E8)),
        title: const Text(
          'Behaviour Study',
          style: TextStyle(
            color: Color(0xFF1A1C24),
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: const Color(0xFF6F39E8),
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF6F39E8)))
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                children: [
                  _hero(_data),
                  const SizedBox(height: 16),
                  _statsRow(_data),
                  const SizedBox(height: 18),
                  const Text(
                    'TODAY\'S SIGNALS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: Color(0xFF8A8D99),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _summaryGrid(_data),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '30s facial scans',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1A1C24),
                          ),
                        ),
                      ),
                      Text(
                        '${_data.facialScans.length} results',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF6F39E8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_data.facialScans.isEmpty)
                    _emptyCard(
                      'No background facial scans today yet. '
                      'Scheduled captures appear here after processing.',
                    )
                  else
                    ..._data.facialScans.map(_scanTile),
                ],
              ),
      ),
    );
  }

  Widget _hero(BehaviourStudyDayData data) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [Color(0xFF6F39E8), Color(0xFF8B5CF6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data.date.isNotEmpty ? data.date : 'Today',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'One-day behaviour view',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            data.windowLabel,
            style: const TextStyle(
              color: Color(0xFFE8DEFF),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statsRow(BehaviourStudyDayData data) {
    return Row(
      children: [
        Expanded(
          child: _miniStat(
            'Facial scans',
            '${data.facialScanCount}',
            Icons.videocam_rounded,
            const Color(0xFF6F39E8),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _miniStat(
            'Video signals',
            '${data.videoChunkSignals}',
            Icons.movie_filter_outlined,
            const Color(0xFF0E9186),
          ),
        ),
      ],
    );
  }

  Widget _miniStat(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A1C24),
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF8A8D99),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryGrid(BehaviourStudyDayData data) {
    final cards = data.summary.isNotEmpty
        ? data.summary
        : [
            const BehaviourDaySummaryCard(key: 'stress', label: 'Stress', count: 0),
            const BehaviourDaySummaryCard(key: 'emotion', label: 'Emotion', count: 0),
            const BehaviourDaySummaryCard(key: 'depression', label: 'Depression', count: 0),
            const BehaviourDaySummaryCard(key: 'normal', label: 'Normal', count: 0),
          ];
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _outcomeCard(cards[0])),
            const SizedBox(width: 10),
            Expanded(child: _outcomeCard(cards.length > 1 ? cards[1] : cards[0])),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _outcomeCard(cards.length > 2 ? cards[2] : cards[0])),
            const SizedBox(width: 10),
            Expanded(child: _outcomeCard(cards.length > 3 ? cards[3] : cards[0])),
          ],
        ),
      ],
    );
  }

  Widget _outcomeCard(BehaviourDaySummaryCard card) {
    final color = _outcomeColors[card.key] ?? const Color(0xFF6F39E8);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            card.label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${card.count}',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1C24),
            ),
          ),
          Text(
            card.count == 1 ? 'detection' : 'detections',
            style: const TextStyle(fontSize: 10, color: Color(0xFF8A8D99)),
          ),
        ],
      ),
    );
  }

  Widget _scanTile(BehaviourDayFacialScan scan) {
    final color = _outcomeColors[scan.outcome] ?? const Color(0xFF6F39E8);
    final processing = scan.status == 'processing' || scan.status == 'pending';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  scan.outcomeLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                scan.time,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF8A8D99),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _chip('Emotion', scan.emotion.isNotEmpty ? scan.emotion : '—'),
              const SizedBox(width: 8),
              _chip('Stress', '${scan.stressScore}%'),
              const SizedBox(width: 8),
              _chip('Depr.', '${scan.depressionScore}%'),
            ],
          ),
          if (scan.sourceApp.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              scan.sourceApp,
              style: const TextStyle(fontSize: 10, color: Color(0xFF8A8D99)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (processing) ...[
            const SizedBox(height: 8),
            const Row(
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6F39E8)),
                ),
                SizedBox(width: 8),
                Text(
                  'Processing…',
                  style: TextStyle(fontSize: 10, color: Color(0xFF6F39E8), fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F5F9),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 8, color: Color(0xFF8A8D99), fontWeight: FontWeight.w700)),
            Text(
              value,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF1A1C24)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyCard(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        message,
        style: const TextStyle(fontSize: 12, height: 1.4, color: Color(0xFF8A8D99)),
      ),
    );
  }
}
