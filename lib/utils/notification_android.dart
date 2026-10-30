import 'dart:developer' as developer;
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'notification_util.dart' as util;

/// Android 特定的通知实现
class AndroidNotificationUtil implements util.NotificationUtil {
  final FlutterLocalNotificationsPlugin _plugin;
  final MethodChannel _channel = const MethodChannel('notification_channel');
  bool _initialized = false;

  AndroidNotificationUtil(this._plugin);

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(initSettings);

    // 初始化后立即请求权限
    await requestPermissions();

    _initialized = true;

    developer.log('[Android] 通知服务初始化完成');
  }

  @override
  Future<bool> requestPermissions() async {
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin == null) return false;

    // 请求基础通知权限
    final granted = await androidPlugin.requestNotificationsPermission();
    developer.log('[Android] 基础通知权限: ${granted ?? false}');

    // 请求精确闹钟权限 (Android 12+)
    try {
      await androidPlugin.requestExactAlarmsPermission();
      final canScheduleExact = await androidPlugin.canScheduleExactNotifications();
      developer.log('[Android] 精确闹钟权限: ${canScheduleExact ?? false}');
    } catch (e) {
      developer.log('[Android] 请求精确闹钟权限失败: $e');
    }

    return granted ?? false;
  }

  @override
  Future<void> scheduleDailyReminder({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
  }) async {
    if (!_initialized) await initialize();

    await _cancelReminderSet(id);

    final scheduledDate = util.calculateNextReminderTime(hour, minute);
    final tzScheduledDate = util.convertToTZDateTime(scheduledDate);

    const androidDetails = AndroidNotificationDetails(
      'accounting_reminder',
      '记账提醒',
      channelDescription: '每日记账提醒',
      importance: Importance.max,
      priority: Priority.max,
      ticker: '记账提醒',
      icon: '@mipmap/ic_launcher',
      enableVibration: true,
      playSound: true,
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.public,
      autoCancel: true,
      showWhen: true,
    );

    const notificationDetails = NotificationDetails(android: androidDetails);

    try {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final canScheduleExact =
          await androidPlugin?.canScheduleExactNotifications() ?? false;
      final scheduleMode = canScheduleExact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tzScheduledDate,
        notificationDetails,
        androidScheduleMode: scheduleMode,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      developer.log('[Android] 每日提醒已登记: $hour:$minute 下次 $scheduledDate, 模式 $scheduleMode');
    } catch (e) {
      developer.log('[Android] 插件登记失败，改用备用闹钟: $e');
      await _scheduleAlarmManagerBackup(
        id: id,
        title: title,
        body: body,
        hour: hour,
        minute: minute,
      );
    }
  }

  @override
  Future<void> scheduleOnceReminder({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    if (!_initialized) await initialize();

    final tzScheduledDate = util.convertToTZDateTime(scheduledDate);

    const androidDetails = AndroidNotificationDetails(
      'accounting_reminder',
      '记账提醒',
      channelDescription: '每日记账提醒',
      importance: Importance.max,
      priority: Priority.max,
      ticker: '记账提醒',
      icon: '@mipmap/ic_launcher',
      enableVibration: true,
      playSound: true,
      enableLights: true,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.public,
    );

    const notificationDetails = NotificationDetails(android: androidDetails);

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tzScheduledDate,
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );

    developer.log('[Android] 单次提醒设置成功: $scheduledDate');
  }

  @override
  Future<void> cancelNotification(int id) async {
    if (!_initialized) await initialize();
    await _cancelReminderSet(id);
    developer.log('[Android] 提醒已取消: $id');
  }

  @override
  Future<void> cancelAllNotifications() async {
    if (!_initialized) await initialize();
    await _plugin.cancelAll();
    developer.log('[Android] 所有通知已取消');
  }

  @override
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!_initialized) await initialize();

    const androidDetails = AndroidNotificationDetails(
      'accounting_reminder',
      '记账提醒',
      channelDescription: '每日记账提醒',
      importance: Importance.max,
      priority: Priority.max,
      ticker: '记账提醒',
      icon: '@mipmap/ic_launcher',
      enableVibration: true,
      playSound: true,
      enableLights: true,
    );

    const notificationDetails = NotificationDetails(android: androidDetails);

    await _plugin.show(id, title, body, notificationDetails);
    developer.log('[Android] 即时通知已显示: $title');
  }

  @override
  Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    if (!_initialized) await initialize();
    return await _plugin.pendingNotificationRequests();
  }

  @override
  Future<bool> checkPermissionStatus() async {
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin == null) return false;

    final enabled = await androidPlugin.areNotificationsEnabled();
    return enabled ?? false;
  }

  Future<void> _cancelReminderSet(int id) async {
    await _plugin.cancel(id);
    for (var i = 1; i <= 7; i++) {
      await _plugin.cancel(id + i);
    }
    try {
      await _channel.invokeMethod('cancelFallbackReminder', {
        'notificationId': id + 100,
      });
    } catch (e) {
      developer.log('[Android] 取消备用提醒失败: $e');
    }
  }

  /// 插件登记失败时，用原生闹钟登记下一次。
  Future<void> _scheduleAlarmManagerBackup({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
  }) async {
    final scheduled = await _channel.invokeMethod<bool>('scheduleFallbackReminder', {
      'title': title,
      'body': body,
      'hour': hour,
      'minute': minute,
      'notificationId': id + 100,
    });
    if (scheduled != true) {
      throw StateError('备用记账提醒登记失败');
    }
    developer.log('[Android] 备用提醒已登记');
  }

  /// 检查电池优化状态（Android 特有）
  Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      final result = await _channel.invokeMethod('isIgnoringBatteryOptimizations');
      return result ?? false;
    } catch (e) {
      developer.log('[Android] 检查电池优化状态失败: $e');
      return false;
    }
  }

  /// 请求忽略电池优化（Android 特有）
  Future<bool> requestIgnoreBatteryOptimizations() async {
    try {
      final result = await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
      return result ?? false;
    } catch (e) {
      developer.log('[Android] 请求忽略电池优化失败: $e');
      return false;
    }
  }

  /// 打开应用设置（Android 特有）
  Future<void> openAppSettings() async {
    try {
      await _channel.invokeMethod('openAppSettings');
    } catch (e) {
      developer.log('[Android] 打开应用设置失败: $e');
    }
  }

  /// 打开厂商自启动管理页；不可用时由原生侧打开应用设置页。
  Future<bool> openAutoStartSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openAutoStartSettings') ?? false;
    } catch (e) {
      developer.log('[Android] 打开自启动设置失败: $e');
      await openAppSettings();
      return false;
    }
  }

  /// 打开通知渠道设置（Android 特有）
  Future<void> openNotificationChannelSettings() async {
    try {
      await _channel.invokeMethod('openNotificationChannelSettings');
    } catch (e) {
      developer.log('[Android] 打开通知渠道设置失败: $e');
    }
  }

  /// 获取电池优化详细信息（Android 特有）
  Future<Map<String, dynamic>> getBatteryOptimizationInfo() async {
    try {
      final result = await _channel.invokeMethod('getBatteryOptimizationInfo');
      return Map<String, dynamic>.from(result ?? {});
    } catch (e) {
      developer.log('[Android] 获取电池优化信息失败: $e');
      return {
        'isIgnoring': false,
        'canRequest': false,
        'manufacturer': 'Unknown',
        'model': 'Unknown',
        'androidVersion': 'Unknown',
      };
    }
  }

  /// 获取通知渠道详细信息（Android 特有）
  Future<Map<String, dynamic>> getNotificationChannelInfo() async {
    try {
      final result = await _channel.invokeMethod('getNotificationChannelInfo');
      return Map<String, dynamic>.from(result ?? {});
    } catch (e) {
      developer.log('[Android] 获取通知渠道信息失败: $e');
      return {
        'isEnabled': false,
        'importance': 'unknown',
        'sound': false,
        'vibration': false,
      };
    }
  }
}
