package com.workspace.client.k7m4

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.Paint
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
        verticalOffset: Double = 0.0,
        scale: Double = 1.0,
    ): MutableList<OcrLine> {
        val lines = mutableListOf<OcrLine>()
        for (block in detected.textBlocks) {
            for (line in block.lines) {
                val box = line.boundingBox ?: continue
                lines.add(OcrLine(
                    line.text,
                    horizontalOffset + box.left / scale,
                    verticalOffset + box.top / scale,
                    horizontalOffset + box.right / scale,
                    verticalOffset + box.bottom / scale,
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

    private val moneyFragment = Regex("""^(?:[¥￥yY]\s*)?\d{1,7}(?:[.,]\d{1,2})?$|^[¥￥]$""")

    private fun looksLikeMiHuashiDetail(lines: List<OcrLine>, height: Int): Boolean {
        val hasCenteredOrderHeader = lines.any {
            it.text.trim() == "订单" && it.centerY < height * 0.14
        }
        val hasDetailContent = lines.any {
            it.text.contains("稿酬") || it.text.contains("约稿完成") ||
                it.text.contains("稿件夹") || it.text.contains("上传稿件") ||
                it.text.contains("联系企划方")
        }
        val hasPayment = lines.any {
            it.text.contains("稿酬") || it.text.contains("约稿完成") ||
                it.text.contains("已全额支付")
        }
        val hasMiTab = lines.any {
            it.text.contains("稿件夹") || it.text.contains("进程动态") ||
                it.text.contains("联系企划方")
        }
        val hasAttachment = lines.any {
            Regex("""\.(?:png|jpe?g|webp)\b""", RegexOption.IGNORE_CASE)
                .containsMatchIn(it.text)
        }
        // A truncated OCR header must not disable the only high-resolution
        // retry that can recover its artwork title and payment amount.
        return !looksLikeHuajia(lines) &&
            ((hasCenteredOrderHeader && hasDetailContent) ||
                (hasPayment && hasMiTab && hasAttachment))
    }

    private fun headingCandidate(
        lines: List<OcrLine>, width: Int, height: Int
    ): OcrLine? = lines
        .filter {
            it.text.contains("【") && it.left > width * 0.20 &&
                it.centerY > height * 0.075 && it.centerY < height * 0.30
        }
        .maxByOrNull {
            (if (it.text.contains("】")) 100 else 0) + it.text.length
        }

    private fun titleQuality(line: OcrLine?): Int {
        if (line == null) return -1
        val text = line.text.trim()
        val completeTag = text.contains("【") && text.contains("】")
        return (if (completeTag) 100 else 0) +
            text.length - (if (Regex("""【[^】]*[1lI丨][^】]*""").containsMatchIn(text)) 10 else 0)
    }

    /**
     * Retry only the order detail header at higher scale. This helps with
     * small artwork titles/Chinese buyer names without adding OCR duplicates
     * that would be mistaken for another order. Existing text wins unless
     * the crop actually yields a better bracketed title or missing fee.
     */
    private fun retryMiHuashiHeader(
        bitmap: Bitmap,
        recognizer: com.google.mlkit.vision.text.TextRecognizer,
        original: List<OcrLine>,
        done: (List<OcrLine>) -> Unit,
    ) {
        val cropX = (bitmap.width * 0.15).roundToInt()
        val cropY = (bitmap.height * 0.085).roundToInt()
        val cropWidth = bitmap.width - cropX
        val cropHeight = min(
            (bitmap.height * 0.37).roundToInt(),
            bitmap.height - cropY,
        )
        if (cropHeight <= 10 || cropWidth <= 30) {
            done(original)
            return
        }
        var zoom: Bitmap? = null
        try {
            val crop = Bitmap.createBitmap(bitmap, cropX, cropY, cropWidth, cropHeight)
            zoom = Bitmap.createScaledBitmap(crop, cropWidth * 2, cropHeight * 2, true)
            if (crop !== zoom) crop.recycle()
            val scaled = zoom ?: throw IllegalStateException("Crop scaling failed")
            recognizer.process(InputImage.fromBitmap(scaled, 0))
                .addOnSuccessListener { recognized ->
                    val corrected = original.toMutableList()
                    val zoomLines = extractLines(
                        recognized,
                        horizontalOffset = cropX.toDouble(),
                        verticalOffset = cropY.toDouble(),
                        scale = 2.0,
                    )
                    val oldTitle = headingCandidate(original, bitmap.width, bitmap.height)
                    val newTitle = headingCandidate(zoomLines, bitmap.width, bitmap.height)
                    if (newTitle != null && titleQuality(newTitle) > titleQuality(oldTitle)) {
                        if (oldTitle != null) corrected.remove(oldTitle)
                        corrected.add(newTitle)
                    }
                    // Do not add overlapping titles or duplicate clocks. Only
                    // add new fee recognition in the known upper payment row.
                    val oldHasFee = original.any {
                        it.centerY in (bitmap.height * 0.27)..(bitmap.height * 0.44) &&
                            Regex("""[¥￥]\s*\d+""").containsMatchIn(it.text)
                    }
                    if (!oldHasFee) {
                        for (line in zoomLines) {
                            if (line.centerY !in (bitmap.height * 0.27)..(bitmap.height * 0.44)) {
                                continue
                            }
                            if (!moneyFragment.matches(line.text.trim())) continue
                            if (corrected.any {
                                it.text.trim() == line.text.trim() &&
                                    abs(it.centerY - line.centerY) < 18
                            }) continue
                            corrected.add(line)
                        }
                    }
                    done(corrected)
                }
                .addOnFailureListener { done(original) }
                .addOnCompleteListener { scaled.recycle() }
        } catch (_: Exception) {
            zoom?.recycle()
            done(original)
        }
    }




    /**
     * MiHuashi listing OCR regularly loses one small buyer name, even when
     * the artwork title, fee and deadline are recognized perfectly.
     * Retry only the tiny buyer band above titles WITHOUT a buyer text box.
     * Unlike a full-image second pass, this never duplicates amounts/dates.
     */
    private fun looksLikeMiHuashiList(lines: List<OcrLine>): Boolean {
        if (looksLikeHuajia(lines)) return false
        val combined = lines.joinToString(" ") { it.text }
        return (combined.contains("购买时间") &&
            (combined.contains("截稿时间") || combined.contains("默认") ||
             combined.contains("接单时间"))) ||
            (combined.contains("定向企划") &&
             (combined.contains("全额支付") || combined.contains("企划名称")))
    }

    private fun possibleMiHuashiBuyer(text: String): Boolean {
        val value = text.trim()
        if (value.length < 2 || value.length > 32) return false
        if (Regex("""\d{4}[-/.年]\d|[¥￥]|[0-9]+%""").containsMatchIn(value)) return false
        return !listOf(
            "默认", "进行中", "已完成", "已中断", "添加备注", "全额支付",
            "接单时间", "购买时间", "截稿时间", "定向企划",
            "企划名称", "企划内容", "搜索", "待支付",
        ).any { value.contains(it) } && !value.contains("【") &&
            !value.contains("黑白摸鱼") && !value.contains("￥")
    }

    private fun retryMissingMiHuashiBuyers(
        bitmap: Bitmap,
        recognizer: com.google.mlkit.vision.text.TextRecognizer,
        initial: List<OcrLine>,
        done: (List<OcrLine>) -> Unit,
    ) {
        if (!looksLikeMiHuashiList(initial)) {
            done(initial)
            return
        }
        val width = bitmap.width
        val height = bitmap.height
        val artworkTitles = initial.filter { line ->
            line.centerY > height * 0.16 && line.centerY < height * 0.96 &&
                (line.text.trim().startsWith("【") ||
                    line.text.contains("定向企划")) &&
                line.text.length >= 8 &&
                line.right > width * 0.28
        }.sortedBy { it.centerY }
        // Keep the number of extra native OCR passes bounded on huge lists.
        val missing = artworkTitles.filter { title ->
            initial.none { line ->
                line.left < width * 0.42 &&
                    line.centerY >= title.centerY - 210 &&
                    line.centerY <= title.centerY - 58 &&
                    possibleMiHuashiBuyer(line.text)
            }
        }.take(7)
        if (missing.isEmpty()) {
            done(initial)
            return
        }
        val recovered = initial.toMutableList()
        fun retryAt(index: Int) {
            if (index >= missing.size) {
                done(recovered)
                return
            }
            val title = missing[index]
            // Skip the avatar on the left; its pictogram can drown out a
            // short, low-contrast nickname such as a Chinese char + vv.
            val cropX = (width * 0.15).roundToInt()
            val cropY = (title.centerY - 190).roundToInt().coerceIn(0, height - 1)
            val cropRight = (width * 0.46).roundToInt().coerceAtMost(width)
            val cropBottom = (title.centerY - 55).roundToInt().coerceIn(cropY + 1, height)
            val cropWidth = cropRight - cropX
            val cropHeight = cropBottom - cropY
            if (cropWidth < 20 || cropHeight < 20) {
                retryAt(index + 1)
                return
            }
            var scaled: Bitmap? = null
            try {
                val crop = Bitmap.createBitmap(bitmap, cropX, cropY, cropWidth, cropHeight)
                scaled = Bitmap.createScaledBitmap(
                    crop, cropWidth * 3, cropHeight * 3, true,
                )
                if (crop !== scaled) crop.recycle()
                val zoom = scaled ?: throw IllegalStateException("Empty buyer crop")
                fun accept(detected: Text): Boolean {
                    val candidates = extractLines(
                        detected, horizontalOffset = cropX.toDouble(),
                        verticalOffset = cropY.toDouble(), scale = 3.0,
                    ).filter { line ->
                        line.left < width * 0.42 &&
                            line.centerY > title.centerY - 200 &&
                            line.centerY < title.centerY - 55 &&
                            possibleMiHuashiBuyer(line.text)
                    }
                    val best = candidates.minByOrNull {
                        abs(it.centerY - (title.centerY - 112))
                    } ?: return false
                    if (recovered.none { line ->
                        abs(line.centerY - best.centerY) < 26 &&
                            line.left < width * 0.42
                    }) recovered.add(best)
                    return true
                }
                // First retry is unchanged ML Kit, on enlarged pixels. Only
                // a STILL-MISSING buyer gets a contrast-enhanced second pass.
                // No guesses or nearby customer names are copied across cards.
                fun retryEnhanced() {
                    var enhanced: Bitmap? = null
                    try {
                        val contrasted = Bitmap.createBitmap(
                            zoom.width, zoom.height, Bitmap.Config.ARGB_8888,
                        )
                        enhanced = contrasted
                        val matrix = ColorMatrix(floatArrayOf(
                            1.8f, 0f, 0f, 0f, -110f,
                            0f, 1.8f, 0f, 0f, -110f,
                            0f, 0f, 1.8f, 0f, -110f,
                            0f, 0f, 0f, 1f, 0f,
                        ))
                        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                            colorFilter = ColorMatrixColorFilter(matrix)
                        }
                        Canvas(contrasted).drawBitmap(zoom, 0f, 0f, paint)
                        recognizer.process(InputImage.fromBitmap(contrasted, 0))
                            .addOnSuccessListener { accept(it); retryAt(index + 1) }
                            .addOnFailureListener { retryAt(index + 1) }
                            .addOnCompleteListener { contrasted.recycle() }
                    } catch (_: Exception) {
                        enhanced?.recycle()
                        retryAt(index + 1)
                    }
                }
                recognizer.process(InputImage.fromBitmap(zoom, 0))
                    .addOnSuccessListener { detected ->
                        if (accept(detected)) retryAt(index + 1)
                        else retryEnhanced()
                    }
                    .addOnFailureListener { retryEnhanced() }
                    .addOnCompleteListener { zoom.recycle() }
            } catch (_: Exception) {
                scaled?.recycle()
                retryAt(index + 1)
            }
        }
        retryAt(0)
    }

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
                if (bitmap.width >= 300 && bitmap.height <= 4200 &&
                    looksLikeMiHuashiDetail(originalLines, bitmap.height)) {
                    retryMiHuashiHeader(
                        bitmap, recognizer, originalLines,
                    ) { updatedLines -> finish(updatedLines) }
                    return@addOnSuccessListener
                }
                if (bitmap.width >= 300 && bitmap.height <= 4200 &&
                    looksLikeMiHuashiList(originalLines)) {
                    retryMissingMiHuashiBuyers(
                        bitmap, recognizer, originalLines,
                    ) { recovered -> finish(recovered) }
                    return@addOnSuccessListener
                }
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
                                retry, horizontalOffset = cropX.toDouble(),
                                scale = trueScale,
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
