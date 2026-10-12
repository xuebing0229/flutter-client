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

class MainActivity : FlutterActivity() {
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
                "installDownloadedUpdate" -> handleInstallDownloadedUpdate(call, result)
                else -> result.notImplemented()
            }
        }
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
