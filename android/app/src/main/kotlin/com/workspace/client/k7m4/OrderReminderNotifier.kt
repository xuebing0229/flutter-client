package com.workspace.client.k7m4

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build

object OrderReminderNotifier {
    const val CHANNEL_ID = "order_deadline_reminders"
    private const val PREFS = "order_deadline_notification_state"
    private const val ACCOUNT_NOTIFICATION_IDS = "account_notification_ids"

    fun cancel(context: Context, reminder: OrderReminder) {
        val manager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val id = reminder.key.hashCode()
        manager.cancel(id)
        if (reminder.kind != "diagnostic") {
            forgetAccountNotification(context, id)
        }
    }

    fun cancelAllAccountReminders(context: Context) {
        val manager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val ids = prefs.getStringSet(ACCOUNT_NOTIFICATION_IDS, emptySet())
            ?.toSet()
            ?: emptySet()
        for (id in ids) {
            val notificationId = id.toIntOrNull() ?: continue
            manager.cancel(notificationId)
        }
        prefs.edit().remove(ACCOUNT_NOTIFICATION_IDS).apply()
    }

    private fun rememberAccountNotification(context: Context, id: Int) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val ids = prefs.getStringSet(ACCOUNT_NOTIFICATION_IDS, emptySet())
            ?.toMutableSet()
            ?: mutableSetOf()
        ids.add(id.toString())
        prefs.edit().putStringSet(ACCOUNT_NOTIFICATION_IDS, ids).apply()
    }

    private fun forgetAccountNotification(context: Context, id: Int) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val ids = prefs.getStringSet(ACCOUNT_NOTIFICATION_IDS, emptySet())
            ?.toMutableSet()
            ?: mutableSetOf()
        if (ids.remove(id.toString())) {
            prefs.edit().putStringSet(ACCOUNT_NOTIFICATION_IDS, ids).apply()
        }
    }

    fun show(context: Context, reminder: OrderReminder): Boolean {
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            ReminderDiagnostics.markFailure(
                context,
                "notification permission denied",
            )
            return false
        }

        return try {
            val manager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                manager.createNotificationChannel(
                    NotificationChannel(
                        CHANNEL_ID,
                        "截稿提醒",
                        NotificationManager.IMPORTANCE_HIGH,
                    ).apply {
                        description = "排单截稿提醒"
                        enableVibration(true)
                    },
                )
            }

            val launchIntent =
                context.packageManager.getLaunchIntentForPackage(context.packageName)
            val contentIntent = launchIntent?.let {
                PendingIntent.getActivity(
                    context,
                    reminder.key.hashCode(),
                    it,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
            }

            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                android.app.Notification.Builder(context, CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                android.app.Notification.Builder(context)
            }

            val title =
                if (reminder.kind == "diagnostic") "提醒诊断测试"
                else "截稿提醒 · ${reminder.label}"
            val body =
                if (reminder.kind == "diagnostic") {
                    "如果你没有打开 App 也看到了这条，后台提醒链路正常。"
                } else {
                    "“${reminder.title}”已进入截稿前${reminder.label}"
                }

            val notification = builder
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle(title)
                .setContentText(body)
                .setAutoCancel(true)
                .setWhen(reminder.triggerAtMillis)
                .setShowWhen(true)
                .setContentIntent(contentIntent)
                .build()

            val notificationId = reminder.key.hashCode()
            manager.notify(notificationId, notification)
            if (reminder.kind != "diagnostic") {
                rememberAccountNotification(context, notificationId)
            }
            OrderReminderScheduler.markDelivered(context, reminder)
            ReminderDiagnostics.markNotified(context)
            true
        } catch (error: Exception) {
            ReminderDiagnostics.markFailure(
                context,
                "notify: ${error.message}",
            )
            false
        }
    }
}
