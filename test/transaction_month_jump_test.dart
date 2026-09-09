import 'package:beecount/utils/transaction_month_jump.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('monthJumpIndex', () {
    test('returns first header of the target month (newest day first)', () {
      final map = <String, int>{
        '2026-09-09': 0,
        '2026-09-01': 4,
        '2026-08-20': 10,
        '2026-07-02': 20,
      };
      expect(monthJumpIndex(map, DateTime(2026, 8, 1)), 10);
    });

    test('falls back to nearest older month when target has no rows', () {
      final map = <String, int>{
        '2026-09-09': 0,
        '2026-07-02': 20,
      };
      expect(monthJumpIndex(map, DateTime(2026, 8, 1)), 20);
    });

    test('returns last header when all dates are newer than target', () {
      final map = <String, int>{
        '2026-09-09': 0,
        '2026-08-20': 10,
      };
      expect(monthJumpIndex(map, DateTime(2026, 3, 1)), 10);
    });

    test('returns null for empty map', () {
      expect(monthJumpIndex({}, DateTime(2026, 8, 1)), isNull);
    });
  });

  group('datesContainMonth / datesPassedMonth', () {
    final newestFirst = [
      DateTime(2026, 9, 9),
      DateTime(2026, 9, 1),
      DateTime(2026, 8, 20),
    ];

    test('contains the loaded month', () {
      expect(datesContainMonth(newestFirst, DateTime(2026, 8, 1)), isTrue);
      expect(datesContainMonth(newestFirst, DateTime(2026, 7, 1)), isFalse);
    });

    test('has not passed a newer month that is still ahead', () {
      expect(datesPassedMonth(newestFirst, DateTime(2026, 7, 1)), isFalse);
    });

    test('has passed a month older than the oldest loaded row', () {
      expect(datesPassedMonth(newestFirst, DateTime(2026, 10, 1)), isTrue);
    });
  });
}
