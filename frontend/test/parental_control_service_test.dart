import 'package:flutter_test/flutter_test.dart';
import 'package:mindsync/services/parental_control_service.dart';

void main() {
  group('ParentalControlService API models', () {
    test('ParentContentMonitorItem.fromJson maps backend fields', () {
      final item = ParentContentMonitorItem.fromJson({
        'label': 'Social media',
        'category': 'social',
        'percent': 42.5,
        'count': 3,
      });
      expect(item.label, 'Social media');
      expect(item.percent, 42.5);
      expect(item.count, 3);
    });

    test('ParentalAppRule preserves package and blocked flag', () {
      const rule = ParentalAppRule(
        packageName: 'com.example.app',
        appLabel: 'Example',
        blocked: true,
      );
      expect(rule.packageName, 'com.example.app');
      expect(rule.blocked, isTrue);
    });
  });
}
