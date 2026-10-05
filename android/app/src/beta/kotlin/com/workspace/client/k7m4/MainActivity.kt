package com.workspace.client.k7m4

import android.app.DownloadManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.os.Environment
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

    private var activeDownloadId = -1L
    private var downloadReceiver: BroadcastReceiver? = null
    private var activeApk: File? = null
    private lateinit var backupFileBridge: BackupFileBridge
    private lateinit var orderReminderBridge: OrderReminderBridge
    private lateinit var syncthingBridge: SyncthingBridge

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        backupFileBridge = BackupFileBridge(this).also {
            it.configure(flutterEngine.dartExecutor.binaryMessenger)
        }
        orderReminderBridge = OrderReminderBridge(this).also {
            it.configure(flutterEngine.dartExecutor.binaryMessenger)
        }
        syncthingBridge = SyncthingBridge(this).also {
            it.configure(flutterEngine.dartExecutor.binaryMessenger)
        }

        cleanupStaleUpdatePackages()

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "app.beta_update",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "fetchLatestManifest" -> handleFetchLatestManifest(result)
                "downloadAndInstall" -> handleDownloadAndInstall(call, result)
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
        val assets = json.optJSONArray("assets")
        if (assets != null) {
            for (index in 0 until assets.length()) {
                val asset = assets.optJSONObject(index) ?: continue
                if (asset.optString("name") == "app-beta.apk") {
                    downloadUrl =
                        asset.optString("browser_download_url", "")
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

    private fun handleDownloadAndInstall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val url = call.argument<String>("url").orEmpty()
        val requestedName = call.argument<String>("fileName").orEmpty()

        val uri = runCatching { Uri.parse(url) }.getOrNull()
        if (
            uri == null ||
            uri.scheme != "https" ||
            uri.host?.lowercase() != "github.com"
        ) {
            result.error(
                "INVALID_URL",
                "Beta updates may only be downloaded from GitHub Releases.",
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

        val safeName = requestedName
            .ifBlank { "app-beta-update.apk" }
            .replace(Regex("[^A-Za-z0-9._-]"), "_")
            .let { if (it.lowercase().endsWith(".apk")) it else "$it.apk" }

        val baseDir = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
        if (baseDir == null) {
            result.error(
                "DOWNLOAD_DIR_UNAVAILABLE",
                "Android download directory is unavailable.",
                null,
            )
            return
        }

        val updateDir = File(baseDir, "updates")
        if (!updateDir.exists() && !updateDir.mkdirs()) {
            result.error(
                "DOWNLOAD_DIR_FAILED",
                "Unable to create the update directory.",
                null,
            )
            return
        }

        cleanupUpdateDirectory(updateDir)

        val apk = File(updateDir, safeName)
        if (apk.exists()) {
            apk.delete()
        }
        activeApk = apk

        val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        unregisterDownloadReceiver()

        downloadReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val completedId =
                    intent?.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1L) ?: -1L
                if (completedId != activeDownloadId) return

                try {
                    val query = DownloadManager.Query().setFilterById(completedId)
                    manager.query(query).use { cursor ->
                        if (!cursor.moveToFirst()) return@use

                        val status = cursor.getInt(
                            cursor.getColumnIndexOrThrow(
                                DownloadManager.COLUMN_STATUS,
                            ),
                        )

                        if (status == DownloadManager.STATUS_SUCCESSFUL) {
                            activeApk?.let(::openInstaller)
                        }
                    }
                } finally {
                    unregisterDownloadReceiver()
                }
            }
        }

        val filter = IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(
                downloadReceiver,
                filter,
                Context.RECEIVER_NOT_EXPORTED,
            )
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(downloadReceiver, filter)
        }

        try {
            val request = DownloadManager.Request(uri).apply {
                setTitle("测试版更新")
                setDescription("正在下载 $safeName")
                setMimeType("application/vnd.android.package-archive")
                setNotificationVisibility(
                    DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED,
                )
                setDestinationUri(Uri.fromFile(apk))
                setAllowedOverMetered(true)
                setAllowedOverRoaming(false)
            }

            activeDownloadId = manager.enqueue(request)
            result.success("downloading")
        } catch (error: Exception) {
            unregisterDownloadReceiver()
            result.error("DOWNLOAD_FAILED", error.message, null)
        }
    }

    private fun cleanupStaleUpdatePackages() {
        val baseDir = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
            ?: return
        val updateDir = File(baseDir, "updates")
        cleanupUpdateDirectory(updateDir)
    }

    private fun cleanupUpdateDirectory(updateDir: File) {
        if (!updateDir.exists()) return

        runCatching {
            updateDir.listFiles()?.forEach { file ->
                if (file.isFile && file.name.lowercase().endsWith(".apk")) {
                    file.delete()
                }
            }
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

    private fun unregisterDownloadReceiver() {
        val receiver = downloadReceiver ?: return
        try {
            unregisterReceiver(receiver)
        } catch (_: IllegalArgumentException) {
            // Receiver was already gone.
        }
        downloadReceiver = null
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
        unregisterDownloadReceiver()
        super.onDestroy()
    }
}
