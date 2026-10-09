package com.workspace.client.k7m4

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.paddle.ocr.EngineConfig
import com.paddle.ocr.PaddleOCR
import com.paddle.ocr.PaddleOCRConfig
import com.paddle.ocr.util.OpenCVUtils
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.ByteArrayOutputStream

/**
 * Exercises the *real official PP-OCRv6 Small SDK*, OpenCV, ONNX, model load and
 * recognition. Does not simulate OCR by passing fake parsed text.
 */
@RunWith(AndroidJUnit4::class)
class ScreenshotOfficialPaddleOcrTest {
    @Test fun realNativeChineseRecognitionTwice() = runBlocking {
        val ctx = InstrumentationRegistry.getInstrumentation().targetContext
        assertTrue("OpenCV must load", OpenCVUtils.init(ctx))
        // Two separately loaded batches exercise release and subsequent reload.
        val bmp = Bitmap.createBitmap(865, 1920, Bitmap.Config.ARGB_8888)
        val bytes = try {
            val canvas = Canvas(bmp)
            canvas.drawColor(Color.WHITE)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.BLACK
                textSize = 60f
                isFakeBoldText = true
            }
            canvas.drawText("ABC123", 130f, 280f, paint)
            canvas.drawText("黑白摸鱼头3.0", 180f, 500f, paint)
            canvas.drawText("Viu51", 150f, 1100f, paint)
            ByteArrayOutputStream().use { output ->
                bmp.compress(Bitmap.CompressFormat.PNG, 100, output)
                output.toByteArray()
            }
        } finally {
            bmp.recycle()
        }
        repeat(2) { batch ->
          val ocr = PaddleOCR.create(
            context = ctx,
            config = PaddleOCRConfig(
                detLimitSideLen = 1536,
                detLimitType = "max",
                recBatchSize = 1,
                recScoreThresh = 0f,
            ),
            engineConfig = EngineConfig(numThreads = 2),
            detModelAssetPath = "models/det/inference.onnx",
            recModelAssetPath = "models/rec/inference.onnx",
            recConfigAssetPath = "models/rec/inference.yml",
        )
        try {
            repeat(2) { run ->
                val result = ocr.recognize(bytes)
                Log.i("AG_REAL_OCR", "PP-OCRv6 Small batch=$batch run=$run " +
                    "lines=${result.lineCount} det=${result.detectionTimeMs}ms " +
                    "rec=${result.recognitionTimeMs}ms " +
                    "text=${result.results.map { it.text }}")
                assertTrue("Real PP-OCRv6 output must contain visible text", result.lineCount > 0)
            }
        } finally {
            ocr.release()
        }
        }
    }
}
