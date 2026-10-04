package com.workspace.client.k7m4

import android.Manifest
import android.app.AlarmManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.TimeUnit

class OrderReminderBridge(
    private val activity: FlutterActivity,
) {
    companion object {
        private const val CHANNEL = "app.order_reminders"
        private const val REQUEST_NOTIFICATIONS = 8301
    }

    private var pendingPermissionResult: MethodChannel.Result? = null

    fun configure(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "ensurePermission" -> ensurePermission(result)
                "sync" -> sync(call, result)
                "clearActiveAccount" -> {
                    OrderReminderScheduler.clearActiveAccount(activity)
                    result.success(null)
                }
                "activateAccount" -> activateAccount(call, result)
                "clearAll" -> clearAll(call, result)
                "getDiagnostics" -> result.success(ReminderDiagnostics.snapshot(activity))
                "scheduleDiagnosticTest" -> scheduleDiagnosticTest(call, result)
                "openBatteryOptimizationSettings" -> openBatteryOptimizationSettings(result)
                "openExactAlarmSettings" -> openExactAlarmSettings(result)
                "openNotificationSettings" -> openNotificationSettings(result)
                "markBackgroundGuideShown" -> {
                    ReminderDiagnostics.markBackgroundGuideShown(activity)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun ensurePermission(result: MethodChannel.Result) {
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            if (pendingPermissionResult != null) {
                result.error(
                    "PERMISSION_REQUEST_BUSY",
                    "Notification permission request already in progress.",
                    null,
                )
                return
            }

            pendingPermissionResult = result
            activity.requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                REQUEST_NOTIFICATIONS,
            )
            return
        }

        requestExactAlarmAccessIfNeeded()
        result.success(true)
    }

    private fun requestExactAlarmAccessIfNeeded() {
        if (
            Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
        ) {
            return
        }

        val manager =
            activity.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        if (manager.canScheduleExactAlarms()) return

        runCatching {
            activity.startActivity(
                Intent(
                    Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                    Uri.parse("package:${activity.packageName}"),
                ),
            )
        }.onFailure {
            ReminderDiagnostics.markFailure(activity, "open exact alarm settings: ${it.message}")
        }
    }

    private fun sync(call: MethodCall, result: MethodChannel.Result) {
        try {
            val accountId = call.argument<String>("accountId").orEmpty()
            if (accountId.isBlank()) {
                result.error(
                    "REMINDER_ACCOUNT_MISSING",
                    "Reminder sync is missing accountId.",
                    null,
                )
                return
            }

            val raw = call.argument<List<Any?>>("reminders")
                ?: throw IllegalArgumentException("Reminder sync is missing reminders.")
            val reminders = raw.map { item ->
                val map = item as? Map<*, *>
                    ?: throw IllegalArgumentException("Reminder payload is invalid.")
                val key = map["key"] as? String
                    ?: throw IllegalArgumentException("Reminder key is missing.")
                val title = map["title"] as? String
                    ?: throw IllegalArgumentException("Reminder title is missing.")
                val triggerAt = (map["triggerAtMillis"] as? Number)?.toLong()
                    ?: throw IllegalArgumentException("Reminder trigger time is missing.")
                val deadlineAt = (map["deadlineAtMillis"] as? Number)?.toLong()
                    ?: throw IllegalArgumentException("Reminder deadline is missing.")
                val kind = map["kind"] as? String
                    ?: throw IllegalArgumentException("Reminder kind is missing.")
                val label = map["label"] as? String
                    ?: throw IllegalArgumentException("Reminder label is missing.")

                OrderReminder(
                    key = key,
                    title = title,
                    triggerAtMillis = triggerAt,
                    deadlineAtMillis = deadlineAt,
                    kind = kind,
                    label = label,
                )
            }

            if (reminders.any { reminder ->
                    reminder.kind != "diagnostic" &&
                        !reminder.key.startsWith("$accountId:")
                }
            ) {
                result.error(
                    "REMINDER_ACCOUNT_MISMATCH",
                    "Reminder payload belongs to another account.",
                    null,
                )
                return
            }

            OrderReminderScheduler.sync(activity, accountId, reminders)
            result.success(null)
        } catch (error: Exception) {
            ReminderDiagnostics.markFailure(activity, "sync: ${error.message}")
            result.error(
                "REMINDER_SYNC_FAILED",
                error.message ?: "Failed to schedule reminders.",
                null,
            )
        }
    }

    private fun activateAccount(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val accountId = call.argument<String>("accountId").orEmpty()
        if (accountId.isBlank()) {
            result.error(
                "REMINDER_ACCOUNT_MISSING",
                "Reminder activation is missing accountId.",
                null,
            )
            return
        }

        OrderReminderScheduler.activateAccount(activity, accountId)
        result.success(null)
    }

    private fun clearAll(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val accountId = call.argument<String>("accountId").orEmpty()
        if (accountId.isBlank()) {
            result.error(
                "REMINDER_ACCOUNT_MISSING",
                "Reminder clear is missing accountId.",
                null,
            )
            return
        }

        OrderReminderScheduler.clearIfActive(activity, accountId)
        result.success(null)
    }

    private fun scheduleDiagnosticTest(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        try {
            val requestedDelay =
                (call.argument<Number>("delaySeconds")?.toLong() ?: 60L)
                    .coerceIn(10L, 600L)
            val now = System.currentTimeMillis()
            val triggerAt = now + TimeUnit.SECONDS.toMillis(requestedDelay)
            val reminder = OrderReminder(
                key = "diagnostic:$now",
                title = "提醒诊断测试",
                triggerAtMillis = triggerAt,
                deadlineAtMillis = triggerAt + TimeUnit.MINUTES.toMillis(10),
                kind = "diagnostic",
                label = "测试",
            )

            ReminderDiagnostics.beginTest(activity)
            OrderReminderScheduler.scheduleStandalone(activity, reminder)

            result.success(ReminderDiagnostics.snapshot(activity))
        } catch (error: Exception) {
            ReminderDiagnostics.markFailure(activity, "diagnostic schedule: ${error.message}")
            result.error(
                "DIAGNOSTIC_TEST_FAILED",
                error.message ?: "Failed to schedule diagnostic reminder.",
                null,
            )
        }
    }

    private fun openBatteryOptimizationSettings(result: MethodChannel.Result) {
        runCatching {
            activity.startActivity(
                Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS),
            )
        }.onSuccess {
            result.success(null)
        }.onFailure {
            ReminderDiagnostics.markFailure(activity, "open battery settings: ${it.message}")
            result.error("SETTINGS_UNAVAILABLE", it.message, null)
        }
    }

    private fun openExactAlarmSettings(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            result.success(null)
            return
        }

        runCatching {
            activity.startActivity(
                Intent(
                    Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                    Uri.parse("package:${activity.packageName}"),
                ),
            )
        }.onSuccess {
            result.success(null)
        }.onFailure {
            ReminderDiagnostics.markFailure(activity, "open exact alarm settings: ${it.message}")
            result.error("SETTINGS_UNAVAILABLE", it.message, null)
        }
    }

    private fun openNotificationSettings(result: MethodChannel.Result) {
        runCatching {
            val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
                    .putExtra(
                        Settings.EXTRA_CHANNEL_ID,
                        OrderReminderNotifier.CHANNEL_ID,
                    )
            } else {
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
            }
            activity.startActivity(intent)
        }.onSuccess {
            result.success(null)
        }.onFailure {
            ReminderDiagnostics.markFailure(activity, "open notification settings: ${it.message}")
            result.error("SETTINGS_UNAVAILABLE", it.message, null)
        }
    }

    fun onRequestPermissionsResult(
        requestCode: Int,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != REQUEST_NOTIFICATIONS) return false

        val pending = pendingPermissionResult ?: return true
        pendingPermissionResult = null
        val granted =
            grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
        if (granted) {
            requestExactAlarmAccessIfNeeded()
        }
        pending.success(granted)
        return true
    }
}
