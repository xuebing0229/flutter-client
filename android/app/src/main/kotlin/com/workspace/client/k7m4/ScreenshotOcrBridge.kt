package com.workspace.client.k7m4

import android.app.Activity
import android.graphics.BitmapFactory
import android.os.SystemClock
import com.paddle.ocr.EngineConfig
import com.paddle.ocr.PaddleOCR
import com.paddle.ocr.PaddleOCRConfig
import com.paddle.ocr.util.OpenCVUtils
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.io.File

/**
 * Android's only screenshot recognizer, directly using the official PP-OCRv6
 * Android SDK. Follows the upstream demo: initialize OpenCV, create model once,
 * recognize image bytes, reuse during a batch, and release after import.
 *
 * Flutter owns the screenshot card parsing; this native layer returns ONLY
 * raw text and original image coordinates, with no secondary engine or retries.
 */
class ScreenshotOcrBridge(private val activity: Activity) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val guard = Mutex()
    private val failureLog = OcrCrashDiagnostics(activity)
    private var ocr: PaddleOCR? = null

    fun configure(messenger: BinaryMessenger) {
        MethodChannel(messenger, "app.screenshot_ocr").setMethodCallHandler { call, reply ->
            when (call.method) {
                "lastCrashReport" -> {
                    // Android system exit records may include a previous Beta,
                    // which did not yet save pre-native checkpoints.
                    try {
                        reply.success(failureLog.lastFailureReport())
                    } catch (error: Throwable) {
                        reply.error("OCR_DIAGNOSTIC_FAILED", error.message, null)
                    }
                }
                "release" -> {
                    // The mutex serializes release with inference and with
                    // the next batch. Null the handle even if release throws.
                    scope.launch {
                        try {
                            guard.withLock {
                                failureLog.checkpoint("release_onnx_sessions")
                                releaseModel()
                                failureLog.finish()
                            }
                            reply.success(null)
                        } catch (error: Throwable) {
                            failureLog.finish()
                            reply.error(
                                "OFFICIAL_PPOCRV6_RELEASE_FAILED",
                                error.message ?: error.javaClass.simpleName,
                                null,
                            )
                        }
                    }
                }
                "recognize" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        reply.error("BAD_IMAGE", "请选择截图文件", null)
                    } else {
                        scope.launch {
                            try {
                                reply.success(guard.withLock {
                                    failureLog.checkpoint("recognize_requested")
                                    val output = recognize(path)
                                    failureLog.finish()
                                    output
                                })
                            } catch (error: Throwable) {
                                failureLog.finish()
                                reply.error(
                                    "OFFICIAL_PPOCRV6_FAILED",
                                    error.message ?: error.javaClass.simpleName,
                                    null,
                                )
                            }
                        }
                    }
                }
                else -> reply.notImplemented()
            }
        }
    }

    private suspend fun getOcr(): PaddleOCR {
        ocr?.let { return it }
        failureLog.checkpoint("opencv_load")
        check(OpenCVUtils.init(activity.applicationContext)) {
            "官方 PP-OCRv6 SDK 无法初始化 Android OpenCV"
        }
        failureLog.checkpoint("onnx_model_init")
        val loaded = PaddleOCR.create(
            context = activity.applicationContext,
            config = PaddleOCRConfig(
                detLimitSideLen = 1536,
                detLimitType = "max",
                recBatchSize = 1,
                recScoreThresh = 0.0f,
            ),
            engineConfig = EngineConfig(numThreads = 2),
            detModelAssetPath = "models/det/inference.onnx",
            recModelAssetPath = "models/rec/inference.onnx",
            recConfigAssetPath = "models/rec/inference.yml",
        )
        ocr = loaded
        failureLog.checkpoint("onnx_models_ready")
        return loaded
    }

    private suspend fun recognize(path: String): Map<String, Any> {
        val file = File(path)
        require(file.isFile && file.canRead()) { "截图不存在或不可读取" }
        failureLog.checkpoint("image_decode_bounds")
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        require(bounds.outWidth > 0 && bounds.outHeight > 0) { "无法读取截图尺寸" }

        // Same original encoded image-byte route as upstream OCRViewModel:
        // OpenCV performs decoding, no intermediate Android Bitmap conversion.
        val bytes = file.readBytes()
        val start = SystemClock.elapsedRealtime()
        val engine = getOcr()
        failureLog.checkpoint("onnx_recognize_image")
        val result = engine.recognize(bytes)
        failureLog.checkpoint("ocr_result_box_conversion")

        val lines = result.results.mapNotNull { row ->
            if (row.text.isBlank()) return@mapNotNull null
            val left = row.box.points.minOf { it.x }.toDouble().coerceIn(0.0, bounds.outWidth.toDouble())
            val right = row.box.points.maxOf { it.x }.toDouble().coerceIn(0.0, bounds.outWidth.toDouble())
            val top = row.box.points.minOf { it.y }.toDouble().coerceIn(0.0, bounds.outHeight.toDouble())
            val bottom = row.box.points.maxOf { it.y }.toDouble().coerceIn(0.0, bounds.outHeight.toDouble())
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
            "imageWidth" to bounds.outWidth,
            "imageHeight" to bounds.outHeight,
            "lines" to lines,
            "nativeTrace" to listOf(
                "唯一引擎：官方 PaddleOCR PP-OCRv6 Small Android SDK (ONNX Runtime)",
                "识别行数：${result.lineCount}",
                "模型初始化：${result.coldLoadTimeMs} ms",
                "检测：${result.detectionTimeMs} ms",
                "识别：${result.recognitionTimeMs} ms",
                "推理总耗时：${result.totalTimeMs} ms",
                "本轮总耗时：${SystemClock.elapsedRealtime() - start} ms",
                "检测张量：${result.detInputShape}",
            ),
        )
    }

    private suspend fun releaseModel() {
        val previous = ocr
        ocr = null
        previous?.release()
    }

    // Defensive Activity teardown only. Normal release is Flutter's
    // explicit 'release' call after all screenshots in the batch.
    fun close() {
        scope.launch {
            guard.withLock { releaseModel() }
        }
    }
}
