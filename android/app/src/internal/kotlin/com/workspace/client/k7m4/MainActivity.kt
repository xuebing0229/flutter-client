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
import java.io.File

class MainActivity : FlutterActivity() {
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
