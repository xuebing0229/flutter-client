package com.workspace.client.k7m4

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

class MainActivity : FlutterActivity() {
    companion object {
        private const val STATIC_MANIFEST_URL =
            "https://github.com/xuebing0229/release-files/releases/latest/download/app-beta-latest.json"
        private const val RELEASE_API_URL =
            "https://api.github.com/repos/xuebing0229/release-files/releases/latest"
        private const val USER_AGENT = "artist-queue-beta-updater"
    }

    private lateinit var backupFileBridge: BackupFileBridge
    private lateinit var feedbackLinkBridge: FeedbackLinkBridge
    private lateinit var orderReminderBridge: OrderReminderBridge
    private lateinit var syncthingBridge: SyncthingBridge
    private lateinit var screenshotOcrBridge: ScreenshotOcrBridge

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        backupFileBridge = BackupFileBridge(this).also {
            it.configure(flutterEngine.dartExecutor.binaryMessenger)
        }
        feedbackLinkBridge = FeedbackLinkBridge(this).also {
            it.configure(flutterEngine.dartExecutor.binaryMessenger)
        }
        orderReminderBridge = OrderReminderBridge(this).also {
            it.configure(flutterEngine.dartExecutor.binaryMessenger)
        }
        syncthingBridge = SyncthingBridge(this).also {
            it.configure(flutterEngine.dartExecutor.binaryMessenger)
        }
        screenshotOcrBridge = ScreenshotOcrBridge(this).also {
            it.configure(flutterEngine.dartExecutor.binaryMessenger)
        }


        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "app.beta_update",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "fetchLatestManifest" -> handleFetchLatestManifest(result)
                "installDownloadedUpdate" -> handleInstallDownloadedUpdate(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun handleFetchLatestManifest(
        result: MethodChannel.Result,
    ) {
        Thread {
            try {
                val manifest =
                    fetchStaticManifest() ?: fetchReleaseApiManifest()

                runOnUiThread {
                    result.success(manifest)
                }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error(
                        "UPDATE_CHECK_FAILED",
                        error.message ?: "Native update check failed.",
                        null,
                    )
                }
            }
        }.start()
    }

    private fun fetchStaticManifest(): Map<String, Any?>? {
        val json = runCatching {
            fetchJson(
                STATIC_MANIFEST_URL,
                "application/json",
            )
        }.getOrNull() ?: return null

        val schema = json.optInt("schema", -1)
        val published = json.optBoolean("published", false)
        val channel = json.optString("channel", "")
        val version = json.optString("version", "")
        val build = json.optInt("build", -1)
        val downloadUrl = json.optString("download_url", "")
        val sizeBytes = json.optLong("android_size_bytes", -1L)
        val sha256 = json.optString("android_sha256", "")

        if (
            schema != 1 ||
            !published ||
            channel != "beta" ||
            version.isBlank() ||
            build < 0 ||
            downloadUrl.isBlank()
        ) {
            return null
        }

        return linkedMapOf(
            "schema" to schema,
            "channel" to channel,
            "version" to version,
            "build" to build,
            "published" to published,
            "download_url" to downloadUrl,
            "size_bytes" to sizeBytes.takeIf { it > 0L },
            "sha256" to sha256.takeIf { it.isNotBlank() },
            "notes" to json.optString("notes", ""),
        )
    }

    private fun fetchReleaseApiManifest(): Map<String, Any?> {
        val json = fetchJson(
            RELEASE_API_URL,
            "application/vnd.github+json",
        )

        if (json.optBoolean("draft", false)) {
            throw IllegalStateException("Latest Beta release is still a draft.")
        }

        val tag = json.optString("tag_name", "")
        val tagMatch = Regex(
            """beta-v([^+]+)\+(\d+)""",
            RegexOption.IGNORE_CASE,
        ).find(tag)
            ?: throw IllegalStateException("Latest Beta release tag is invalid.")

        val version = tagMatch.groupValues[1]
        val build = tagMatch.groupValues[2].toIntOrNull()
            ?: throw IllegalStateException("Latest Beta release build is invalid.")

        var downloadUrl = ""
        var sizeBytes = -1L
        var sha256 = ""
        val assets = json.optJSONArray("assets")
        if (assets != null) {
            for (index in 0 until assets.length()) {
                val asset = assets.optJSONObject(index) ?: continue
                if (asset.optString("name") == "app-beta.apk") {
                    downloadUrl =
                        asset.optString("browser_download_url", "")
                    sizeBytes = asset.optLong("size", -1L)
                    val digest = asset.optString("digest", "")
                    if (digest.startsWith("sha256:", ignoreCase = true)) {
                        sha256 = digest.substringAfter(":")
                    }
                    break
                }
            }
        }

        if (downloadUrl.isBlank()) {
            throw IllegalStateException(
                "Latest Beta release has no app-beta.apk asset.",
            )
        }

        return linkedMapOf(
            "schema" to 1,
            "channel" to "beta",
            "version" to version,
            "build" to build,
            "published" to true,
            "download_url" to downloadUrl,
            "size_bytes" to sizeBytes.takeIf { it > 0L },
            "sha256" to sha256.takeIf { it.isNotBlank() },
            "notes" to json.optString("body", ""),
        )
    }

    private fun fetchJson(
        url: String,
        accept: String,
    ): JSONObject {
        val connection =
            (URL(url).openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                instanceFollowRedirects = true
                connectTimeout = 12000
                readTimeout = 12000
                useCaches = false
                setRequestProperty("User-Agent", USER_AGENT)
                setRequestProperty("Accept", accept)
                setRequestProperty("Cache-Control", "no-cache")
                if (url.contains("api.github.com")) {
                    setRequestProperty(
                        "X-GitHub-Api-Version",
                        "2022-11-28",
                    )
                }
            }

        try {
            val status = connection.responseCode
            if (status !in 200..299) {
                val errorBody =
                    connection.errorStream
                        ?.bufferedReader()
                        ?.use { it.readText() }
                        .orEmpty()

                throw IllegalStateException(
                    "Update endpoint returned HTTP $status" +
                        if (errorBody.isBlank()) "" else ": $errorBody",
                )
            }

            val body =
                connection.inputStream
                    .bufferedReader()
                    .use { it.readText() }

            return JSONObject(body)
        } finally {
            connection.disconnect()
        }
    }

    private fun handleInstallDownloadedUpdate(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val rawPath = call.argument<String>("path").orEmpty()
        if (rawPath.isBlank()) {
            result.error(
                "INVALID_UPDATE_FILE",
                "Downloaded update path is missing.",
                null,
            )
            return
        }

        val apk = runCatching { File(rawPath).canonicalFile }.getOrNull()
        val allowedRoot = runCatching { filesDir.canonicalFile }.getOrNull()
        val allowedPrefix = allowedRoot?.path?.let {
            if (it.endsWith(File.separator)) it else it + File.separator
        }

        if (
            apk == null ||
            allowedPrefix == null ||
            !apk.path.startsWith(allowedPrefix) ||
            !apk.name.lowercase().endsWith(".apk") ||
            !apk.isFile
        ) {
            result.error(
                "INVALID_UPDATE_FILE",
                "Downloaded update file is invalid or outside app storage.",
                null,
            )
            return
        }

        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            val intent = Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName"),
            ).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            result.success("permission_required")
            return
        }

        try {
            openInstaller(apk)
            result.success("installing")
        } catch (error: Exception) {
            result.error(
                "INSTALL_LAUNCH_FAILED",
                error.message ?: "Could not open the Android package installer.",
                null,
            )
        }
    }

    private fun openInstaller(apk: File) {
        val uri = FileProvider.getUriForFile(
            this,
            "${applicationContext.packageName}.update_files",
            apk,
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (
            ::orderReminderBridge.isInitialized &&
            orderReminderBridge.onRequestPermissionsResult(
                requestCode,
                grantResults,
            )
        ) {
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ) {
        if (
            ::backupFileBridge.isInitialized &&
            backupFileBridge.onActivityResult(requestCode, resultCode, data)
        ) {
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        if (::screenshotOcrBridge.isInitialized) screenshotOcrBridge.close()
        super.onDestroy()
    }
}
