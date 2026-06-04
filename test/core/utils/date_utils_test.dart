import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/utils/date_utils.dart';

void main() {
  group('formatTimeAgo', () {
    final now = DateTime(2024, 6, 15, 12, 0, 0);

    test('returns just now for < 1 minute', () {
      expect(
        formatTimeAgo(now.subtract(const Duration(seconds: 30)), now: now),
        'just now',
      );
    });

    test('returns minutes ago', () {
      expect(
        formatTimeAgo(now.subtract(const Duration(minutes: 5)), now: now),
        '5m ago',
      );
    });

    test('returns hours ago', () {
      expect(
        formatTimeAgo(now.subtract(const Duration(hours: 3)), now: now),
        '3h ago',
      );
    });

    test('returns days ago', () {
      expect(
        formatTimeAgo(now.subtract(const Duration(days: 2)), now: now),
        '2d ago',
      );
    });

    test('returns date for >= 7 days', () {
      expect(
        formatTimeAgo(now.subtract(const Duration(days: 10)), now: now),
        '2024-06-05',
      );
    });

    test('uses DateTime.now when now omitted', () {
      final result = formatTimeAgo(DateTime.now());
      expect(result, isNotEmpty);
    });
  });
}
