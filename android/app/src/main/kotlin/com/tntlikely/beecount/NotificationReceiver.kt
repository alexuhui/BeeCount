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
        // 旧闹钟没有 hour，只弹出这一次，避免按默认 21:00 再登记一条。
        if (intent.hasExtra("hour")) {
            armNext(context, title, body, hour, minute, notificationId)
        }
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
