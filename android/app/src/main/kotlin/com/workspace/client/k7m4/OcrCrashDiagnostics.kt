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
        val relevant = records.filter {
            it.processName == appContext.packageName &&
                it.reason in listOf(
                    ApplicationExitInfo.REASON_CRASH,
                    ApplicationExitInfo.REASON_CRASH_NATIVE,
                    ApplicationExitInfo.REASON_LOW_MEMORY,
                    ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE,
                ) &&
                System.currentTimeMillis() - it.timestamp < 24L * 3600L * 1000L
        }
        val matched = relevant.firstOrNull {
            previous && it.pid == pid && it.timestamp >= stamp - 120_000L
        }
        // If the previous version was too old to write breadcrumbs, still
        // surface Android's own most recent process exit, if available.
        val chosen = matched ?: if (!previous) relevant.maxByOrNull { it.timestamp } else null
        if (!previous && chosen == null) return null

        val pageSize = runCatching { Os.sysconf(OsConstants._SC_PAGESIZE) }.getOrDefault(-1L)
        val date = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.ROOT)
        return buildString {
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
                val tombstoneSummary = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    runCatching {
                        chosen.traceInputStream?.use { input ->
                            parseNativeTombstone(input.readNBytes(4 * 1024 * 1024))
                        }
                    }.getOrNull()
                } else null
                appendLine("原生 tombstone 可提取：${tombstoneSummary != null}")
                if (tombstoneSummary != null) {
                    appendLine("--- 原生 tombstone 摘要 ---")
                    append(tombstoneSummary)
                    if (!tombstoneSummary.endsWith("\n")) appendLine()
                }
            }
        }
    }
    private data class NativeFrame(
        val relPc: Long?,
        val function: String?,
        val functionOffset: Long?,
        val file: String?,
        val buildId: String?,
    )

    private data class NativeThread(
        val id: Int?,
        val name: String?,
        val frames: List<NativeFrame>,
    )

    /**
     * ApplicationExitInfo returns Android native tombstones as protobuf on
     * API 31+. Parse only signal/abort/cause/crashing-thread/backtrace fields.
     * Logs, memory dumps, fds and command arguments are intentionally ignored.
     */
    private fun parseNativeTombstone(bytes: ByteArray): String? {
        if (bytes.isEmpty()) return null
        val reader = ProtoReader(bytes)
        var crashingTid: Int? = null
        var signalNumber: Int? = null
        var signalName: String? = null
        var signalCode: Int? = null
        var signalCodeName: String? = null
        var abortMessage: String? = null
        val causes = mutableListOf<String>()
        val threads = linkedMapOf<Int, NativeThread>()

        while (!reader.done()) {
            val tag = reader.readVarintOrNull() ?: break
            val field = (tag ushr 3).toInt()
            val wire = (tag and 7L).toInt()
            when (field) {
                6 -> if (wire == 0) crashingTid = reader.readVarintOrNull()?.toInt()
                10 -> if (wire == 2) {
                    val signal = ProtoReader(reader.readBytesOrNull() ?: ByteArray(0))
                    while (!signal.done()) {
                        val st = signal.readVarintOrNull() ?: break
                        val sf = (st ushr 3).toInt()
                        val sw = (st and 7L).toInt()
                        when (sf) {
                            1 -> if (sw == 0) signalNumber = signal.readVarintOrNull()?.toInt()
                            2 -> if (sw == 2) signalName = signal.readStringOrNull()
                            3 -> if (sw == 0) signalCode = signal.readVarintOrNull()?.toInt()
                            4 -> if (sw == 2) signalCodeName = signal.readStringOrNull()
                            else -> signal.skip(sw)
                        }
                    }
                }
                14 -> if (wire == 2) abortMessage = reader.readStringOrNull()
                15 -> if (wire == 2) {
                    val cause = ProtoReader(reader.readBytesOrNull() ?: ByteArray(0))
                    while (!cause.done()) {
                        val ct = cause.readVarintOrNull() ?: break
                        val cf = (ct ushr 3).toInt()
                        val cw = (ct and 7L).toInt()
                        if (cf == 1 && cw == 2) {
                            cause.readStringOrNull()?.takeIf { it.isNotBlank() }?.let(causes::add)
                        } else {
                            cause.skip(cw)
                        }
                    }
                }
                16 -> if (wire == 2) {
                    parseThreadMapEntry(reader.readBytesOrNull() ?: ByteArray(0))?.let { (key, thread) ->
                        threads[key] = thread
                    }
                }
                else -> reader.skip(wire)
            }
        }

        val crashing = crashingTid?.let(threads::get)
            ?: threads.values.firstOrNull { it.frames.isNotEmpty() }
        if (signalNumber == null && signalName == null && abortMessage == null && crashing == null) return null

        return buildString {
            appendLine("signal：${signalName ?: "未知"} (${signalNumber ?: -1})" +
                if (signalCode != null || !signalCodeName.isNullOrBlank())
                    "；code=${signalCodeName ?: "未知"} (${signalCode ?: -1})"
                else "")
            if (!abortMessage.isNullOrBlank()) appendLine("abort message：$abortMessage")
            causes.take(4).forEach { appendLine("cause：$it") }
            if (crashing != null) {
                appendLine("crashing tid：${crashing.id ?: crashingTid ?: -1}" +
                    if (!crashing.name.isNullOrBlank()) "；thread=${crashing.name}" else "")
                crashing.frames.take(16).forEachIndexed { index, frame ->
                    append("#")
                    append(index.toString().padStart(2, '0'))
                    append(" ")
                    if (frame.relPc != null) append("pc 0x${frame.relPc.toString(16)} ")
                    append(frame.file ?: "<unknown>")
                    if (!frame.function.isNullOrBlank()) {
                        append(" (")
                        append(frame.function)
                        if (frame.functionOffset != null && frame.functionOffset != 0L) {
                            append("+")
                            append(frame.functionOffset)
                        }
                        append(")")
                    }
                    if (!frame.buildId.isNullOrBlank()) append(" [BuildId ${frame.buildId}]")
                    appendLine()
                }
            }
        }
    }

    private fun parseThreadMapEntry(bytes: ByteArray): Pair<Int, NativeThread>? {
        val reader = ProtoReader(bytes)
        var key: Int? = null
        var thread: NativeThread? = null
        while (!reader.done()) {
            val tag = reader.readVarintOrNull() ?: break
            val field = (tag ushr 3).toInt()
            val wire = (tag and 7L).toInt()
            when (field) {
                1 -> if (wire == 0) key = reader.readVarintOrNull()?.toInt()
                2 -> if (wire == 2) thread = parseNativeThread(reader.readBytesOrNull() ?: ByteArray(0))
                else -> reader.skip(wire)
            }
        }
        val resolved = key ?: thread?.id ?: return null
        return resolved to (thread ?: NativeThread(resolved, null, emptyList()))
    }

    private fun parseNativeThread(bytes: ByteArray): NativeThread {
        val reader = ProtoReader(bytes)
        var id: Int? = null
        var name: String? = null
        val frames = mutableListOf<NativeFrame>()
        while (!reader.done()) {
            val tag = reader.readVarintOrNull() ?: break
            val field = (tag ushr 3).toInt()
            val wire = (tag and 7L).toInt()
            when (field) {
                1 -> if (wire == 0) id = reader.readVarintOrNull()?.toInt()
                2 -> if (wire == 2) name = reader.readStringOrNull()
                4 -> if (wire == 2) parseNativeFrame(reader.readBytesOrNull() ?: ByteArray(0))?.let(frames::add)
                else -> reader.skip(wire)
            }
        }
        return NativeThread(id, name, frames)
    }

    private fun parseNativeFrame(bytes: ByteArray): NativeFrame? {
        val reader = ProtoReader(bytes)
        var relPc: Long? = null
        var function: String? = null
        var functionOffset: Long? = null
        var file: String? = null
        var buildId: String? = null
        while (!reader.done()) {
            val tag = reader.readVarintOrNull() ?: break
            val field = (tag ushr 3).toInt()
            val wire = (tag and 7L).toInt()
            when (field) {
                1 -> if (wire == 0) relPc = reader.readVarintOrNull()
                4 -> if (wire == 2) function = reader.readStringOrNull()
                5 -> if (wire == 0) functionOffset = reader.readVarintOrNull()
                6 -> if (wire == 2) file = reader.readStringOrNull()
                8 -> if (wire == 2) buildId = reader.readStringOrNull()
                else -> reader.skip(wire)
            }
        }
        if (relPc == null && function == null && file == null) return null
        return NativeFrame(relPc, function, functionOffset, file, buildId)
    }

    private class ProtoReader(private val bytes: ByteArray) {
        private var index = 0

        fun done(): Boolean = index >= bytes.size

        fun readVarintOrNull(): Long? {
            var out = 0L
            var shift = 0
            while (index < bytes.size && shift <= 63) {
                val b = bytes[index++].toInt() and 0xff
                out = out or ((b and 0x7f).toLong() shl shift)
                if (b and 0x80 == 0) return out
                shift += 7
            }
            index = bytes.size
            return null
        }

        fun readBytesOrNull(): ByteArray? {
            val length = readVarintOrNull()?.toInt() ?: return null
            if (length < 0 || length > bytes.size - index) {
                index = bytes.size
                return null
            }
            val result = bytes.copyOfRange(index, index + length)
            index += length
            return result
        }

        fun readStringOrNull(): String? =
            readBytesOrNull()?.toString(Charsets.UTF_8)

        fun skip(wire: Int) {
            when (wire) {
                0 -> readVarintOrNull()
                1 -> index = (index + 8).coerceAtMost(bytes.size)
                2 -> {
                    val length = readVarintOrNull()?.toInt() ?: return
                    if (length < 0) {
                        index = bytes.size
                    } else {
                        index = (index + length).coerceAtMost(bytes.size)
                    }
                }
                5 -> index = (index + 4).coerceAtMost(bytes.size)
                else -> index = bytes.size
            }
        }
    }

}
