package com.workspace.client.k7m4

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Launches the fixed public feedback form in the user's external browser. */
class FeedbackLinkBridge(private val activity: FlutterActivity) {
    fun configure(messenger: BinaryMessenger) {
        MethodChannel(messenger, "app.feedback").setMethodCallHandler { call, result ->
            if (call.method != "openUrl") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val raw = call.argument<String>("url").orEmpty()
            val uri = Uri.parse(raw)
            if (uri.scheme != "https" || uri.host != "v.wjx.cn") {
                result.error("INVALID_FEEDBACK_URL", "Invalid feedback URL.", null)
                return@setMethodCallHandler
            }
            try {
                activity.startActivity(Intent(Intent.ACTION_VIEW, uri))
                result.success(null)
            } catch (error: ActivityNotFoundException) {
                result.error("NO_BROWSER", "No browser is installed.", null)
            } catch (error: Exception) {
                result.error("OPEN_FEEDBACK_FAILED", error.message, null)
            }
        }
    }
}
