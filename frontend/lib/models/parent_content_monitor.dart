class ParentContentMonitorItem {
  const ParentContentMonitorItem({
    required this.label,
    required this.percent,
    required this.count,
  });

  final String label;
  final double percent;
  final int count;

  factory ParentContentMonitorItem.fromJson(Map<String, dynamic> json) {
    return ParentContentMonitorItem(
      label: (json['label'] ?? json['category'] ?? 'Unknown').toString(),
      percent: (json['percent'] as num?)?.toDouble() ?? 0,
      count: (json['count'] as num?)?.toInt() ?? 0,
    );
  }
}

class ParentContentMonitorSnapshot {
  const ParentContentMonitorSnapshot({
    required this.hasData,
    required this.items,
    this.message,
  });

  final bool hasData;
  final List<ParentContentMonitorItem> items;
  final String? message;

  static const empty = ParentContentMonitorSnapshot(hasData: false, items: []);
}
