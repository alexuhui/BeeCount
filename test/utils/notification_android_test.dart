import 'package:beecount/utils/notification_android.dart';
import 'package:beecount/utils/notification_factory.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pluginChannel = MethodChannel('dexterous.com/flutter/local_notifications');
  const backupChannel = MethodChannel('notification_channel');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    NotificationFactory.initializeTimeZone();
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(pluginChannel, null);
    messenger.setMockMethodCallHandler(backupChannel, null);
  });

  test('daily reminder uses an inexact alarm when exact access is denied', () async {
    Map<Object?, Object?>? scheduled;
    messenger.setMockMethodCallHandler(pluginChannel, (call) async {
      if (call.method == 'canScheduleExactNotifications') return false;
      if (call.method == 'zonedSchedule') {
        scheduled = call.arguments as Map<Object?, Object?>;
      }
      return true;
    });
    messenger.setMockMethodCallHandler(backupChannel, (call) async => true);

    final notifications = AndroidNotificationUtil(FlutterLocalNotificationsPlugin());
    await notifications.scheduleDailyReminder(
      id: 1001,
      title: '记账提醒',
      body: '测试',
      hour: 21,
      minute: 0,
    );

    expect(scheduled, isNotNull);
    final details = scheduled!['platformSpecifics'] as Map<Object?, Object?>;
    expect(details['scheduleMode'], 'inexactAllowWhileIdle');
  });

  test('reports failure when both schedulers reject the reminder', () async {
    messenger.setMockMethodCallHandler(pluginChannel, (call) async {
      if (call.method == 'canScheduleExactNotifications') return false;
      if (call.method == 'zonedSchedule') {
        throw PlatformException(code: 'schedule_failed');
      }
      return true;
    });
    messenger.setMockMethodCallHandler(backupChannel, (call) async => false);

    final notifications = AndroidNotificationUtil(FlutterLocalNotificationsPlugin());
    await expectLater(
      notifications.scheduleDailyReminder(
        id: 1001,
        title: '记账提醒',
        body: '测试',
        hour: 21,
        minute: 0,
      ),
      throwsStateError,
    );
  });
}
