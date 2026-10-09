package com.workspace.client.k7m4

import android.app.Activity
import android.graphics.BitmapFactory
import android.os.SystemClock
import com.equationl.ncnnandroidppocr.OCR
import com.equationl.ncnnandroidppocr.bean.Device
import com.equationl.ncnnandroidppocr.bean.DrawModel
import com.equationl.ncnnandroidppocr.bean.ImageSize
import com.equationl.ncnnandroidppocr.bean.ModelType
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.io.File

/** One offline Android OCR path: PP-OCRv5 Mobile using the existing ncnn SDK. */
class ScreenshotOcrBridge(private val activity: Activity) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val mutex = Mutex()
    private var engine: OCR? = null

    fun configure(messenger: BinaryMessenger) {
        MethodChannel(messenger, "app.screenshot_ocr").setMethodCallHandler { call, result ->
            when (call.method) {
                "recognize" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("BAD_IMAGE", "请选择截图文件", null)
                    } else {
                        scope.launch {
                            try {
                                result.success(mutex.withLock { recognize(path) })
                            } catch (error: Throwable) {
                                result.error("OCR_FAILED", error.message ?: error.javaClass.simpleName, null)
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun getEngine(): OCR {
        engine?.let { return it }
        val created = OCR()
        check(created.initModelFromAssert(
            activity.assets, ModelType.Mobile, ImageSize.Size1080, Device.CPU
        )) { "PP-OCRv5 ncnn 离线模型初始化失败" }
        engine = created
        return created
    }

    private fun recognize(path: String): Map<String, Any> {
        val file = File(path)
        require(file.isFile && file.canRead()) { "截图不存在或无法读取" }
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        require(bounds.outWidth > 0 && bounds.outHeight > 0) { "截图格式无法识别" }

        var sample = 1
        while (bounds.outWidth / sample > 2400 || bounds.outHeight / sample > 4000) sample *= 2
        val bitmap = BitmapFactory.decodeFile(
            path, BitmapFactory.Options().apply { inSampleSize = sample }
        ) ?: throw IllegalArgumentException("图片解码失败")
        val started = SystemClock.elapsedRealtime()
        try {
            val found = getEngine().detectBitmap(bitmap, DrawModel.None)
                ?: error("PP-OCRv5 ncnn 推理未返回结果")
            val lines = found.textLines.mapNotNull { row ->
                if (row.text.isBlank() || row.points.isEmpty()) return@mapNotNull null
                val left = row.points.minOf { it.x }.toDouble().coerceIn(0.0, bitmap.width.toDouble())
                val right = row.points.maxOf { it.x }.toDouble().coerceIn(0.0, bitmap.width.toDouble())
                val top = row.points.minOf { it.y }.toDouble().coerceIn(0.0, bitmap.height.toDouble())
                val bottom = row.points.maxOf { it.y }.toDouble().coerceIn(0.0, bitmap.height.toDouble())
                if (right <= left || bottom <= top) return@mapNotNull null
                mapOf(
                    "text" to row.text,
                    "left" to left,
                    "right" to right,
                    "top" to top,
                    "bottom" to bottom,
                    "recoveredFromCrop" to false,
                )
            }.sortedWith(compareBy<Map<String, Any>> { it["top"] as Double }
                .thenBy { it["left"] as Double })
            return mapOf(
                "imageWidth" to bitmap.width,
                "imageHeight" to bitmap.height,
                "lines" to lines,
                "nativeTrace" to listOf(
                    "唯一引擎：PaddleOCR PP-OCRv5 Mobile / ncnn",
                    "识别行数：${lines.size}",
                    "SDK 推理耗时：${found.inferenceTime} ms",
                    "总耗时：${SystemClock.elapsedRealtime() - started} ms",
                ),
            )
        } finally {
            bitmap.recycle()
        }
    }

    fun close() {
        scope.launch {
            mutex.withLock {
                engine?.release()
                engine = null
            }
        }
    }
}
