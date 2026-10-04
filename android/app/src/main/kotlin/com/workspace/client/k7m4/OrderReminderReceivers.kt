package com.workspace.client.k7m4

import android.app.AlarmManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class OrderReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == OrderReminderScheduler.ACTION_WATCHDOG) {
            ReminderDiagnostics.markReceiver(context)
            OrderReminderRescheduleWorker.enqueue(context)
            return
        }

        if (intent.action != OrderReminderScheduler.ACTION_SHOW_REMINDER) {
            return
        }

        val reminder = OrderReminder.fromIntent(intent)
        if (reminder == null) {
            ReminderDiagnostics.markFailure(context, "receiver: invalid reminder payload")
            return
        }

        ReminderDiagnostics.markReceiver(context)

        if (reminder.deadlineAtMillis <= System.currentTimeMillis()) return
        if (!OrderReminderScheduler.isForActiveAccount(context, reminder)) return
        if (OrderReminderScheduler.wasDelivered(context, reminder)) return

        OrderReminderNotifier.show(context, reminder)
    }
}

class OrderReminderSystemReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (
            action == AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
        ) {
            val alarmManager =
                context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            if (!alarmManager.canScheduleExactAlarms()) return
        }

        OrderReminderRescheduleWorker.enqueue(context)
    }
}
