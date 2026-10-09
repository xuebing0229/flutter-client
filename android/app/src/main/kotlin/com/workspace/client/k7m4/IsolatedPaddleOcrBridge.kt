package com.workspace.client.k7m4

import android.app.Activity
import android.app.ActivityManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import android.os.RemoteException
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** The app remains alive if the isolated OCR native process dies. */
class IsolatedPaddleOcrBridge(private val activity: Activity) {
    private data class Pending(val path: String, val reply: MethodChannel.Result)

    private val waiting = linkedMapOf<Int, Pending>()
    private var sequence = 0
    private var binding = false
    private var remote: Messenger? = null

    private val responses = Messenger(Handler(Looper.getMainLooper()) { message ->
        val id = message.data.getInt("request_id")
        val pending = waiting.remove(id)
        if (pending != null) {
            when (message.what) {
                IsolatedPaddleOcrService.SUCCESS -> pending.reply.success(
                    mapOf(
                        "results" to message.data.getString("results", "[]"),
                        "detectionMs" to message.data.getInt("detection_ms"),
                        "recognitionMs" to message.data.getInt("recognition_ms"),
                    )
                )
                else -> pending.reply.error(
                    "PADDLE_RECOGNITION_FAILED",
                    message.data.getString("error") ?: "Unknown OCR error",
                    null,
                )
            }
        }
        true
    })

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            remote = binder?.let(::Messenger)
            if (remote == null) {
                failAll("PADDLE_BIND_FAILED", "OCR service returned no Binder")
                return
            }
            // Only send once bound; requests may have arrived during startup.
            for ((id, pending) in waiting.toMap()) send(id, pending)
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            remote = null
            failAll(
                "PADDLE_PROCESS_DIED",
                "PaddleOCR 原生子进程已异常退出，已安全返回应用。请复制诊断查看原因。",
            )
        }

        override fun onBindingDied(name: ComponentName?) {
            onServiceDisconnected(name)
            if (binding) {
                runCatching { activity.unbindService(this) }
                binding = false
            }
        }

        override fun onNullBinding(name: ComponentName?) {
            remote = null
            failAll("PADDLE_BIND_FAILED", "OCR service could not bind")
        }
    }

    fun configure(messenger: BinaryMessenger) {
        MethodChannel(messenger, "app.paddle_isolated_ocr")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "recognize" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("BAD_PATH", "No image selected", null)
                        } else {
                            recognize(path, result)
                        }
                    }
                    "recentExit" -> result.success(recentExit())
                    else -> result.notImplemented()
                }
            }
    }

    private fun recognize(path: String, result: MethodChannel.Result) {
        val id = ++sequence
        val pending = Pending(path, result)
        waiting[id] = pending
        val existing = remote
        if (existing != null) {
            send(id, pending)
        } else if (!binding) {
            binding = try {
                activity.bindService(
                    Intent(activity, IsolatedPaddleOcrService::class.java),
                    connection,
                    Context.BIND_AUTO_CREATE,
                )
            } catch (error: Exception) {
                failAll("PADDLE_BIND_FAILED", error.message ?: "Cannot start OCR service")
                false
            }
            if (!binding) {
                failAll("PADDLE_BIND_FAILED", "Cannot bind OCR service")
            }
        }
    }

    private fun send(id: Int, pending: Pending) {
        val bound = remote ?: return
        val msg = Message.obtain(null, IsolatedPaddleOcrService.RECOGNIZE).apply {
            data = android.os.Bundle().apply {
                putInt("request_id", id)
                putString("path", pending.path)
            }
            replyTo = responses
        }
        try {
            bound.send(msg)
        } catch (error: RemoteException) {
            remote = null
            failAll("PADDLE_PROCESS_DIED", "PaddleOCR 子进程已断开：" + error.message)
        }
    }

    private fun failAll(code: String, message: String) {
        val requests = waiting.values.toList()
        waiting.clear()
        for (request in requests) request.reply.error(code, message, null)
    }

    // Android 11+ keeps the reason for previous app and OCR child-process exits.
    // Reports process names and reasons only, not screenshots or user content.
    private fun recentExit(): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            return "当前 Android 版本不支持系统进程退出历史。"
        }
        return try {
            val manager = activity.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val entries = manager.getHistoricalProcessExitReasons(null, 0, 12)
                .filter { entry ->
                    entry.processName == activity.packageName + ":paddle_ocr"
                }
                .take(3)
            if (entries.isEmpty()) {
                "Android 尚未记录 PaddleOCR 子进程的退出原因。"
            } else {
                entries.joinToString("\n") { entry ->
                    "PaddleOCR 子进程退出：reason=" + entry.reason +
                        " status=" + entry.status +
                        " time=" + java.text.SimpleDateFormat(
                            "yyyy-MM-dd HH:mm:ss",
                            java.util.Locale.ROOT,
                        ).format(java.util.Date(entry.timestamp)) +
                        " description=" + (entry.description ?: "无")
                }
            }
        } catch (error: Exception) {
            "读取 Android 退出记录失败：" + error.message
        }
    }

    fun close() {
        failAll("PADDLE_CLOSED", "OCR screen is closing")
        if (binding) {
            runCatching { activity.unbindService(connection) }
            binding = false
        }
        remote = null
    }
}
