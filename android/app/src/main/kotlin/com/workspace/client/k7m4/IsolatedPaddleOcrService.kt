package com.workspace.client.k7m4

import android.app.Service
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import android.os.RemoteException
import android.util.Log
import com.paddle.ocr.EngineConfig
import com.paddle.ocr.PaddleOCR
import com.paddle.ocr.PaddleOCRConfig
import com.paddle.ocr.util.OpenCVUtils
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

/**
 * Runs ALL Paddle/OpenCV/ONNX calls in the :paddle_ocr process, not the app UI
 * process. A native SIGSEGV, SIGABRT or memory kill here must not close the app.
 * No screenshot or OCR output is uploaded: the Messenger is app-private.
 */
class IsolatedPaddleOcrService : Service() {
    companion object {
        const val RECOGNIZE = 1
        const val SUCCESS = 2
        const val FAILURE = 3
        private const val TAG = "AG_IsolatedPaddle"
        private const val MODEL_ROOT = "flutter_assets/packages/paddle_ocr_native/assets/models/"
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var engine: PaddleOCR? = null
    private val incoming = Messenger(Handler(Looper.getMainLooper()) { message ->
        if (message.what != RECOGNIZE) return@Handler false
        val requestId = message.data.getInt("request_id")
        val path = message.data.getString("path")
        val receiver = message.replyTo
        scope.launch {
            val answer = try {
                val source = path?.let { BitmapFactory.decodeFile(it) }
                    ?: throw IllegalArgumentException("Image could not be decoded")
                val bitmap = if (source.config == Bitmap.Config.ARGB_8888) {
                    source
                } else {
                    source.copy(Bitmap.Config.ARGB_8888, false).also { source.recycle() }
                }
                val run = try {
                    getEngine().recognize(bitmap)
                } finally {
                    bitmap.recycle()
                }
                val boxes = JSONArray()
                for (item in run.results) {
                    val points = JSONArray()
                    for (point in item.box.points) {
                        points.put(JSONObject().put("x", point.x).put("y", point.y))
                    }
                    boxes.put(JSONObject()
                        .put("text", item.text)
                        .put("confidence", item.confidence)
                        .put("points", points))
                }
                Message.obtain(null, SUCCESS).apply {
                    data = Bundle().apply {
                        putInt("request_id", requestId)
                        putString("results", boxes.toString())
                        putInt("detection_ms", run.detectionTimeMs.toInt())
                        putInt("recognition_ms", run.recognitionTimeMs.toInt())
                    }
                }
            } catch (error: Throwable) {
                Log.e(TAG, "Paddle OCR failed (isolated)", error)
                Message.obtain(null, FAILURE).apply {
                    data = Bundle().apply {
                        putInt("request_id", requestId)
                        putString("error", error.message ?: error.javaClass.simpleName)
                    }
                }
            }
            try {
                receiver?.send(answer)
            } catch (_: RemoteException) {
                // App UI may have closed. The service must never hold a stale reply.
            }
        }
        true
    })

    override fun onBind(intent: Intent?): IBinder = incoming.binder

    private suspend fun getEngine(): PaddleOCR {
        engine?.let { return it }
        if (!OpenCVUtils.init(applicationContext)) {
            throw IllegalStateException("OpenCV native initialization failed")
        }
        val created = PaddleOCR.create(
            context = applicationContext,
            config = PaddleOCRConfig(),
            engineConfig = EngineConfig(numThreads = 1),
            detModelAssetPath = MODEL_ROOT + "det/inference.onnx",
            recModelAssetPath = MODEL_ROOT + "rec/inference.onnx",
            recConfigAssetPath = MODEL_ROOT + "rec/inference.yml",
        )
        engine = created
        return created
    }

    override fun onDestroy() {
        scope.launch {
            try { engine?.release() } catch (_: Throwable) { }
            engine = null
            scope.cancel()
        }
        super.onDestroy()
    }
}
