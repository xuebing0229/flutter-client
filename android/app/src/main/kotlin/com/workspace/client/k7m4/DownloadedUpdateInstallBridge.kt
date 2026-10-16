package com.workspace.client.k7m4

import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class DownloadedUpdateInstallBridge(
    private val activity: FlutterActivity,
    private val channelName: String = "app.beta_update",
) {
    private var pendingInstallApk: File? = null

    fun configure(binaryMessenger: BinaryMessenger) {
        MethodChannel(binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "installDownloadedUpdate" -> handleInstallDownloadedUpdate(call, result)
                else -> result.notImplemented()
            }
        }
    }

    fun onResume() {
        val apk = pendingInstallApk ?: return
        if (!apk.isFile) {
            pendingInstallApk = null
            return
        }
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !activity.packageManager.canRequestPackageInstalls()
        ) {
            return
        }

        pendingInstallApk = null
        runCatching { openInstaller(apk) }.onFailure {
            pendingInstallApk = apk
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
        val allowedRoot = runCatching { activity.filesDir.canonicalFile }.getOrNull()
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
            !activity.packageManager.canRequestPackageInstalls()
        ) {
            pendingInstallApk = apk
            val intent = Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:${activity.packageName}"),
            ).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            activity.startActivity(intent)
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
            activity,
            "${activity.applicationContext.packageName}.update_files",
            apk,
        )

        fun grantToResolvedHandlers(intent: Intent) {
            intent.clipData = ClipData.newRawUri("app-update", uri)
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)

            activity.packageManager.queryIntentActivities(
                intent,
                android.content.pm.PackageManager.MATCH_DEFAULT_ONLY,
            ).forEach { handler ->
                activity.grantUriPermission(
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
        if (installIntent.resolveActivity(activity.packageManager) != null) {
            activity.startActivity(installIntent)
            return
        }

        val viewIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
        }
        grantToResolvedHandlers(viewIntent)
        activity.startActivity(viewIntent)
    }
}
