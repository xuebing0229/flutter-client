package com.workspace.client.k7m4

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID

class BackupFileBridge(
    private val activity: FlutterActivity,
) {
    companion object {
        private const val CHANNEL = "app.data_portability"
        private const val REQUEST_EXPORT = 7101
        private const val REQUEST_IMPORT = 7102
        private const val REQUEST_QR_IMAGE = 7103
    }

    private var pendingExport: MethodChannel.Result? = null
    private var pendingImport: MethodChannel.Result? = null
    private var pendingQrImage: MethodChannel.Result? = null
    private var pendingExportContent: String? = null

    fun configure(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "exportBackup" -> handleExport(call, result)
                "importBackup" -> handleImport(result)
                "pickQrImage" -> handleQrImage(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun isFileDialogBusy(): Boolean =
        pendingExport != null ||
            pendingImport != null ||
            pendingQrImage != null

    private fun handleExport(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        if (isFileDialogBusy()) {
            result.error(
                "FILE_DIALOG_BUSY",
                "A file dialog is already open.",
                null,
            )
            return
        }

        val fileName = call.argument<String>("fileName")
            ?.trim()
            .orEmpty()
            .ifBlank { "artist-queue-backup.json" }
        val content = call.argument<String>("content")

        if (content == null) {
            result.error(
                "MISSING_CONTENT",
                "Backup content is missing.",
                null,
            )
            return
        }

        pendingExport = result
        pendingExportContent = content

        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/json"
            putExtra(Intent.EXTRA_TITLE, fileName)
        }

        activity.startActivityForResult(intent, REQUEST_EXPORT)
    }

    private fun handleImport(result: MethodChannel.Result) {
        if (isFileDialogBusy()) {
            result.error(
                "FILE_DIALOG_BUSY",
                "A file dialog is already open.",
                null,
            )
            return
        }

        pendingImport = result

        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/json"
        }

        activity.startActivityForResult(intent, REQUEST_IMPORT)
    }

    private fun handleQrImage(result: MethodChannel.Result) {
        if (isFileDialogBusy()) {
            result.error(
                "FILE_DIALOG_BUSY",
                "A file dialog is already open.",
                null,
            )
            return
        }

        pendingQrImage = result

        val intent =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                Intent(MediaStore.ACTION_PICK_IMAGES).apply {
                    type = "image/*"
                }
            } else {
                Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "image/*"
                }
            }

        activity.startActivityForResult(intent, REQUEST_QR_IMAGE)
    }

    fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ): Boolean {
        return when (requestCode) {
            REQUEST_EXPORT -> {
                finishExport(resultCode, data?.data)
                true
            }
            REQUEST_IMPORT -> {
                finishImport(resultCode, data?.data)
                true
            }
            REQUEST_QR_IMAGE -> {
                finishQrImage(resultCode, data?.data)
                true
            }
            else -> false
        }
    }

    private fun finishExport(resultCode: Int, uri: Uri?) {
        val result = pendingExport ?: return
        pendingExport = null

        val content = pendingExportContent
        pendingExportContent = null

        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(false)
            return
        }

        if (content == null) {
            result.error(
                "MISSING_CONTENT",
                "Backup content was lost before saving.",
                null,
            )
            return
        }

        try {
            val stream = activity.contentResolver.openOutputStream(uri, "wt")
                ?: throw IllegalStateException("Unable to open backup destination.")
            stream.bufferedWriter(Charsets.UTF_8).use { writer ->
                writer.write(content)
            }
            result.success(true)
        } catch (error: Exception) {
            result.error(
                "EXPORT_FAILED",
                error.message ?: "Backup export failed.",
                null,
            )
        }
    }

    private fun finishImport(resultCode: Int, uri: Uri?) {
        val result = pendingImport ?: return
        pendingImport = null

        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }

        try {
            val stream = activity.contentResolver.openInputStream(uri)
                ?: throw IllegalStateException("Unable to open backup file.")
            val content = stream.bufferedReader(Charsets.UTF_8).use {
                it.readText()
            }
            result.success(content)
        } catch (error: Exception) {
            result.error(
                "IMPORT_FAILED",
                error.message ?: "Backup import failed.",
                null,
            )
        }
    }

    private fun finishQrImage(resultCode: Int, uri: Uri?) {
        val result = pendingQrImage ?: return
        pendingQrImage = null

        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }

        try {
            val input = activity.contentResolver.openInputStream(uri)
                ?: throw IllegalStateException("Unable to open selected image.")
            val cacheDir = File(activity.cacheDir, "qr-import").apply {
                mkdirs()
            }
            val file = File(
                cacheDir,
                "qr-${UUID.randomUUID()}.img",
            )

            input.use { source ->
                file.outputStream().use { destination ->
                    source.copyTo(destination)
                }
            }

            result.success(file.absolutePath)
        } catch (error: Exception) {
            result.error(
                "QR_IMAGE_IMPORT_FAILED",
                error.message ?: "QR image import failed.",
                null,
            )
        }
    }
}
