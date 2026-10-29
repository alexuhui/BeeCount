import 'package:beecount/utils/notification_util.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses today when the clock time is still ahead', () {
    final next = calculateNextReminderTime(
      21,
      0,
      now: DateTime(2026, 10, 29, 20, 0),
    );
    expect(next, DateTime(2026, 10, 29, 21, 0));
  });

  test('keeps today when now is exactly the reminder time', () {
    final next = calculateNextReminderTime(
      21,
      0,
      now: DateTime(2026, 10, 29, 21, 0),
    );
    expect(next, DateTime(2026, 10, 29, 21, 0));
  });

  test('rolls to tomorrow after the clock time has passed', () {
    final next = calculateNextReminderTime(
      21,
      0,
      now: DateTime(2026, 10, 29, 21, 0, 1),
    );
    expect(next, DateTime(2026, 10, 30, 21, 0));
  });

  test('midnight rolls to the next day late at night', () {
    final next = calculateNextReminderTime(
      0,
      0,
      now: DateTime(2026, 10, 29, 23, 59),
    );
    expect(next, DateTime(2026, 10, 30, 0, 0));
  });
}
