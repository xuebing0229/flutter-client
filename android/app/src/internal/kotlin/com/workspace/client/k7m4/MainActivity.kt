package com.workspace.client.k7m4

import android.content.ClipData
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
        private const val MANIFEST_URL =
            "https://license.apixb.top/releases/internal/android-latest.json"
        private const val USER_AGENT = "adventurers-guild-internal-updater"
    }

    private lateinit var backupFileBridge: BackupFileBridge
    private lateinit var feedbackLinkBridge: FeedbackLinkBridge
    private lateinit var orderReminderBridge: OrderReminderBridge
    private lateinit var syncthingBridge: SyncthingBridge
    private lateinit var screenshotOcrBridge: ScreenshotOcrBridge
    private lateinit var licenseDirectHttpsBridge: LicenseDirectHttpsBridge
    private var pendingInstallApk: File? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        licenseDirectHttpsBridge = LicenseDirectHttpsBridge(this).also {
            it.configure(flutterEngine.dartExecutor.binaryMessenger)
        }
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
                "setUpdateDownloadActive" -> handleSetUpdateDownloadActive(call, result)
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
                val manifest = fetchInternalManifest()
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

    private fun fetchInternalManifest(): Map<String, Any?> {
        val json = fetchJson(MANIFEST_URL)

        val schema = json.optInt("schema", -1)
        val published = json.optBoolean("published", false)
        val channel = json.optString("channel", "")
        val version = json.optString("version", "")
        val build = json.optInt("build", -1)
        val downloadUrl = json.optString("download_url", "")
        val sizeBytes = json.optLong("size_bytes", -1L)
        val sha256 = json.optString("sha256", "")

        if (
            schema != 1 ||
            !published ||
            channel != "internal" ||
            version.isBlank() ||
            build < 0 ||
            downloadUrl.isBlank()
        ) {
            throw IllegalStateException("Internal update manifest is invalid.")
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

    private fun fetchJson(url: String): JSONObject {
        val connection =
            (URL(url).openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                instanceFollowRedirects = true
                connectTimeout = 12000
                readTimeout = 12000
                useCaches = false
                setRequestProperty("User-Agent", USER_AGENT)
                setRequestProperty("Accept", "application/json")
                setRequestProperty("Cache-Control", "no-cache")
            }

        try {
            val status = connection.responseCode
            if (status !in 200..299) {
                throw IllegalStateException(
                    "Update endpoint returned HTTP $status",
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

    private fun handleSetUpdateDownloadActive(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val active = call.argument<Boolean>("active") == true
        if (active) {
            UpdateDownloadKeepAliveService.start(this)
        } else {
            UpdateDownloadKeepAliveService.stop(this)
        }
        result.success(null)
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
            pendingInstallApk = apk
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
            pendingInstallApk = null
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

        fun grantToResolvedHandlers(intent: Intent) {
            intent.clipData = ClipData.newRawUri("app-update", uri)
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)

            packageManager.queryIntentActivities(
                intent,
                android.content.pm.PackageManager.MATCH_DEFAULT_ONLY,
            ).forEach { handler ->
                grantUriPermission(
                    handler.activityInfo.packageName,
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            }
        }

        val installIntent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
            data = uri
        }
        grantToResolvedHandlers(installIntent)
        if (installIntent.resolveActivity(packageManager) != null) {
            startActivity(installIntent)
            return
        }

        val viewIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
        }
        grantToResolvedHandlers(viewIntent)
        startActivity(viewIntent)
    }

    override fun onResume() {
        super.onResume()

        val apk = pendingInstallApk ?: return
        if (!apk.isFile) {
            pendingInstallApk = null
            return
        }
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            return
        }

        pendingInstallApk = null
        runCatching {
            openInstaller(apk)
        }.onFailure {
            pendingInstallApk = apk
        }
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
