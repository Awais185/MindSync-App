import 'package:flutter/material.dart';

import '../models/late_night_sleep_snapshot.dart';

/// Appended below Behaviour Study detail — late-night screen activity (22:00–05:00).
class LateNightActivityDetailSection extends StatelessWidget {
  const LateNightActivityDetailSection({
    super.key,
    required this.data,
  });

  final LateNightSleepSnapshot data;

  @override
  Widget build(BuildContext context) {
    final dayLabels = rollingSevenDayLabels();
    final hasPerDay = data.lateNightByDayMinutes.any((v) => v > 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const Text(
          'Late Night Activity',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A1C24),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Screen-on time between 10 PM and 5 AM (device tracker)',
          style: TextStyle(
            fontSize: 12,
            color: Color(0xFF6B6E7A),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
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
              Row(
                children: [
                  const Icon(
                    Icons.nightlight_round,
                    size: 18,
                    color: LateNightSleepColors.activityAccent,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      formatSleepDuration(data.lateNightWeekMinutes),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF181A22),
                      ),
                    ),
                  ),
                  const Text(
                    ' this week',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6B6E7A),
                    ),
                  ),
                ],
              ),
              if (data.lateNightTonightMinutes > 0) ...[
                const SizedBox(height: 4),
                Text(
                  'Tonight: ${formatSleepDuration(data.lateNightTonightMinutes)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6F39E8),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (data.lateNightCategoriesTonight.isNotEmpty ||
                  data.lateNightCategoriesWeek.isNotEmpty) ...[
                const Text(
                  'By app category',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2C2D36),
                  ),
                ),
                const SizedBox(height: 10),
                ...() {
                  final cats = data.lateNightCategoriesWeek.isNotEmpty
                      ? data.lateNightCategoriesWeek
                      : data.lateNightCategoriesTonight;
                  final max = _categoryMax(cats);
                  return _sortedCategories(cats)
                      .map((e) => _categoryRow(e, max));
                }(),
                const SizedBox(height: 16),
              ] else if (!data.hasData) ...[
                const Text(
                  'No late-night screen activity recorded yet for this period.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B6E7A),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              const Text(
                '7-day late-night screen time',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2C2D36),
                ),
              ),
              const SizedBox(height: 12),
              _LateNightWeekBarChart(
                values: data.lateNightByDayMinutes,
                dayLabels: dayLabels,
              ),
              if (!hasPerDay && data.lateNightWeekMinutes <= 0)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Open a tracked app after 10 PM to start recording late-night activity.',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF8A8D99),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  List<MapEntry<String, int>> _sortedCategories(Map<String, int> cats) {
    final entries = cats.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  int _categoryMax(Map<String, int> cats) {
    if (cats.isEmpty) return 1;
    return cats.values.reduce((a, b) => a > b ? a : b).clamp(1, 9999);
  }

  Widget _categoryRow(MapEntry<String, int> entry, int maxMin) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  entry.key,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2C2D36),
                  ),
                ),
              ),
              Text(
                formatSleepDuration(entry.value),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: LateNightSleepColors.categoryColor(entry.key),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: (entry.value / maxMin).clamp(0.05, 1.0),
              minHeight: 5,
              backgroundColor: const Color(0xFFEFF0F5),
              valueColor: AlwaysStoppedAnimation<Color>(
                LateNightSleepColors.categoryColor(entry.key),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LateNightWeekBarChart extends StatelessWidget {
  const _LateNightWeekBarChart({
    required this.values,
    required this.dayLabels,
  });

  final List<int> values;
  final List<String> dayLabels;

  @override
  Widget build(BuildContext context) {
    final bars = values.length >= 7
        ? values.sublist(0, 7)
        : List<int>.filled(7, 0);
    final maxVal = bars.fold<int>(0, (a, b) => a > b ? a : b);
    final maxBar = maxVal <= 0 ? 1.0 : maxVal.toDouble();
    final labels = dayLabels.length >= 7
        ? dayLabels.sublist(0, 7)
        : rollingSevenDayLabels();

    return Column(
      children: [
        SizedBox(
          height: 108,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(7, (index) {
              final v = bars[index];
              final frac = v / maxBar;
              final h = (frac * 64).clamp(v > 0 ? 6.0 : 4.0, 64.0);
              final isHighest = v > 0 && v == maxVal;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      SizedBox(
                        height: 18,
                        child: v > 0
                            ? FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  v >= 60 ? '${v ~/ 60}h' : '${v}m',
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF6B6E7A),
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        height: h,
                        decoration: BoxDecoration(
                          color: isHighest
                              ? LateNightSleepColors.barHighlight
                              : LateNightSleepColors.barTrack,
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: List.generate(
            7,
            (i) => Expanded(
              child: Text(
                labels[i].toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF9A9BA6),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Compact 7-day late-night + sleep rows for Analytics archive card.
class LateNightSleepWeekRows extends StatelessWidget {
  const LateNightSleepWeekRows({
    super.key,
    required this.lateNightByDayMinutes,
    required this.sleepByDayMinutes,
    this.lateNightWeekMinutes = 0,
    this.sleepWeekMinutes = 0,
  });

  final List<int> lateNightByDayMinutes;
  final List<int> sleepByDayMinutes;
  final int lateNightWeekMinutes;
  final int sleepWeekMinutes;

  @override
  Widget build(BuildContext context) {
    final late = lateNightByDayMinutes.length >= 7
        ? lateNightByDayMinutes.sublist(0, 7)
        : List<int>.filled(7, 0);
    final sleep = sleepByDayMinutes.length >= 7
        ? sleepByDayMinutes.sublist(0, 7)
        : List<int>.filled(7, 0);
    final hasAny = late.any((e) => e > 0) ||
        sleep.any((e) => e > 0) ||
        lateNightWeekMinutes > 0 ||
        sleepWeekMinutes > 0;
    if (!hasAny) return const SizedBox.shrink();

    final labels = rollingSevenDayLabels();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        const Divider(height: 1, color: Color(0xFFEFF0F5)),
        const SizedBox(height: 12),
        const Text(
          '7-Day Late Night & Sleep',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13,
            color: Color(0xFF181A22),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          lateNightWeekMinutes > 0 || sleepWeekMinutes > 0
              ? 'Week totals — Late: ${formatSleepDuration(lateNightWeekMinutes)} · '
                  'Sleep: ${formatSleepDuration(sleepWeekMinutes)}'
              : '10 PM – 5 AM · screen-on vs estimated sleep',
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF6B6E7A),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        ...List.generate(7, (i) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  child: Text(
                    labels[i],
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6B6E7A),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Late: ${formatSleepDuration(late[i])}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  'Sleep: ${formatSleepDuration(sleep[i])}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: LateNightSleepColors.sleepAccent,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

/// Standalone card for Analytics — shows even when app-usage list is empty.
class LateNightSleepAnalyticsCard extends StatelessWidget {
  const LateNightSleepAnalyticsCard({super.key, required this.data});

  final LateNightSleepSnapshot data;

  @override
  Widget build(BuildContext context) {
    if (!data.hasData) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '7-Day Late Night & Sleep',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: Color(0xFF181A22),
              ),
            ),
            SizedBox(height: 6),
            Text(
              'No late-night activity recorded yet. Usage Access must be enabled '
              'and you need screen-on time between 10 PM – 5 AM.',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF6B6E7A),
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: LateNightSleepWeekRows(
        lateNightByDayMinutes: data.lateNightByDayMinutes,
        sleepByDayMinutes: data.sleepByDayMinutes,
        lateNightWeekMinutes: data.lateNightWeekMinutes,
        sleepWeekMinutes: data.sleepWeekMinutes,
      ),
    );
  }
}
