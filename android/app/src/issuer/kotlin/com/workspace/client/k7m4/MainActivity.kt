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
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

class MainActivity : FlutterActivity() {
    companion object {
        private const val RELEASES_API_URL =
            "https://api.github.com/repos/xuebing0229/release-files/releases?per_page=50"
        private const val USER_AGENT = "adventurers-guild-license-issuer"
    }

    private lateinit var issuerSecretBridge: IssuerSecretBridge
    private lateinit var licenseDirectHttpsBridge: LicenseDirectHttpsBridge
    private var pendingUpdateApk: File? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        licenseDirectHttpsBridge = LicenseDirectHttpsBridge(this).also {
            it.configure(flutterEngine.dartExecutor.binaryMessenger)
        }

        issuerSecretBridge = IssuerSecretBridge(this).also {
            it.configure(flutterEngine.dartExecutor.binaryMessenger)
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "app.issuer_update",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "fetchIssuerReleases" -> handleFetchIssuerReleases(result)
                "installDownloadedUpdate" -> handleInstallDownloadedUpdate(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun handleFetchIssuerReleases(
        result: MethodChannel.Result,
    ) {
        Thread {
            try {
                val connection =
                    (URL(RELEASES_API_URL).openConnection() as HttpURLConnection).apply {
                        requestMethod = "GET"
                        instanceFollowRedirects = true
                        connectTimeout = 12000
                        readTimeout = 12000
                        useCaches = false
                        setRequestProperty("User-Agent", USER_AGENT)
                        setRequestProperty("Accept", "application/vnd.github+json")
                        setRequestProperty("Cache-Control", "no-cache")
                        setRequestProperty("X-GitHub-Api-Version", "2022-11-28")
                    }

                val body = try {
                    val status = connection.responseCode
                    if (status !in 200..299) {
                        val errorBody =
                            connection.errorStream
                                ?.bufferedReader()
                                ?.use { it.readText() }
                                .orEmpty()
                        throw IllegalStateException(
                            "GitHub update endpoint returned HTTP $status" +
                                if (errorBody.isBlank()) "" else ": $errorBody",
                        )
                    }
                    connection.inputStream
                        .bufferedReader()
                        .use { it.readText() }
                } finally {
                    connection.disconnect()
                }

                runOnUiThread {
                    result.success(body)
                }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error(
                        "ISSUER_UPDATE_CHECK_FAILED",
                        error.message ?: "Unable to reach GitHub update service.",
                        null,
                    )
                }
            }
        }.start()
    }

    private fun handleInstallDownloadedUpdate(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val rawPath = call.argument<String>("path").orEmpty()
        val apk = runCatching { File(rawPath).canonicalFile }.getOrNull()
        val filesRoot = runCatching { filesDir.canonicalFile }.getOrNull()
        val allowedPrefix = filesRoot?.path?.let {
            if (it.endsWith(File.separator)) it else it + File.separator
        }

        if (
            apk == null ||
            allowedPrefix == null ||
            !apk.path.startsWith(allowedPrefix) ||
            !apk.name.lowercase().endsWith(".apk") ||
            !apk.isFile
        ) {
            result.error("INVALID_UPDATE_FILE", "发码器更新包路径无效。", null)
            return
        }

        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            pendingUpdateApk = apk
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName"),
                ).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
            )
            result.success("permission_required")
            return
        }

        try {
            pendingUpdateApk = null
            openInstaller(apk)
            result.success("installing")
        } catch (error: Exception) {
            result.error(
                "INSTALL_LAUNCH_FAILED",
                error.message ?: "无法打开系统安装页面。",
                null,
            )
        }
    }

    private fun openInstaller(apk: File) {
        val uri = FileProvider.getUriForFile(
            this,
            "${applicationContext.packageName}.issuer_update_files",
            apk,
        )
        startActivity(
            Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            },
        )
    }

    override fun onResume() {
        super.onResume()

        val apk = pendingUpdateApk ?: return
        if (!apk.isFile) {
            pendingUpdateApk = null
            return
        }
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            return
        }

        pendingUpdateApk = null
        runCatching { openInstaller(apk) }
            .onFailure { pendingUpdateApk = apk }
    }

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ) {
        if (
            ::issuerSecretBridge.isInitialized &&
            issuerSecretBridge.onActivityResult(requestCode, resultCode, data)
        ) {
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }
}
