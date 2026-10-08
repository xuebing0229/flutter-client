package com.workspace.client.k7m4

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlin.math.abs
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Offline Chinese OCR. Huajia screenshots render tiny prices on the far
 * right of each row: a whole-screen ML Kit pass can miss those while finding
 * the much larger titles and dates. Retry only that strip at higher scale,
 * and translate its boxes back to the original bitmap coordinate system.
 */
class ScreenshotOcrBridge(private val activity: Activity) {
    fun configure(messenger: BinaryMessenger) {
        MethodChannel(messenger, "app.screenshot_ocr").setMethodCallHandler { call, result ->
            when (call.method) {
                "recognize" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("BAD_IMAGE", "请选择截图文件", null)
                    } else {
                        recognize(path, result)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private data class OcrLine(
        val text: String,
        val left: Double,
        val top: Double,
        val right: Double,
        val bottom: Double,
    ) {
        val centerY: Double get() = (top + bottom) / 2
        fun toMap(): Map<String, Any> = mapOf(
            "text" to text,
            "left" to left,
            "top" to top,
            "right" to right,
            "bottom" to bottom,
        )
    }

    private fun extractLines(
        detected: Text,
        horizontalOffset: Double = 0.0,
        scale: Double = 1.0,
    ): MutableList<OcrLine> {
        val lines = mutableListOf<OcrLine>()
        for (block in detected.textBlocks) {
            for (line in block.lines) {
                val box = line.boundingBox ?: continue
                lines.add(OcrLine(
                    line.text,
                    horizontalOffset + box.left / scale,
                    box.top / scale,
                    horizontalOffset + box.right / scale,
                    box.bottom / scale,
                ))
            }
        }
        return lines
    }

    private fun looksLikeHuajia(lines: List<OcrLine>): Boolean =
        lines.any {
            it.text.contains("我卖出的") ||
                it.text.contains("当前交付节点") ||
                it.text.contains("等待对方收稿")
        }

    private val moneyFragment = Regex("""^(?:[¥￥]\s*)?\d{1,7}(?:[.,]\d{1,2})?$|^[¥￥]$""")

    private fun recognize(path: String, result: MethodChannel.Result) {
        val file = File(path)
        if (!file.isFile || !file.canRead()) {
            result.error("IMAGE_MISSING", "截图文件不存在", null)
            return
        }

        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
            result.error("IMAGE_INVALID", "图片格式无法读取", null)
            return
        }
        var sample = 1
        while (bounds.outWidth / sample > 2400 || bounds.outHeight / sample > 4000) {
            sample *= 2
        }
        val bitmap = BitmapFactory.decodeFile(
            path,
            BitmapFactory.Options().apply { inSampleSize = sample }
        )
        if (bitmap == null) {
            result.error("IMAGE_INVALID", "图片解码失败", null)
            return
        }

        val recognizer = TextRecognition.getClient(
            ChineseTextRecognizerOptions.Builder().build()
        )
        fun finish(lines: List<OcrLine>) {
            result.success(mapOf(
                "imageWidth" to bitmap.width,
                "imageHeight" to bitmap.height,
                "lines" to lines.map { it.toMap() },
            ))
            recognizer.close()
            bitmap.recycle()
        }
        recognizer.process(InputImage.fromBitmap(bitmap, 0))
            .addOnSuccessListener { detected ->
                val originalLines = extractLines(detected)
                if (!looksLikeHuajia(originalLines) || bitmap.width < 300 ||
                    bitmap.height > 4200) {
                    finish(originalLines)
                    return@addOnSuccessListener
                }

                // Keep the entire vertical span (multiple cards) and upscale
                // just the right 42% to make the tiny ¥30/¥88 labels readable.
                // Bound the scaled height to avoid huge temporary bitmaps.
                val cropX = (bitmap.width * 0.58).roundToInt()
                val cropWidth = bitmap.width - cropX
                val requestedScale = min(2.2, 4400.0 / bitmap.height)
                if (requestedScale <= 1.05) {
                    finish(originalLines)
                    return@addOnSuccessListener
                }
                var zoomed: Bitmap? = null
                try {
                    val strip = Bitmap.createBitmap(
                        bitmap, cropX, 0, cropWidth, bitmap.height
                    )
                    zoomed = Bitmap.createScaledBitmap(
                        strip,
                        (cropWidth * requestedScale).roundToInt(),
                        (bitmap.height * requestedScale).roundToInt(),
                        true,
                    )
                    if (strip !== zoomed) strip.recycle()
                    val scaledBitmap = zoomed ?: throw IllegalStateException("Crop decode failed")
                    val trueScale = scaledBitmap.height.toDouble() / bitmap.height
                    recognizer.process(InputImage.fromBitmap(scaledBitmap, 0))
                        .addOnSuccessListener { retry ->
                            val combined = originalLines.toMutableList()
                            for (candidate in extractLines(
                                retry, cropX.toDouble(), trueScale,
                            )) {
                                val raw = candidate.text.trim()
                                if (!moneyFragment.matches(raw) ||
                                    candidate.left < bitmap.width * 0.67) {
                                    continue
                                }
                                // Duplicate recognition is not a second amount.
                                if (combined.any {
                                    it.text.trim() == raw &&
                                        abs(it.centerY - candidate.centerY) < 20 &&
                                        abs(it.left - candidate.left) < 45
                                }) continue
                                combined.add(candidate)
                            }
                            finish(combined)
                        }
                        .addOnFailureListener {
                            // Recognition on the full image already succeeded.
                            finish(originalLines)
                        }
                        .addOnCompleteListener {
                            scaledBitmap.recycle()
                        }
                } catch (_: Exception) {
                    zoomed?.recycle()
                    finish(originalLines)
                }
            }
            .addOnFailureListener { error ->
                result.error("OCR_FAILED", error.message ?: "本地文字识别失败", null)
                recognizer.close()
                bitmap.recycle()
            }
    }
}
