import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/notification_factory.dart';
import '../services/user_settings/user_setting_keys.dart';
import '../services/user_settings/user_settings_store.dart';
import 'database_providers.dart';

/// 记账提醒设置
class ReminderSettings {
  final bool isEnabled;
  final int hour;
  final int minute;

  const ReminderSettings({
    required this.isEnabled,
    required this.hour,
    required this.minute,
  });

  factory ReminderSettings.defaultSettings() {
    return const ReminderSettings(
      isEnabled: false,
      hour: 21,
      minute: 0,
    );
  }

  ReminderSettings copyWith({
    bool? isEnabled,
    int? hour,
    int? minute,
  }) {
    return ReminderSettings(
      isEnabled: isEnabled ?? this.isEnabled,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
    );
  }

  String get timeString {
    final h = hour.toString().padLeft(2, '0');
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReminderSettings &&
          runtimeType == other.runtimeType &&
          isEnabled == other.isEnabled &&
          hour == other.hour &&
          minute == other.minute;

  @override
  int get hashCode => isEnabled.hashCode ^ hour.hashCode ^ minute.hashCode;
}

class ReminderSettingsNotifier extends StateNotifier<ReminderSettings> {
  ReminderSettingsNotifier(this._ref) : super(ReminderSettings.defaultSettings()) {
    _loadSettings();
  }

  final Ref _ref;

  Future<void> _loadSettings() async {
    try {
      final store = _ref.read(userSettingsStoreProvider);
      final isEnabled =
          await store.getBool(UserSettingKeys.reminderEnabled) ?? false;
      final hour = await store.getInt(UserSettingKeys.reminderHour) ?? 21;
      final minute = await store.getInt(UserSettingKeys.reminderMinute) ?? 0;
      state = ReminderSettings(
        isEnabled: isEnabled,
        hour: hour,
        minute: minute,
      );
    } catch (e) {
      // 保持默认
    }
  }

  Future<void> _saveSettings() async {
    try {
      final store = _ref.read(userSettingsStoreProvider);
      await store.setBool(UserSettingKeys.reminderEnabled, state.isEnabled);
      await store.setInt(UserSettingKeys.reminderHour, state.hour);
      await store.setInt(UserSettingKeys.reminderMinute, state.minute);
    } catch (e) {
      // 忽略
    }
  }

  Future<void> updateEnabled(bool enabled) async {
    state = state.copyWith(isEnabled: enabled);
    await _saveSettings();

    final notificationUtil = NotificationFactory.getInstance();
    if (enabled) {
      await notificationUtil.scheduleDailyReminder(
        id: 1001,
        title: '记账提醒',
        body: '别忘了记录今天的收支哦 💰',
        hour: state.hour,
        minute: state.minute,
      );
    } else {
      await notificationUtil.cancelNotification(1001);
    }
  }

  Future<void> updateTime(int hour, int minute) async {
    state = state.copyWith(hour: hour, minute: minute);
    await _saveSettings();

    if (state.isEnabled) {
      final notificationUtil = NotificationFactory.getInstance();
      await notificationUtil.scheduleDailyReminder(
        id: 1001,
        title: '记账提醒',
        body: '别忘了记录今天的收支哦 💰',
        hour: hour,
        minute: minute,
      );
    }
  }

  Future<void> updateSettings(ReminderSettings settings) async {
    state = settings;
    await _saveSettings();

    final notificationUtil = NotificationFactory.getInstance();
    if (settings.isEnabled) {
      await notificationUtil.scheduleDailyReminder(
        id: 1001,
        title: '记账提醒',
        body: '别忘了记录今天的收支哦 💰',
        hour: settings.hour,
        minute: settings.minute,
      );
    } else {
      await notificationUtil.cancelNotification(1001);
    }
  }
}

final reminderSettingsProvider =
    StateNotifierProvider<ReminderSettingsNotifier, ReminderSettings>((ref) {
  return ReminderSettingsNotifier(ref);
});
