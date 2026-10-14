import 'package:flutter/material.dart';

class BehaviourStudyData {
  const BehaviourStudyData({
    required this.hasData,
    required this.classes,
  });

  final bool hasData;
  final List<Map<String, dynamic>> classes;

  static const empty = BehaviourStudyData(hasData: false, classes: []);

  factory BehaviourStudyData.fromJson(Map<String, dynamic>? json) {
    if (json == null) return BehaviourStudyData.empty;
    return BehaviourStudyData(
      hasData: json['has_data'] == true,
      classes: (json['classes'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(),
    );
  }
}

class FacialExpressionStudyData {
  const FacialExpressionStudyData({
    required this.hasData,
    required this.classes,
  });

  final bool hasData;
  final List<Map<String, dynamic>> classes;

  static const empty = FacialExpressionStudyData(hasData: false, classes: []);

  factory FacialExpressionStudyData.fromJson(Map<String, dynamic>? json) {
    if (json == null) return FacialExpressionStudyData.empty;
    return FacialExpressionStudyData(
      hasData: json['has_data'] == true,
      classes: (json['classes'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(),
    );
  }
}

class ContentTypeAnalysisData {
  const ContentTypeAnalysisData({
    required this.hasData,
    required this.items,
  });

  final bool hasData;
  final List<Map<String, dynamic>> items;

  static const empty = ContentTypeAnalysisData(hasData: false, items: []);

  factory ContentTypeAnalysisData.fromJson(Map<String, dynamic>? json) {
    if (json == null) return ContentTypeAnalysisData.empty;
    return ContentTypeAnalysisData(
      hasData: json['has_data'] == true,
      items: (json['items'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(),
    );
  }
}

class BehaviourStudyDetailGrid extends StatelessWidget {
  const BehaviourStudyDetailGrid({super.key, required this.data});

  final BehaviourStudyData data;

  static const _icons = [
    Icons.psychology_alt_outlined,
    Icons.mood_bad_outlined,
    Icons.sentiment_dissatisfied_outlined,
    Icons.health_and_safety_outlined,
  ];
  static const _colors = [
    Color(0xFF6F39E8),
    Color(0xFFE09100),
    Color(0xFF0E9186),
    Color(0xFFB3261E),
  ];

  @override
  Widget build(BuildContext context) {
    if (data.classes.isEmpty) {
      return const _EmptyModuleMessage(
        message: 'No behaviour patterns recorded for this period yet.',
      );
    }

    final cards = data.classes.take(4).toList();
    while (cards.length < 4) {
      cards.add({'label': '—', 'count': 0});
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildCard(cards[0], 0)),
            const SizedBox(width: 12),
            Expanded(child: _buildCard(cards[1], 1)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildCard(cards[2], 2)),
            const SizedBox(width: 12),
            Expanded(child: _buildCard(cards[3], 3)),
          ],
        ),
      ],
    );
  }

  Widget _buildCard(Map<String, dynamic> row, int index) {
    final label = (row['label'] ?? 'Unknown').toString();
    final count = (row['count'] as num?)?.toInt() ?? 0;
    final accent = _colors[index % _colors.length];
    return _HomeStyleMetricCard(
      title: label.toUpperCase(),
      value: '$count',
      badge: count > 0 ? '$count Detected' : '0 Detected',
      icon: _icons[index % _icons.length],
      accent: accent,
    );
  }
}

class FacialExpressionStudyDetailGrid extends StatelessWidget {
  const FacialExpressionStudyDetailGrid({super.key, required this.data});

  final FacialExpressionStudyData data;

  static const _icons = [
    Icons.mood_bad_outlined,
    Icons.sentiment_neutral_outlined,
    Icons.sentiment_dissatisfied_outlined,
    Icons.face_retouching_natural_outlined,
  ];
  static const _colors = [
    Color(0xFFE09100),
    Color(0xFF6F39E8),
    Color(0xFF0E9186),
    Color(0xFF2E6FD2),
  ];

  @override
  Widget build(BuildContext context) {
    if (data.classes.isEmpty) {
      return const _EmptyModuleMessage(
        message: 'No facial expression results for this period yet.',
      );
    }

    final cards = data.classes.take(4).toList();
    while (cards.length < 4) {
      cards.add({'label': '—', 'valid_detections': 0});
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildCard(cards[0], 0)),
            const SizedBox(width: 12),
            Expanded(child: _buildCard(cards[1], 1)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildCard(cards[2], 2)),
            const SizedBox(width: 12),
            Expanded(child: _buildCard(cards[3], 3)),
          ],
        ),
      ],
    );
  }

  Widget _buildCard(Map<String, dynamic> row, int index) {
    final label = (row['label'] ?? 'Unknown').toString();
    final count = (row['valid_detections'] as num?)?.toInt() ?? 0;
    return _HomeStyleMetricCard(
      title: label.toUpperCase(),
      value: '$count',
      badge: count > 0 ? '$count above 0.50' : '0',
      icon: _icons[index % _icons.length],
      accent: _colors[index % _colors.length],
    );
  }
}

class ContentTypeAnalysisDetailList extends StatelessWidget {
  const ContentTypeAnalysisDetailList({super.key, required this.data});

  final ContentTypeAnalysisData data;

  @override
  Widget build(BuildContext context) {
    if (!data.hasData || data.items.isEmpty) {
      return const _EmptyModuleMessage(
        message: 'No content type data for this period yet.',
      );
    }

    final sorted = [...data.items]
      ..sort(
        (a, b) => ((b['percent'] as num?) ?? 0).compareTo(
          (a['percent'] as num?) ?? 0,
        ),
      );

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Detected content types',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A2130),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Sorted by share of total detections',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF8A8D99),
            ),
          ),
          const SizedBox(height: 16),
          ...sorted.map((item) {
            final label = (item['label'] ?? 'Other').toString();
            final percent =
                ((item['percent'] as num?) ?? 0).toDouble().clamp(0, 100);
            final isTop = sorted.first == item;
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight:
                                isTop ? FontWeight.w800 : FontWeight.w700,
                            color: const Color(0xFF1A2130),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${percent.toStringAsFixed(1)}%',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1A2130),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: percent / 100,
                      minHeight: 8,
                      backgroundColor: const Color(0xFFEFF0F5),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isTop
                            ? const Color(0xFF6F39E8)
                            : const Color(0xFF1A2130),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _HomeStyleMetricCard extends StatelessWidget {
  const _HomeStyleMetricCard({
    required this.title,
    required this.value,
    required this.badge,
    required this.icon,
    required this.accent,
  });

  final String title;
  final String value;
  final String badge;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 130,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: accent),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              height: 1,
              color: Color(0xFF1A2130),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            badge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
          const Spacer(),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              letterSpacing: 1.0,
              color: Color(0xFF8A8D99),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class BehaviourStudySection extends StatelessWidget {
  const BehaviourStudySection({super.key, required this.data});

  final BehaviourStudyData data;

  @override
  Widget build(BuildContext context) {
    return _AnalyticsModuleShell(
      title: 'Behaviour Study',
      subtitle: 'Patterns from activity analysis',
      icon: Icons.psychology_alt_outlined,
      iconColor: const Color(0xFF6F39E8),
      child: data.hasData && data.classes.isNotEmpty
          ? _BehaviourGrid(classes: data.classes)
          : const _EmptyModuleMessage(
              message: 'No behaviour patterns recorded for this period yet.',
            ),
    );
  }
}

class FacialExpressionStudySection extends StatelessWidget {
  const FacialExpressionStudySection({super.key, required this.data});

  final FacialExpressionStudyData data;

  @override
  Widget build(BuildContext context) {
    return _AnalyticsModuleShell(
      title: 'Facial Expression Study',
      subtitle: 'High-confidence expression signals only',
      icon: Icons.face_retouching_natural_outlined,
      iconColor: const Color(0xFF0E9186),
      child: data.hasData && data.classes.isNotEmpty
          ? _FacialGrid(classes: data.classes)
          : const _EmptyModuleMessage(
              message: 'No facial expression results for this period yet.',
            ),
    );
  }
}

class ContentTypeAnalysisSection extends StatelessWidget {
  const ContentTypeAnalysisSection({super.key, required this.data});

  final ContentTypeAnalysisData data;

  @override
  Widget build(BuildContext context) {
    return _AnalyticsModuleShell(
      title: 'Most Content Type Analysis',
      subtitle: 'What you engage with most often',
      icon: Icons.movie_filter_outlined,
      iconColor: const Color(0xFFE09100),
      child: data.hasData && data.items.isNotEmpty
          ? _ContentTypeList(items: data.items)
          : const _EmptyModuleMessage(
              message: 'No content type data for this period yet.',
            ),
    );
  }
}

class _AnalyticsModuleShell extends StatelessWidget {
  const _AnalyticsModuleShell({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.child,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A2130),
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF8A8D99),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _BehaviourGrid extends StatelessWidget {
  const _BehaviourGrid({required this.classes});

  final List<Map<String, dynamic>> classes;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossCount = constraints.maxWidth >= 520 ? 2 : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: classes.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: crossCount == 2 ? 1.55 : 2.2,
          ),
          itemBuilder: (context, index) {
            final row = classes[index];
            final detected = (row['status'] ?? '').toString() == 'Detected';
            return _MetricCard(
              title: (row['label'] ?? '').toString(),
              lines: [
                _MetricLine('Count', '${row['count'] ?? 0}'),
                _MetricLine(
                  'Percentage',
                  '${((row['percent'] as num?) ?? 0).toStringAsFixed(1)}%',
                ),
                _MetricLine(
                  'Average',
                  '${((row['average_per_day'] as num?) ?? 0).toStringAsFixed(1)} / day',
                ),
              ],
              badge: detected ? 'Detected' : 'Not Detected',
              badgeColor: detected
                  ? const Color(0xFFB3261E)
                  : const Color(0xFF8A8D99),
            );
          },
        );
      },
    );
  }
}

class _FacialGrid extends StatelessWidget {
  const _FacialGrid({required this.classes});

  final List<Map<String, dynamic>> classes;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossCount = constraints.maxWidth >= 520 ? 2 : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: classes.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: crossCount == 2 ? 1.45 : 2.0,
          ),
          itemBuilder: (context, index) {
            final row = classes[index];
            return _MetricCard(
              title: (row['label'] ?? '').toString(),
              lines: [
                _MetricLine('Total', '${row['total_detections'] ?? 0}'),
                _MetricLine('Valid', '${row['valid_detections'] ?? 0}'),
                _MetricLine(
                  'Share',
                  '${((row['percent'] as num?) ?? 0).toStringAsFixed(1)}%',
                ),
              ],
              badge: '${row['valid_detections'] ?? 0} validated',
              badgeColor: const Color(0xFF0E9186),
            );
          },
        );
      },
    );
  }
}

class _ContentTypeList extends StatelessWidget {
  const _ContentTypeList({required this.items});

  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: items.map((item) {
        final label = (item['label'] ?? 'Other').toString();
        final percent = ((item['percent'] as num?) ?? 0).toDouble().clamp(0, 100);
        final isTop = item['is_top'] == true;
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isTop ? FontWeight.w800 : FontWeight.w700,
                        color: const Color(0xFF1A2130),
                      ),
                    ),
                  ),
                  if (isTop)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF4E5),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'Top',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFE09100),
                        ),
                      ),
                    ),
                  Text(
                    '${percent.toStringAsFixed(1)}%',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A2130),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: percent / 100,
                  minHeight: 8,
                  backgroundColor: const Color(0xFFEFF0F5),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isTop
                        ? const Color(0xFF6F39E8)
                        : const Color(0xFF1A2130),
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.lines,
    required this.badge,
    required this.badgeColor,
  });

  final String title;
  final List<_MetricLine> lines;
  final String badge;
  final Color badgeColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEEF0F5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A2130),
            ),
          ),
          const SizedBox(height: 8),
          ...lines.map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Text(
                    line.label,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF8A8D99),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    line.value,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A2130),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              badge,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: badgeColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricLine {
  const _MetricLine(this.label, this.value);
  final String label;
  final String value;
}

class _EmptyModuleMessage extends StatelessWidget {
  const _EmptyModuleMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        message,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF8A8D99),
        ),
      ),
    );
  }
}
