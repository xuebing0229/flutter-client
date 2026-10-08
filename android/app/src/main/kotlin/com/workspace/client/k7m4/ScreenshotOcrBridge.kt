package com.workspace.client.k7m4

import android.app.Activity
import android.graphics.BitmapFactory
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Android OCR with the *bundled* ML Kit Chinese recognizer. No image data
 * leaves this phone. The Flutter layer owns parsing, validation and import.
 * Use one shared result only after ML Kit's async recognition completes.
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

    private fun recognize(path: String, result: MethodChannel.Result) {
        val file = File(path)
        if (!file.isFile || !file.canRead()) {
            result.error("IMAGE_MISSING", "截图文件不存在", null)
            return
        }

        // Downsample unusually large screenshot images to limit memory usage.
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
        recognizer.process(InputImage.fromBitmap(bitmap, 0))
            .addOnSuccessListener { detected ->
                val lines = ArrayList<Map<String, Any>>()
                for (block in detected.textBlocks) {
                    for (line in block.lines) {
                        val bounds = line.boundingBox ?: continue
                        lines.add(mapOf(
                            "text" to line.text,
                            "left" to bounds.left.toDouble(),
                            "top" to bounds.top.toDouble(),
                            "right" to bounds.right.toDouble(),
                            "bottom" to bounds.bottom.toDouble()
                        ))
                    }
                }
                result.success(mapOf(
                    "imageWidth" to bitmap.width,
                    "imageHeight" to bitmap.height,
                    "lines" to lines
                ))
            }
            .addOnFailureListener { error ->
                result.error("OCR_FAILED", error.message ?: "本地文字识别失败", null)
            }
            .addOnCompleteListener {
                recognizer.close()
                bitmap.recycle()
            }
    }
}
