# 定时记账提醒后台弹出修复方案

> **For agentic workers:** 按任务顺序实现。每步用 checkbox（`- [ ]`）跟踪。本方案不包含自动 git 提交，提交由用户决定。

**目标：** 记账提醒在应用被划掉或进程被系统回收后，仍由系统在设定时刻弹出，并在弹出后自动预约下一天。

**做法：** 每日提醒只保留一条 `flutter_local_notifications` 精确闹钟，并在 `AndroidManifest.xml` 注册插件要求的两个接收器。插件接收器负责到点弹通知、预约下一天、开机恢复。原生 `AlarmManager` 只在这条路径失败时作为备用，备用闹钟自己循环，开机时不启动界面。

**技术栈：** Flutter、`flutter_local_notifications` 17.2.4、Android `AlarmManager`、Kotlin `BroadcastReceiver`。

## 全局约束

- 插件版本保持 `flutter_local_notifications` 17.2.4，不升级插件。
- 每日提醒通知 ID 保持 `1001`。调用处：`lib/app.dart`、`lib/providers/reminder_providers.dart`。
- 时区继续用启动时的 `NotificationFactory.initializeTimeZone()`（`Asia/Shanghai`）。本次不改时区策略。
- 精确闹钟权限继续用现有的 `SCHEDULE_EXACT_ALARM` 与 `USE_EXACT_ALARM`。不新增 `USE_FULL_SCREEN_INTENT`。
- 提醒开关与时间的数据源是当前账号的 `user_settings`（`UserSettingKeys.reminderEnabled` / `reminderHour` / `reminderMinute`）。不要读 `SharedPreferences` 的 `reminder_enabled`。
- iOS 的 `scheduleDailyReminder` 保持现状。本次缺陷在 Android 接收器。
- 桌面端 `NotificationFactory.getInstance()` 会抛 `UnsupportedError`。恢复逻辑继续包在现有的 `try/catch` 里。

---

## 1. 现象与原因

用户打开提醒后，只有应用进程还活着时，到点才会弹出通知。划掉应用或进程被回收后，到点没有通知。再次打开应用后，又恢复正常。

每日提醒在 `AndroidNotificationUtil.scheduleDailyReminder` 里调用 `FlutterLocalNotificationsPlugin.zonedSchedule`，模式是 `AndroidScheduleMode.exactAllowWhileIdle`，并用 `matchDateTimeComponents: DateTimeComponents.time` 表示每天同一时刻。

插件把闹钟登记到 `AlarmManager`，到点广播的目标是：

`com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver`

该接收器做两件事：调用 `showNotification` 弹出通知，再调用 `scheduleNextNotification` → `zonedScheduleNextNotificationMatchingDateComponents` 预约下一天。开机恢复由 `ScheduledNotificationBootReceiver` 读取插件自己的调度缓存并重新登记闹钟。

从插件 16 起，这两个接收器不再合并进应用。17.2.4 的插件清单里只有 `POST_NOTIFICATIONS` 和 `VIBRATE`。插件 README 的 “AndroidManifest.xml setup” 要求应用自己声明它们。当前 `android/app/src/main/AndroidManifest.xml` 没有这两项。

接收器不在清单里时，系统不能为它拉起进程。进程还在时，显式广播还能送到已加载的类，通知会弹出；进程不在时，广播被丢掉，下一天也不会被预约。

应用每次冷启动都会在 `BeeApp._restoreDailyReminderFromUserSettings` 里再调一次 `scheduleDailyReminder`。进程这时是活的，所以打开应用之后提醒又正常。这就是“只有打开应用才能弹出”。

现有备用路径补不上这个缺口：

| 路径 | 现状 | 结果 |
| --- | --- | --- |
| 未来 7 天的 `zonedSchedule`（ID `1002`–`1008`） | 同样打到未注册的插件接收器 | 进程不在时不会弹出。接收器补上之后，这 7 条会和 ID `1001` 叠成多次通知，必须拆掉 |
| `MainActivity.scheduleNotification`（ID `1101`） | `setExactAndAllowWhileIdle` 只响一次；时间已过时在调度函数里直接 `onReceive`，等于打开应用就弹 | 响完没有下一天。不能靠它做每日提醒 |
| `NotificationReceiver` 的开机分支 | `exported="false"`，且 `BOOT_COMPLETED` 与 `<data android:scheme="package" />` 写在同一个 `intent-filter` | 开机广播匹配不上。分支里还 `startActivity`，Android 10+ 后台启动界面会被系统拦住 |
| `ReminderMonitorService` | 读 `SharedPreferences` 的 `reminder_enabled`。设置实际写在 `user_settings`，`setBool` 不回写 prefs。`pendingNotificationRequests` 读的是插件缓存，不是 `AlarmManager` 里是否还有闹钟 | 回到前台时判定为未开启，不会补登记。缓存还在、闹钟已被厂商清掉时，也会误判为正常 |

## 2. 修完后的行为

- 用户开启提醒或修改时间后，系统里只有 ID `1001` 这一条每日闹钟。
- 应用在前台、后台、被划掉、进程被回收，到点都弹出同一条通知。
- 弹出之后，插件接收器预约下一个同一钟点。
- 设备重启或应用更新后，插件的 `ScheduledNotificationBootReceiver` 按缓存重新登记，不打开界面。
- `zonedSchedule` 抛错时，原生备用闹钟登记下一次触发；触发后弹出并再登记下一天。备用闹钟的开机恢复只读自己的 prefs，不启动 `MainActivity`。
- 用户关闭提醒后，ID `1001`–`1008` 和原生 ID `1101` 全部取消，备用 prefs 清掉。
- 打开应用或回到前台时，若提醒仍开启，用 `user_settings` 再登记一次 ID `1001`，把被厂商清掉的闹钟装回去。这一步只重新登记未来时刻，不因为“打开应用”立刻弹通知。

## 3. 不在本次范围

- 不改提醒文案、设置页布局、iOS 调度。
- 不把每日提醒改成全屏 Intent，不加 `USE_FULL_SCREEN_INTENT`。
- 不新建通知渠道。渠道 `accounting_reminder` 已按 `Importance.max` 创建；系统不允许应用事后调高已有渠道的重要性。个别机型横幅被用户或厂商关掉时，仍走设置页里现有的渠道设置入口。
- 不把时区从 `Asia/Shanghai` 改成设备时区。

## 4. 调度模型

```
开启 / 改时间 / 冷启动 / 回到前台
        │
        ▼
取消 1001–1008 与原生 1101，并清除备用 prefs
        │
        ▼
zonedSchedule(id=1001, exactAllowWhileIdle, matchDateTimeComponents=time)
        │
        ├── 成功 ──► 插件缓存 + AlarmManager
        │              │
        │              ├── 到点：ScheduledNotificationReceiver 弹通知并预约下一天
        │              └── 开机：ScheduledNotificationBootReceiver 按缓存重登记
        │
        └── 失败 ──► 原生备用
                       写入 beecount_reminder_fallback
                       setExactAndAllowWhileIdle(下一次 hour:minute)
                       │
                       ├── 到点：NotificationReceiver 弹通知，再登记下一天
                       └── 开机：同一接收器读 prefs 重登记，不 startActivity
```

成功路径不要再调用 `_scheduleBackupReminders` 和 `_scheduleAlarmManagerBackup`。两条同时成功会在同一分钟弹出两条通知。

## 5. 文件

| 文件 | 动作 |
| --- | --- |
| `android/app/src/main/AndroidManifest.xml` | 注册插件两个接收器；修正 `NotificationReceiver` 的开机 filter |
| `android/app/src/main/kotlin/com/tntlikely/beecount/MainActivity.kt` | 备用闹钟改为按 hour/minute 登记下一次，不再在调度时立刻弹 |
| `android/app/src/main/kotlin/com/tntlikely/beecount/NotificationReceiver.kt` | 弹出后预约下一天；开机只恢复备用闹钟 |
| `lib/utils/notification_android.dart` | 成功路径只登记 ID `1001`；失败才走备用 |
| `lib/utils/notification_util.dart` | `calculateNextReminderTime` 增加可注入的 `now`，供单测 |
| `lib/app.dart` | 回到前台时用 `user_settings` 重新登记 |
| `lib/main.dart` | 去掉 `ReminderMonitorService` 启动 |
| `lib/services/system/reminder_monitor_service.dart` | 删除 |
| `test/utils/reminder_time_test.dart` | 新增 |

`lib/providers/reminder_providers.dart` 继续调用 `scheduleDailyReminder` / `cancelNotification(1001)`，签名不变，这个文件不用改。

---

## 6. 任务

### Task 1: 锁住“下一次提醒不落在过去”

**文件：**

- 修改：`lib/utils/notification_util.dart` 中 `calculateNextReminderTime`
- 新增：`test/utils/reminder_time_test.dart`

**接口：**

- 产出：`DateTime calculateNextReminderTime(int hour, int minute, {DateTime? now})`
- `now` 省略时使用 `DateTime.now()`。现有调用点不用改。

- [ ] **Step 1: 写失败测试**

`test/utils/reminder_time_test.dart`：

```dart
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
```

- [ ] **Step 2: 跑测试，确认因缺少命名参数而失败**

```
flutter test test/utils/reminder_time_test.dart
```

期望：编译失败，`calculateNextReminderTime` 没有命名参数 `now`。

- [ ] **Step 3: 给函数加上 `now`**

`lib/utils/notification_util.dart` 中替换 `calculateNextReminderTime`：

```dart
/// 计算下一次提醒时间。
///
/// [now] 仅用于测试。省略时使用设备当前时间。
/// 指定钟点早于 [now] 时返回下一天的同一钟点；相等时返回今天。
DateTime calculateNextReminderTime(int hour, int minute, {DateTime? now}) {
  final clock = now ?? DateTime.now();
  var scheduledDate = DateTime(clock.year, clock.month, clock.day, hour, minute);

  if (scheduledDate.isBefore(clock)) {
    scheduledDate = scheduledDate.add(const Duration(days: 1));
  }

  return scheduledDate;
}
```

- [ ] **Step 4: 再跑测试**

```
flutter test test/utils/reminder_time_test.dart
```

期望：4 个测试通过。这个测试锁的是调度输入，不能代替真机验证。

### Task 2: 注册插件接收器，并修正自有开机接收器

**文件：**

- 修改：`android/app/src/main/AndroidManifest.xml`

**接口：**

- 消费：插件类名 `com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver`、`com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver`（与 17.2.4 README 一致）
- 产出：进程不在时，插件闹钟仍能启动接收器；`NotificationReceiver` 能收到开机广播，且没有 package data 限制

- [ ] **Step 1: 在 `</application>` 之前加入插件接收器**

放在现有 `NotificationReceiver` 声明附近：

```xml
<receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
<receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
    <intent-filter>
        <action android:name="android.intent.action.BOOT_COMPLETED"/>
        <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
        <action android:name="android.intent.action.QUICKBOOT_POWERON" />
        <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
    </intent-filter>
</receiver>
```

`RECEIVE_BOOT_COMPLETED` 已在清单顶部，不要再加一遍。

- [ ] **Step 2: 替换现有 `NotificationReceiver` 声明**

去掉 `PACKAGE_REPLACED` 和 `<data android:scheme="package" />`。自定义 action filter 也可以去掉：备用闹钟使用指向该类的显式 `PendingIntent`，不依赖 action filter。

```xml
<receiver android:name=".NotificationReceiver"
    android:enabled="true"
    android:exported="false">
    <intent-filter>
        <action android:name="android.intent.action.BOOT_COMPLETED" />
        <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
    </intent-filter>
</receiver>
```

`exported="false"` 与插件开机接收器一致。`BOOT_COMPLETED` 是受保护广播，持有 `RECEIVE_BOOT_COMPLETED` 的应用可以收到。不要改成 `exported="true"`，避免外部应用向这个接收器发广播。

`NotificationClickReceiver` 保持不动。

### Task 3: 原生备用闹钟改为自循环，开机不打开界面

**文件：**

- 修改：`android/app/src/main/kotlin/com/tntlikely/beecount/MainActivity.kt`
- 修改：`android/app/src/main/kotlin/com/tntlikely/beecount/NotificationReceiver.kt`

**接口：**

- MethodChannel `notification_channel` 新方法：
  - `scheduleFallbackReminder`：参数 `title: String`、`body: String`、`hour: Int`、`minute: Int`、`notificationId: Int`。返回 `Boolean`，表示闹钟是否已登记。
  - `cancelFallbackReminder`：参数 `notificationId: Int`。取消闹钟并清除备用 prefs。
- 备用 prefs 文件名：`beecount_reminder_fallback`
- 键：`active`（Boolean）、`hour`（Int）、`minute`（Int）、`title`（String）、`body`（String）、`id`（Int）
- 旧方法 `scheduleNotification` 删除，避免再走“时间已过就立刻 `onReceive`”。

- [ ] **Step 1: 在 `MainActivity` 的 `notification_channel` 分支里换方法**

把 `"scheduleNotification"` 分支换成：

```kotlin
"scheduleFallbackReminder" -> {
    val title = call.argument<String>("title") ?: "记账提醒"
    val body = call.argument<String>("body") ?: "别忘了记录今天的收支哦 💰"
    val hour = call.argument<Int>("hour") ?: 21
    val minute = call.argument<Int>("minute") ?: 0
    val notificationId = call.argument<Int>("notificationId") ?: 1101
    result.success(scheduleFallbackReminder(title, body, hour, minute, notificationId))
}
"cancelFallbackReminder" -> {
    val notificationId = call.argument<Int>("notificationId") ?: 1101
    cancelFallbackReminder(notificationId)
    result.success(true)
}
```

保留现有的 `"cancelNotification"` 分支，让它改为调用 `cancelFallbackReminder`，这样旧的 Dart 取消路径在 Task 4 落地前也不会留下备用闹钟。Task 4 会把 Dart 侧统一到 `cancelFallbackReminder`。

- [ ] **Step 2: 用下面的实现替换 `scheduleNotification` 和 `cancelNotification`**

删除现在的 `scheduleNotification`（其中 `timeDiff <= 0` 时直接 `receiver.onReceive` 的那段不要保留）。新增：

```kotlin
private fun fallbackPrefs() =
    getSharedPreferences("beecount_reminder_fallback", Context.MODE_PRIVATE)

private fun nextTriggerMillis(hour: Int, minute: Int): Long {
    val calendar = java.util.Calendar.getInstance().apply {
        set(java.util.Calendar.SECOND, 0)
        set(java.util.Calendar.MILLISECOND, 0)
        set(java.util.Calendar.HOUR_OF_DAY, hour)
        set(java.util.Calendar.MINUTE, minute)
    }
    if (calendar.timeInMillis <= System.currentTimeMillis()) {
        calendar.add(java.util.Calendar.DAY_OF_YEAR, 1)
    }
    return calendar.timeInMillis
}

private fun fallbackPendingIntent(
    title: String,
    body: String,
    hour: Int,
    minute: Int,
    notificationId: Int,
): PendingIntent {
    val intent = Intent(this, NotificationReceiver::class.java).apply {
        putExtra("title", title)
        putExtra("body", body)
        putExtra("hour", hour)
        putExtra("minute", minute)
        putExtra("notificationId", notificationId)
    }
    val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    return PendingIntent.getBroadcast(this, notificationId, intent, flags)
}

private fun scheduleFallbackReminder(
    title: String,
    body: String,
    hour: Int,
    minute: Int,
    notificationId: Int,
): Boolean {
    val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmManager.canScheduleExactAlarms()) {
        android.util.Log.w("MainActivity", "没有精确闹钟权限，备用提醒未登记")
        return false
    }

    fallbackPrefs().edit()
        .putBoolean("active", true)
        .putInt("hour", hour)
        .putInt("minute", minute)
        .putString("title", title)
        .putString("body", body)
        .putInt("id", notificationId)
        .apply()

    val triggerAt = nextTriggerMillis(hour, minute)
    val pendingIntent = fallbackPendingIntent(title, body, hour, minute, notificationId)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
        alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
    } else {
        alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
    }
    android.util.Log.d("MainActivity", "备用提醒已登记: $triggerAt")
    return true
}

private fun cancelFallbackReminder(notificationId: Int) {
    val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
    val pendingIntent = fallbackPendingIntent("", "", 0, 0, notificationId)
    alarmManager.cancel(pendingIntent)
    fallbackPrefs().edit().clear().apply()
}
```

`fallbackPendingIntent` 在取消时也要使用同一个 request code（`notificationId`）和同一个组件。extras 不同不影响 `AlarmManager.cancel` 的匹配，匹配键是 request code、组件和 flags。

不要在没有精确闹钟权限时 `startActivity(ACTION_REQUEST_SCHEDULE_EXACT_ALARM)`。权限请求已经在 `AndroidNotificationUtil.requestPermissions` 里做过，调度函数再跳设置页会在每次打开应用时打断用户。

- [ ] **Step 3: 重写 `NotificationReceiver`**

用下面的类替换整个文件。删除 `rescheduleNotifications` 里的 `startActivity`。

```kotlin
package com.tntlikely.beecount

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat

class NotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "收到广播: ${intent.action}")
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> restoreFallback(context)
            else -> deliverReminder(context, intent)
        }
    }

    private fun deliverReminder(context: Context, intent: Intent) {
        val title = intent.getStringExtra("title") ?: "记账提醒"
        val body = intent.getStringExtra("body") ?: "别忘了记录今天的收支哦 💰"
        val hour = intent.getIntExtra("hour", 21)
        val minute = intent.getIntExtra("minute", 0)
        val notificationId = intent.getIntExtra("notificationId", 1101)
        showNotification(context, title, body, notificationId)
        armNext(context, title, body, hour, minute, notificationId)
    }

    private fun restoreFallback(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!prefs.getBoolean("active", false)) {
            Log.d(TAG, "没有备用提醒需要恢复")
            return
        }
        val hour = prefs.getInt("hour", 21)
        val minute = prefs.getInt("minute", 0)
        val title = prefs.getString("title", "记账提醒") ?: "记账提醒"
        val body = prefs.getString("body", "别忘了记录今天的收支哦 💰") ?: "别忘了记录今天的收支哦 💰"
        val notificationId = prefs.getInt("id", 1101)
        armNext(context, title, body, hour, minute, notificationId)
    }

    private fun armNext(
        context: Context,
        title: String,
        body: String,
        hour: Int,
        minute: Int,
        notificationId: Int,
    ) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmManager.canScheduleExactAlarms()) {
            Log.w(TAG, "没有精确闹钟权限，无法预约下一次备用提醒")
            return
        }

        val calendar = java.util.Calendar.getInstance().apply {
            set(java.util.Calendar.SECOND, 0)
            set(java.util.Calendar.MILLISECOND, 0)
            set(java.util.Calendar.HOUR_OF_DAY, hour)
            set(java.util.Calendar.MINUTE, minute)
        }
        if (calendar.timeInMillis <= System.currentTimeMillis()) {
            calendar.add(java.util.Calendar.DAY_OF_YEAR, 1)
        }

        val nextIntent = Intent(context, NotificationReceiver::class.java).apply {
            putExtra("title", title)
            putExtra("body", body)
            putExtra("hour", hour)
            putExtra("minute", minute)
            putExtra("notificationId", notificationId)
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val pendingIntent = PendingIntent.getBroadcast(context, notificationId, nextIntent, flags)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                calendar.timeInMillis,
                pendingIntent,
            )
        } else {
            alarmManager.setExact(AlarmManager.RTC_WAKEUP, calendar.timeInMillis, pendingIntent)
        }

        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putBoolean("active", true)
            .putInt("hour", hour)
            .putInt("minute", minute)
            .putString("title", title)
            .putString("body", body)
            .putInt("id", notificationId)
            .apply()
        Log.d(TAG, "下一次备用提醒: ${calendar.timeInMillis}")
    }

    private fun showNotification(context: Context, title: String, body: String, notificationId: Int) {
        val channelId = "accounting_reminder"
        val notificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            val audioAttributes = AudioAttributes.Builder()
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                .build()
            val channel = NotificationChannel(
                channelId,
                "记账提醒",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "每日记账提醒"
                enableVibration(true)
                setSound(soundUri, audioAttributes)
            }
            notificationManager.createNotificationChannel(channel)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && !notificationManager.areNotificationsEnabled()) {
            Log.w(TAG, "通知权限未开启")
            return
        }

        val clickIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("from_notification", true)
            putExtra("notification_id", notificationId)
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            notificationId,
            clickIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(context, channelId)
            .setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()
        notificationManager.notify(notificationId, notification)
    }

    companion object {
        private const val TAG = "NotificationReceiver"
        private const val PREFS = "beecount_reminder_fallback"
    }
}
```

渠道重要性用 `IMPORTANCE_HIGH`。已存在的渠道不会被这次 `createNotificationChannel` 改掉。不要调用 `setBypassDnd(true)`，那需要勿扰策略权限，没有权限时会在部分系统上抛异常，导致整条通知发不出去。

### Task 4: Dart 侧只登记一条每日提醒

**文件：**

- 修改：`lib/utils/notification_android.dart`

**接口：**

- 消费：Task 3 的 `scheduleFallbackReminder`、`cancelFallbackReminder`
- `scheduleDailyReminder` 与 `cancelNotification` 的对外签名不变
- 成功时系统中只有插件 ID `1001`。失败时才有原生 ID `id + 100`（即 `1101`）

- [ ] **Step 1: 替换 `scheduleDailyReminder`**

```dart
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
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tzScheduledDate,
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
    developer.log('[Android] 每日提醒已登记: $hour:$minute 下次 $scheduledDate');
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
```

去掉 `fullScreenIntent: true`。没有 `USE_FULL_SCREEN_INTENT` 时，Android 14 会忽略全屏意图；每日记账提醒用高重要性横幅即可。

不要在 `try` 成功之后调用 `_scheduleBackupReminders` 或 `_scheduleAlarmManagerBackup`。

- [ ] **Step 2: 替换取消与备用登记**

删除 `_scheduleBackupReminders`。`cancelNotification` 改为调用 `_cancelReminderSet`。备用登记改为：

```dart
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

Future<void> _scheduleAlarmManagerBackup({
  required int id,
  required String title,
  required String body,
  required int hour,
  required int minute,
}) async {
  try {
    final scheduled = await _channel.invokeMethod<bool>('scheduleFallbackReminder', {
      'title': title,
      'body': body,
      'hour': hour,
      'minute': minute,
      'notificationId': id + 100,
    });
    developer.log('[Android] 备用提醒登记结果: $scheduled');
  } catch (e) {
    developer.log('[Android] 备用提醒登记失败: $e');
  }
}
```

`_cancelReminderSet` 在每次成功登记前先取消 `1002`–`1008`。已经装过旧版本的用户，这 7 条待触发通知会被清掉，避免接收器补上之后连续多天多弹。

`cancelNotification` 的方法体改为：

```dart
@override
Future<void> cancelNotification(int id) async {
  if (!_initialized) await initialize();
  await _cancelReminderSet(id);
  developer.log('[Android] 提醒已取消: $id');
}
```

`scheduleOnceReminder` 保持单次，不走每日备用。

### Task 5: 回到前台时按账号设置重新登记

**文件：**

- 修改：`lib/app.dart` 的 `didChangeAppLifecycleState`
- 修改：`lib/main.dart`
- 删除：`lib/services/system/reminder_monitor_service.dart`

**接口：**

- 消费：已有的 `_restoreDailyReminderFromUserSettings`
- 该函数在提醒关闭时直接 return；开启时调用 `scheduleDailyReminder`，内部会先取消旧 ID 再登记下一次未来时刻

- [ ] **Step 1: 回到前台时调用恢复函数**

`BeeApp.didChangeAppLifecycleState` 里，`resumed` 分支在更新小组件之后加上恢复调用：

```dart
if (state == AppLifecycleState.resumed) {
  _updateWidget();
  _resumeSyncVersionService();
  _restoreDailyReminderFromUserSettings();
  return;
}
```

不要根据 `pendingNotificationRequests()` 决定是否跳过。那个列表来自插件缓存。厂商清掉 `AlarmManager` 之后缓存仍可能还在，跳过就会继续漏提醒。重复 `zonedSchedule` 同一个 ID 会替换闹钟，触发时刻仍由 `calculateNextReminderTime` 算成下一次，不会在打开应用时立刻弹出。

`_restoreDailyReminderFromUserSettings` 已有 `try/catch`，桌面端抛出的不支持平台错误继续被吃掉。

- [ ] **Step 2: 去掉错误的监控服务**

`lib/main.dart` 删除：

```dart
import 'services/system/reminder_monitor_service.dart';
```

以及 `main()` 里这段：

```dart
try {
  ReminderMonitorService().startMonitoring();
} catch (e) {
  logger.warning('App', '提醒监控服务启动失败（可能在不支持的平台上运行）', e);
}
```

删除 `lib/services/system/reminder_monitor_service.dart`。它读错了存储，并且用插件缓存判断闹钟是否还在。

冷启动的恢复仍留在 `BeeApp.initState` 的 post-frame 回调里，不要删。

### Task 6: 真机验证

单元测试覆盖不了“进程死掉后系统仍投递广播”。Task 1 的测试通过之后，用一台 Android 真机（Android 12 或更高）做下面的检查。

- [ ] **Step 1: 确认合并后的清单含有插件接收器**

```
flutter build apk --debug
```

在 `build/app/intermediates/merged_manifests/debug/AndroidManifest.xml`（路径随 AGP 版本可能略有不同，以 `build/app/intermediates` 下的 merged manifest 为准）中确认同时存在：

- `com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver`
- `com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver`
- `.NotificationReceiver` 的 filter 里没有 `android:scheme="package"`

- [ ] **Step 2: 进程不在时仍弹出**

1. 安装该 debug 包，打开通知权限和精确闹钟权限。
2. 在提醒设置里打开每日提醒，时间设为当前时刻之后 2 分钟。
3. 用最近任务划掉应用，等待到点。
4. 期望：到点弹出一条通知，通知 ID 对应 `1001`。同一分钟没有第二条。
5. 划掉之后不要再打开应用，直到通知出现。

- [ ] **Step 3: 打开应用不会补弹一条已经错过的通知**

1. 把提醒时间设成当前时刻之前的一个钟点。
2. 完全划掉应用后再打开。
3. 期望：打开过程中不弹出提醒。下一次触发是明天的那个钟点。

- [ ] **Step 4: 关闭提醒后不再弹出**

1. 打开提醒，时间设为 2 分钟后。
2. 关掉提醒开关，划掉应用。
3. 期望：到点没有通知。

- [ ] **Step 5: 回归设置页的即时测试按钮**

设置页“测试通知”仍调用 `showNotification`，点击后应立刻出现一条通知。这条不经过闹钟。

---

## 7. 自检

| 要求 | 对应任务 |
| --- | --- |
| 进程不在时插件闹钟仍能弹出 | Task 2 注册 `ScheduledNotificationReceiver` |
| 弹出后有下一天 | 插件 `matchDateTimeComponents: time`；备用路径在 Task 3 的 `armNext` |
| 开机恢复且不打开界面 | Task 2 的 `ScheduledNotificationBootReceiver`；Task 3 的 `restoreFallback` |
| 旧的 7 条备用通知不再叠弹 | Task 4 登记前取消 ID `id+1` 到 `id+7` |
| 打开应用不立刻弹已过时刻 | Task 3 删除 `timeDiff <= 0` 的直接 `onReceive`；Task 1 保证下次时刻不早于现在 |
| 回到前台能把被清掉的闹钟装回 | Task 5 用 `user_settings` 重新 `zonedSchedule` |
| 关闭提醒能取消备用闹钟 | Task 4 `cancelNotification` → `cancelFallbackReminder` |
