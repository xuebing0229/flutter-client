package com.workspace.client.k7m4

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject

object OrderReminderScheduler {
    private const val PREFS = "order_deadline_reminders"
    private const val PREFS_KEY = "reminders"
    private const val DELIVERED_KEY = "delivered"
    private const val ACTIVE_ACCOUNT_KEY = "active_account_id"
    private const val WATCHDOG_REQUEST_CODE = 834711
    private const val WATCHDOG_INTERVAL_MILLIS = 24L * 60L * 60L * 1000L

    const val ACTION_SHOW_REMINDER =
        "com.workspace.client.k7m4.action.SHOW_ORDER_REMINDER"
    const val ACTION_WATCHDOG =
        "com.workspace.client.k7m4.action.REMINDER_WATCHDOG"

    fun sync(
        context: Context,
        accountId: String,
        reminders: List<OrderReminder>,
    ) {
        val previousAccountId = activeAccountId(context)
        val previous = load(context)
        for (reminder in previous) {
            cancel(context, reminder)
        }

        if (previousAccountId != null && previousAccountId != accountId) {
            OrderReminderNotifier.cancelAllAccountReminders(context)
        }

        save(context, accountId, reminders)
        pruneDelivered(context, reminders)

        val now = System.currentTimeMillis()
        for (reminder in reminders) {
            if (!isForActiveAccount(context, reminder)) continue
            scheduleIfNeeded(context, reminder, now)
        }

        if (reminders.isEmpty()) {
            cancelWatchdog(context)
        } else {
            scheduleWatchdog(context)
        }
    }

    fun clearActiveAccount(context: Context) {
        val active = activeAccountId(context) ?: return
        clearIfActive(context, active)
    }

    fun activateAccount(context: Context, accountId: String) {
        val previousAccountId = activeAccountId(context)
        if (previousAccountId == accountId) return

        val previous = load(context)
        for (reminder in previous) {
            cancel(context, reminder)
        }

        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs.edit()
            .remove(PREFS_KEY)
            .remove(DELIVERED_KEY)
            .putString(ACTIVE_ACCOUNT_KEY, accountId)
            .apply()

        cancelWatchdog(context)
        OrderReminderNotifier.cancelAllAccountReminders(context)
    }

    fun clearIfActive(context: Context, accountId: String) {
        if (activeAccountId(context) != accountId) return

        val previous = load(context)
        for (reminder in previous) {
            cancel(context, reminder)
        }

        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs.edit()
            .remove(PREFS_KEY)
            .remove(DELIVERED_KEY)
            .remove(ACTIVE_ACCOUNT_KEY)
            .apply()

        cancelWatchdog(context)
        OrderReminderNotifier.cancelAllAccountReminders(context)
    }

    fun isForActiveAccount(
        context: Context,
        reminder: OrderReminder,
    ): Boolean {
        if (reminder.kind == "diagnostic") return true
        val active = activeAccountId(context) ?: return false
        return reminder.key.startsWith("$active:")
    }

    fun rescheduleAll(context: Context) {
        val reminders = load(context)
            .filter { reminder -> isForActiveAccount(context, reminder) }
        val now = System.currentTimeMillis()
        for (reminder in reminders) {
            scheduleIfNeeded(context, reminder, now)
        }

        if (reminders.isEmpty()) {
            cancelWatchdog(context)
        } else {
            scheduleWatchdog(context)
        }
    }

    fun scheduleStandalone(context: Context, reminder: OrderReminder) {
        schedule(context, reminder, reminder.triggerAtMillis)
    }

    fun savedReminderCount(context: Context): Int =
        load(context).count {
            isForActiveAccount(context, it) && !wasDelivered(context, it)
        }

    fun markDelivered(context: Context, reminder: OrderReminder) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val delivered = prefs.getStringSet(DELIVERED_KEY, emptySet())
            ?.toMutableSet()
            ?: mutableSetOf()
        delivered.add(deliveryToken(reminder))
        prefs.edit().putStringSet(DELIVERED_KEY, delivered).apply()
    }

    fun wasDelivered(context: Context, reminder: OrderReminder): Boolean {
        val delivered = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getStringSet(DELIVERED_KEY, emptySet())
            ?: emptySet()
        return deliveryToken(reminder) in delivered
    }

    private fun scheduleIfNeeded(
        context: Context,
        reminder: OrderReminder,
        now: Long,
    ) {
        if (reminder.deadlineAtMillis <= now) return
        if (wasDelivered(context, reminder)) return

        if (reminder.triggerAtMillis <= now) {
            OrderReminderNotifier.show(context, reminder)
            return
        }

        schedule(context, reminder, reminder.triggerAtMillis)
    }

    private fun schedule(
        context: Context,
        reminder: OrderReminder,
        scheduleAtMillis: Long,
    ) {
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pendingIntent = reminderPendingIntent(
            context,
            reminder,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        ) ?: return

        val exact = canUseExactAlarm(manager)

        try {
            if (exact && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                manager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    scheduleAtMillis,
                    pendingIntent,
                )
            } else if (exact) {
                @Suppress("DEPRECATION")
                manager.setExact(
                    AlarmManager.RTC_WAKEUP,
                    scheduleAtMillis,
                    pendingIntent,
                )
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                manager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    scheduleAtMillis,
                    pendingIntent,
                )
            } else {
                @Suppress("DEPRECATION")
                manager.set(
                    AlarmManager.RTC_WAKEUP,
                    scheduleAtMillis,
                    pendingIntent,
                )
            }
            ReminderDiagnostics.markScheduled(context)
            if (!exact) {
                ReminderDiagnostics.markFailure(
                    context,
                    "Exact alarm permission unavailable; scheduled inexact fallback.",
                )
            }
        } catch (error: SecurityException) {
            ReminderDiagnostics.markFailure(
                context,
                "Exact alarm SecurityException: ${error.message}",
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                manager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    scheduleAtMillis,
                    pendingIntent,
                )
            } else {
                @Suppress("DEPRECATION")
                manager.set(
                    AlarmManager.RTC_WAKEUP,
                    scheduleAtMillis,
                    pendingIntent,
                )
            }
            ReminderDiagnostics.markScheduled(context)
        }
    }

    private fun canUseExactAlarm(manager: AlarmManager): Boolean =
        when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU -> true
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ->
                manager.canScheduleExactAlarms()
            else -> true
        }

    private fun cancel(context: Context, reminder: OrderReminder) {
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pendingIntent = reminderPendingIntent(
            context,
            reminder,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        ) ?: return
        manager.cancel(pendingIntent)
        pendingIntent.cancel()
    }

    private fun reminderIntent(
        context: Context,
        reminder: OrderReminder,
    ): Intent {
        return Intent(context, OrderReminderReceiver::class.java).apply {
            action = ACTION_SHOW_REMINDER
            data = Uri.parse(
                "artistqueue://deadline-reminder/" +
                    Uri.encode(reminder.key),
            )
            putExtra("key", reminder.key)
            putExtra("title", reminder.title)
            putExtra("kind", reminder.kind)
            putExtra("label", reminder.label)
            putExtra("triggerAtMillis", reminder.triggerAtMillis)
            putExtra("deadlineAtMillis", reminder.deadlineAtMillis)
        }
    }

    private fun reminderPendingIntent(
        context: Context,
        reminder: OrderReminder,
        flags: Int,
    ): PendingIntent? =
        PendingIntent.getBroadcast(
            context,
            reminder.key.hashCode(),
            reminderIntent(context, reminder),
            flags,
        )

    private fun watchdogPendingIntent(context: Context, flags: Int): PendingIntent? =
        PendingIntent.getBroadcast(
            context,
            WATCHDOG_REQUEST_CODE,
            Intent(context, OrderReminderReceiver::class.java).apply {
                action = ACTION_WATCHDOG
            },
            flags,
        )

    private fun scheduleWatchdog(context: Context) {
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pendingIntent = watchdogPendingIntent(
            context,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        ) ?: return
        val triggerAt = System.currentTimeMillis() + WATCHDOG_INTERVAL_MILLIS

        runCatching {
            if (
                canUseExactAlarm(manager) &&
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.M
            ) {
                manager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerAt,
                    pendingIntent,
                )
            } else if (canUseExactAlarm(manager)) {
                @Suppress("DEPRECATION")
                manager.setExact(
                    AlarmManager.RTC_WAKEUP,
                    triggerAt,
                    pendingIntent,
                )
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                manager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerAt,
                    pendingIntent,
                )
            } else {
                @Suppress("DEPRECATION")
                manager.set(
                    AlarmManager.RTC_WAKEUP,
                    triggerAt,
                    pendingIntent,
                )
            }
        }.onFailure {
            ReminderDiagnostics.markFailure(context, "watchdog: ${it.message}")
        }
    }

    private fun cancelWatchdog(context: Context) {
        val pendingIntent = watchdogPendingIntent(
            context,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        ) ?: return
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        manager.cancel(pendingIntent)
        pendingIntent.cancel()
    }

    private fun pruneDelivered(
        context: Context,
        reminders: List<OrderReminder>,
    ) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val current = prefs.getStringSet(DELIVERED_KEY, emptySet())
            ?.toMutableSet()
            ?: mutableSetOf()
        val valid = reminders.mapTo(mutableSetOf(), ::deliveryToken)
        if (current.retainAll(valid)) {
            prefs.edit().putStringSet(DELIVERED_KEY, current).apply()
        }
    }

    private fun deliveryToken(reminder: OrderReminder): String =
        "${reminder.key}@${reminder.triggerAtMillis}"

    private fun save(
        context: Context,
        accountId: String,
        reminders: List<OrderReminder>,
    ) {
        val array = JSONArray()
        reminders.forEach { reminder ->
            array.put(
                JSONObject().apply {
                    put("key", reminder.key)
                    put("title", reminder.title)
                    put("triggerAtMillis", reminder.triggerAtMillis)
                    put("deadlineAtMillis", reminder.deadlineAtMillis)
                    put("kind", reminder.kind)
                    put("label", reminder.label)
                },
            )
        }

        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(ACTIVE_ACCOUNT_KEY, accountId)
            .putString(PREFS_KEY, array.toString())
            .apply()
    }

    private fun activeAccountId(context: Context): String? =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(ACTIVE_ACCOUNT_KEY, null)
            ?.takeIf { it.isNotBlank() }

    private fun load(context: Context): List<OrderReminder> {
        val source = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(PREFS_KEY, null)
            ?: return emptyList()

        return runCatching {
            val array = JSONArray(source)
            buildList {
                for (index in 0 until array.length()) {
                    val item = array.optJSONObject(index) ?: continue
                    val key = item.optString("key", "")
                    val title = item.optString("title", "")
                    val kind = item.optString("kind", "")
                    val label = item.optString("label", "")
                    val triggerAt = item.optLong("triggerAtMillis", -1L)
                    val deadlineAt = item.optLong(
                        "deadlineAtMillis",
                        inferSavedDeadlineAt(triggerAt, kind),
                    )

                    if (
                        key.isNotBlank() &&
                        title.isNotBlank() &&
                        kind.isNotBlank() &&
                        label.isNotBlank() &&
                        triggerAt > 0 &&
                        deadlineAt > 0
                    ) {
                        add(
                            OrderReminder(
                                key = key,
                                title = title,
                                triggerAtMillis = triggerAt,
                                deadlineAtMillis = deadlineAt,
                                kind = kind,
                                label = label,
                            ),
                        )
                    }
                }
            }
        }.getOrElse {
            ReminderDiagnostics.markFailure(context, "load reminders: ${it.message}")
            emptyList()
        }
    }

    private fun inferSavedDeadlineAt(triggerAtMillis: Long, kind: String): Long {
        if (triggerAtMillis <= 0) return -1L
        val offsetMillis = when (kind) {
            "7d" -> 7L * 24L * 60L * 60L * 1000L
            "1d" -> 24L * 60L * 60L * 1000L
            else -> 0L
        }
        return triggerAtMillis + offsetMillis
    }
}
