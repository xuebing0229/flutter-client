package com.workspace.client.k7m4

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.PowerManager

object ReminderDiagnostics {
    private const val PREFS = "order_reminder_diagnostics"

    fun beginTest(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .remove("lastScheduledAtMillis")
            .remove("lastReceiverAtMillis")
            .remove("lastNotifiedAtMillis")
            .putString("lastFailure", "")
            .apply()
    }

    fun markScheduled(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putLong("lastScheduledAtMillis", System.currentTimeMillis())
            .apply()
    }

    fun markReceiver(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putLong("lastReceiverAtMillis", System.currentTimeMillis())
            .apply()
    }


    fun markNotified(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putLong("lastNotifiedAtMillis", System.currentTimeMillis())
            .putString("lastFailure", "")
            .apply()
    }

    fun markFailure(context: Context, message: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString("lastFailure", message)
            .apply()
    }

    fun markBackgroundGuideShown(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean("backgroundGuideShown", true)
            .apply()
    }

    fun snapshot(context: Context): Map<String, Any?> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val alarmManager =
            context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val notificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val powerManager =
            context.getSystemService(Context.POWER_SERVICE) as PowerManager

        val notificationPermission =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        val notificationsEnabled =
            notificationPermission &&
                (
                    Build.VERSION.SDK_INT < Build.VERSION_CODES.N ||
                        notificationManager.areNotificationsEnabled()
                    )
        val channelEnabled =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = notificationManager.getNotificationChannel(
                    OrderReminderNotifier.CHANNEL_ID,
                )
                channel == null || channel.importance != NotificationManager.IMPORTANCE_NONE
            } else {
                true
            }
        val exactAlarmGranted =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
                alarmManager.canScheduleExactAlarms()
        val batteryOptimizationIgnored =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
                powerManager.isIgnoringBatteryOptimizations(context.packageName)

        return linkedMapOf(
            "manufacturer" to Build.MANUFACTURER.orEmpty(),
            "brand" to Build.BRAND.orEmpty(),
            "model" to Build.MODEL.orEmpty(),
            "backgroundGuideShown" to prefs.getBoolean("backgroundGuideShown", false),
            "notificationsEnabled" to notificationsEnabled,
            "notificationChannelEnabled" to channelEnabled,
            "exactAlarmGranted" to exactAlarmGranted,
            "batteryOptimizationIgnored" to batteryOptimizationIgnored,
            "savedReminderCount" to OrderReminderScheduler.savedReminderCount(context),
            "lastScheduledAtMillis" to prefs.getLong("lastScheduledAtMillis", 0L),
            "lastReceiverAtMillis" to prefs.getLong("lastReceiverAtMillis", 0L),
            "lastNotifiedAtMillis" to prefs.getLong("lastNotifiedAtMillis", 0L),
            "lastFailure" to prefs.getString("lastFailure", "").orEmpty(),
        )
    }
}
