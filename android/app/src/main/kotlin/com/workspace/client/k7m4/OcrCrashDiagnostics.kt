package com.workspace.client.k7m4

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import android.os.Debug
import android.os.Process
import android.system.Os
import android.system.OsConstants
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Records crash checkpoints OUTSIDE of the official SDK.
 *
 * A native SIGABRT/SIGSEGV or LMK cannot be caught by try/catch.
 * Persist the last pre-JNI stage so the NEXT app process can retrieve the
 * Android system's process-exit reason. Never persist screenshots, OCR text,
 * usernames, order details or image paths. The user must explicitly choose
 * to copy the local report.
 */
internal class OcrCrashDiagnostics(context: Context) {
    private val appContext = context.applicationContext
    private val preferences =
        appContext.getSharedPreferences("ocr_native_failure_report_v1", Context.MODE_PRIVATE)

    fun checkpoint(stage: String) {
        val mem = Debug.MemoryInfo()
        Debug.getMemoryInfo(mem)
        // Synchronous commit matters: if native C++ aborts one millisecond later,
        // an asynchronous apply() is not guaranteed to have reached disk.
        preferences.edit()
            .putInt("pid", Process.myPid())
            .putLong("updatedAtMs", System.currentTimeMillis())
            .putString("stage", stage)
            .putInt("pssKb", mem.totalPss)
            .commit()
    }

    fun finish() {
        preferences.edit()
            .remove("pid")
            .remove("updatedAtMs")
            .remove("stage")
            .remove("pssKb")
            .commit()
    }

    fun lastFailureReport(): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        val pid = preferences.getInt("pid", 0)
        val stage = preferences.getString("stage", null)
        val stamp = preferences.getLong("updatedAtMs", 0L)
        val previous = pid != 0 && pid != Process.myPid() && !stage.isNullOrEmpty()
        val manager = appContext.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val records = manager.getHistoricalProcessExitReasons(null, 0, 16)
        val reportedPid = preferences.getInt("reportedExitPid", -1)
        val reportedTimestamp = preferences.getLong("reportedExitTimestamp", -1L)
        val relevant = records.filter {
            it.processName == appContext.packageName &&
                it.reason in listOf(
                    ApplicationExitInfo.REASON_CRASH,
                    ApplicationExitInfo.REASON_CRASH_NATIVE,
                    ApplicationExitInfo.REASON_LOW_MEMORY,
                    ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE,
                ) &&
                System.currentTimeMillis() - it.timestamp < 24L * 3600L * 1000L &&
                !(it.pid == reportedPid && it.timestamp == reportedTimestamp)
        }
        val matched = relevant.firstOrNull {
            previous && it.pid == pid && it.timestamp >= stamp - 120_000L
        }
        // If an older app version did not write breadcrumbs, fall back to
        // Android's newest unreported exit record. Each exit is surfaced only
        // once, so reopening the import page never nags about the same crash.
        val chosen = matched ?: if (!previous) relevant.maxByOrNull { it.timestamp } else null
        if (chosen == null) return null

        val pageSize = runCatching { Os.sysconf(OsConstants._SC_PAGESIZE) }.getOrDefault(-1L)
        val date = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.ROOT)
        val report = buildString {
            appendLine("冒险者公会 · Android 原生 OCR 崩溃诊断")
            appendLine("版本：仅含系统退出信息和推理阶段，不包含订单/图片内容。")
            appendLine("Android：${Build.VERSION.SDK_INT}（${Build.VERSION.RELEASE}）")
            appendLine("设备：${Build.MANUFACTURER} ${Build.MODEL}")
            appendLine("ABI：${Build.SUPPORTED_ABIS.firstOrNull() ?: "未知"}；内存页：${pageSize} bytes")
            appendLine("运行时 Java 最大堆：${Runtime.getRuntime().maxMemory() / (1024 * 1024)} MiB")
            if (previous) {
                appendLine("上次 OCR 调用阶段：$stage")
                appendLine("上次调用时间：${date.format(Date(stamp))}")
                appendLine("上次 PID：$pid")
                appendLine("上次 OCR 阶段记录时总 PSS：${preferences.getInt("pssKb", -1)} KiB")
            } else {
                appendLine("上次 OCR 调用阶段：未知（当时版本未保存原生阶段）")
            }
            if (chosen == null) {
                appendLine("对应 Android 进程退出记录：未找到（可能已被系统覆盖）")
            } else {
                val reason = when (chosen.reason) {
                    ApplicationExitInfo.REASON_CRASH_NATIVE -> "REASON_CRASH_NATIVE"
                    ApplicationExitInfo.REASON_CRASH -> "REASON_CRASH"
                    ApplicationExitInfo.REASON_LOW_MEMORY -> "REASON_LOW_MEMORY"
                    ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE ->
                        "REASON_EXCESSIVE_RESOURCE_USAGE"
                    else -> "其他"
                }
                appendLine("Android 进程退出时间：${date.format(Date(chosen.timestamp))}")
                appendLine("进程退出原因：$reason（${chosen.reason}）")
                appendLine("退出状态/信号：${chosen.status}")
                appendLine("退出时系统记录 PSS/RSS：${chosen.pss}/${chosen.rss} KiB")
                appendLine("进程：${chosen.processName}")
                // Android 12+ native tombstones are a binary protobuf, not
                // UTF-8 text. Never misinterpret them as a human stack trace.
                val tombstoneAvailable = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    runCatching { chosen.traceInputStream?.use { true } == true }.getOrDefault(false)
                } else false
                appendLine("原生 tombstone 可提取：$tombstoneAvailable")
            }
        }
        preferences.edit()
            .putInt("reportedExitPid", chosen.pid)
            .putLong("reportedExitTimestamp", chosen.timestamp)
            .commit()
        // Old-process checkpoints are no longer useful once the matching
        // system exit has been captured into this report.
        if (previous && chosen.pid == pid) {
            preferences.edit()
                .remove("pid")
                .remove("updatedAtMs")
                .remove("stage")
                .remove("pssKb")
                .commit()
        }
        return report
    }
}
