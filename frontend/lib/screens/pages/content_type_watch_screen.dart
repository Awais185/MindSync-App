import 'package:flutter/material.dart';

import '../../services/content_type_watch_service.dart';

class ContentTypeWatchScreen extends StatefulWidget {
  const ContentTypeWatchScreen({super.key});

  @override
  State<ContentTypeWatchScreen> createState() => _ContentTypeWatchScreenState();
}

class _ContentTypeWatchScreenState extends State<ContentTypeWatchScreen> {
  bool _loading = true;
  String _period = 'week';
  ContentTypeWatchData _data = ContentTypeWatchData.empty;

  static const _categoryIcons = {
    'Gaming': Icons.sports_esports_rounded,
    'Educational': Icons.school_rounded,
    'Social Media': Icons.people_rounded,
    'Entertainment': Icons.movie_rounded,
    'News & Info': Icons.newspaper_rounded,
    'Health & Wellness': Icons.favorite_rounded,
    'Other': Icons.category_rounded,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await ContentTypeWatchService.instance.fetch(period: _period);
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
    });
  }

  void _setPeriod(String period) {
    if (_period == period) return;
    setState(() => _period = period);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F6FA),
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFFE09100)),
        title: const Text(
          'Most Content Type',
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
        color: const Color(0xFFE09100),
        onRefresh: _load,
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFFE09100)),
              )
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                children: [
                  _periodToggle(),
                  const SizedBox(height: 14),
                  _hero(_data),
                  const SizedBox(height: 18),
                  const Text(
                    'CONTENT YOU WATCH',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: Color(0xFF8A8D99),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _data.hasData
                        ? 'From screen & video tracking (${_data.totalChunks} clips)'
                        : 'Placeholder categories — fills in as video chunks are analysed',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF8A8D99),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _categoryCard(_data),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Recent watches',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1A1C24),
                          ),
                        ),
                      ),
                      Text(
                        '${_data.recentWatches.length} clips',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFE09100),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_data.recentWatches.isEmpty)
                    _emptyCard(
                      'No classified video chunks in this window yet. '
                      'Background screen capture feeds categories here.',
                    )
                  else
                    ..._data.recentWatches.map(_recentTile),
                ],
              ),
      ),
    );
  }

  Widget _periodToggle() {
    return Row(
      children: [
        _chip('Last 7 days', 'week'),
        const SizedBox(width: 8),
        _chip('Today', 'day'),
      ],
    );
  }

  Widget _chip(String label, String value) {
    final selected = _period == value;
    return Expanded(
      child: Material(
        color: selected ? const Color(0xFFFFF4E5) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => _setPeriod(value),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: selected
                    ? const Color(0xFFE09100)
                    : const Color(0xFF8A8D99),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _hero(ContentTypeWatchData data) {
    final lead = data.topCategory;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF4E5), Color(0xFFFFFBF5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFFFE4B8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data.windowLabel,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFFE09100),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            lead != null
                ? '$lead leads your watch time'
                : 'Watch categories',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1C24),
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            lead != null
                ? '${data.topPercent.toStringAsFixed(0)}% of classified clips'
                : 'Gaming, education, social & more — tracked per user from video analysis',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B7280),
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryCard(ContentTypeWatchData data) {
    final items = data.items.isNotEmpty
        ? data.items
        : const [
            ContentTypeWatchItem(
              label: 'Gaming',
              count: 0,
              percent: 0,
              isPlaceholder: true,
              hasWatchData: false,
            ),
            ContentTypeWatchItem(
              label: 'Educational',
              count: 0,
              percent: 0,
              isPlaceholder: true,
              hasWatchData: false,
            ),
            ContentTypeWatchItem(
              label: 'Social Media',
              count: 0,
              percent: 0,
              isPlaceholder: true,
              hasWatchData: false,
            ),
            ContentTypeWatchItem(
              label: 'Entertainment',
              count: 0,
              percent: 0,
              isPlaceholder: true,
              hasWatchData: false,
            ),
            ContentTypeWatchItem(
              label: 'News & Info',
              count: 0,
              percent: 0,
              isPlaceholder: true,
              hasWatchData: false,
            ),
            ContentTypeWatchItem(
              label: 'Health & Wellness',
              count: 0,
              percent: 0,
              isPlaceholder: true,
              hasWatchData: false,
            ),
          ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            _categoryRow(items[i], isTop: i == 0 && items.first.hasWatchData),
          ],
        ],
      ),
    );
  }

  Widget _categoryRow(ContentTypeWatchItem item, {required bool isTop}) {
    final icon = _categoryIcons[item.label] ?? Icons.play_circle_outline_rounded;
    final percent = item.percent.clamp(0, 100);
    final barValue = item.hasWatchData ? percent / 100 : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isTop ? const Color(0xFFE09100) : const Color(0xFF8A8D99),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isTop ? FontWeight.w800 : FontWeight.w700,
                  color: const Color(0xFF1A1C24),
                ),
              ),
            ),
            if (item.isPlaceholder && !item.hasWatchData)
              const Text(
                '—',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFCBD5E1),
                ),
              )
            else
              Text(
                '${percent.toStringAsFixed(1)}%',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1C24),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: barValue,
            minHeight: 8,
            backgroundColor: const Color(0xFFEFF0F5),
            valueColor: AlwaysStoppedAnimation<Color>(
              isTop ? const Color(0xFFE09100) : const Color(0xFF1A2130),
            ),
          ),
        ),
        if (item.count > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${item.count} clip${item.count == 1 ? '' : 's'}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF8A8D99),
              ),
            ),
          ),
      ],
    );
  }

  Widget _recentTile(ContentTypeRecentWatch watch) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4E5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  watch.category,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFE09100),
                  ),
                ),
              ),
              const Spacer(),
              Text(
                watch.time,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF8A8D99),
                ),
              ),
            ],
          ),
          if (watch.platform.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              watch.platform,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1C24),
              ),
            ),
          ],
          if (watch.summary.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              watch.summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF6B7280),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _emptyCard(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        message,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF8A8D99),
          height: 1.4,
        ),
      ),
    );
  }
}
