package com.workspace.client.k7m4

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.provider.OpenableColumns
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
        private const val REQUEST_REFERENCE_IMAGES = 7104
        private const val REQUEST_LOCAL_FILE_EXPORT = 7105
        private const val REQUEST_BACKUP_FILE = 7106
    }

    private var pendingExport: MethodChannel.Result? = null
    private var pendingImport: MethodChannel.Result? = null
    private var pendingQrImage: MethodChannel.Result? = null
    private var pendingReferenceImages: MethodChannel.Result? = null
    private var pendingLocalFileExport: MethodChannel.Result? = null
    private var pendingBackupFile: MethodChannel.Result? = null
    private var pendingExportContent: String? = null
    private var pendingLocalFilePath: String? = null

    fun configure(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "exportBackup" -> handleExport(call, result)
                "importBackup" -> handleImport(result)
                "pickBackupFile" -> handleBackupFile(result)
                "pickQrImage" -> handleQrImage(result)
                "pickReferenceImages" -> handleReferenceImages(result)
                "exportLocalFile" -> handleLocalFileExport(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun isFileDialogBusy(): Boolean =
        pendingExport != null ||
            pendingImport != null ||
            pendingQrImage != null ||
            pendingReferenceImages != null ||
            pendingLocalFileExport != null ||
            pendingBackupFile != null

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

    private fun handleBackupFile(result: MethodChannel.Result) {
        if (isFileDialogBusy()) {
            result.error(
                "FILE_DIALOG_BUSY",
                "A file dialog is already open.",
                null,
            )
            return
        }

        pendingBackupFile = result

        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(
                Intent.EXTRA_MIME_TYPES,
                arrayOf(
                    "application/zip",
                    "application/json",
                    "application/octet-stream",
                ),
            )
        }
        activity.startActivityForResult(intent, REQUEST_BACKUP_FILE)
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

    private fun handleReferenceImages(result: MethodChannel.Result) {
        if (isFileDialogBusy()) {
            result.error(
                "FILE_DIALOG_BUSY",
                "A file dialog is already open.",
                null,
            )
            return
        }

        pendingReferenceImages = result

        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "image/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        }
        activity.startActivityForResult(intent, REQUEST_REFERENCE_IMAGES)
    }

    private fun handleLocalFileExport(
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

        val sourcePath = call.argument<String>("sourcePath")
            ?.trim()
            .orEmpty()
        val source = File(sourcePath)
        if (sourcePath.isBlank() || !source.isFile) {
            result.error(
                "SOURCE_FILE_MISSING",
                "The source file is not available.",
                null,
            )
            return
        }

        val fileName = call.argument<String>("fileName")
            ?.trim()
            .orEmpty()
            .ifBlank { source.name }
        val mimeType = call.argument<String>("mimeType")
            ?.trim()
            .orEmpty()
            .ifBlank { "application/octet-stream" }

        pendingLocalFileExport = result
        pendingLocalFilePath = source.absolutePath

        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mimeType
            putExtra(Intent.EXTRA_TITLE, fileName)
        }
        activity.startActivityForResult(intent, REQUEST_LOCAL_FILE_EXPORT)
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
            REQUEST_BACKUP_FILE -> {
                finishBackupFile(resultCode, data?.data)
                true
            }
            REQUEST_QR_IMAGE -> {
                finishQrImage(resultCode, data?.data)
                true
            }
            REQUEST_REFERENCE_IMAGES -> {
                finishReferenceImages(resultCode, data)
                true
            }
            REQUEST_LOCAL_FILE_EXPORT -> {
                finishLocalFileExport(resultCode, data?.data)
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

    private fun finishBackupFile(resultCode: Int, uri: Uri?) {
        val result = pendingBackupFile ?: return
        pendingBackupFile = null

        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }

        Thread {
            try {
                val displayName = queryDisplayName(uri)
                val extension = safeExtension(displayName)
                val cacheDir = File(activity.cacheDir, "backup-import").apply {
                    mkdirs()
                }
                runCatching {
                    cacheDir.listFiles()?.forEach { stale ->
                        if (stale.isFile) stale.delete()
                    }
                }
                val file = File(
                    cacheDir,
                    "backup-${UUID.randomUUID()}${extension ?: ".bin"}",
                )

                val input = activity.contentResolver.openInputStream(uri)
                    ?: throw IllegalStateException("Unable to open backup file.")
                input.use { source ->
                    file.outputStream().use { destination ->
                        source.copyTo(destination)
                    }
                }

                activity.runOnUiThread {
                    result.success(
                        linkedMapOf(
                            "path" to file.absolutePath,
                            "name" to displayName,
                        ),
                    )
                }
            } catch (error: Exception) {
                activity.runOnUiThread {
                    result.error(
                        "BACKUP_FILE_IMPORT_FAILED",
                        error.message ?: "Backup file import failed.",
                        null,
                    )
                }
            }
        }.start()
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

    private fun finishReferenceImages(
        resultCode: Int,
        data: Intent?,
    ) {
        val result = pendingReferenceImages ?: return
        pendingReferenceImages = null

        if (resultCode != Activity.RESULT_OK || data == null) {
            result.success(emptyList<Map<String, String>>())
            return
        }

        val uris = mutableListOf<Uri>()
        val clip = data.clipData
        if (clip != null) {
            for (index in 0 until clip.itemCount) {
                clip.getItemAt(index).uri?.let(uris::add)
            }
        } else {
            data.data?.let(uris::add)
        }

        if (uris.isEmpty()) {
            result.success(emptyList<Map<String, String>>())
            return
        }

        Thread {
            val createdFiles = mutableListOf<File>()
            try {
                val cacheDir = File(activity.cacheDir, "reference-import").apply {
                    mkdirs()
                }
                runCatching {
                    cacheDir.listFiles()?.forEach { stale ->
                        if (stale.isFile) stale.delete()
                    }
                }

                val payload = mutableListOf<Map<String, String>>()
                for (uri in uris) {
                    val displayName = queryDisplayName(uri)
                    val extension = safeExtension(displayName)
                    val file = File(
                        cacheDir,
                        "ref-${UUID.randomUUID()}${extension ?: ".img"}",
                    )

                    val input = activity.contentResolver.openInputStream(uri)
                        ?: throw IllegalStateException(
                            "Unable to open selected image.",
                        )
                    input.use { source ->
                        file.outputStream().use { destination ->
                            source.copyTo(destination)
                        }
                    }
                    createdFiles.add(file)
                    payload.add(
                        linkedMapOf(
                            "path" to file.absolutePath,
                            "name" to displayName,
                        ),
                    )
                }

                activity.runOnUiThread {
                    result.success(payload)
                }
            } catch (error: Exception) {
                createdFiles.forEach { runCatching { it.delete() } }
                activity.runOnUiThread {
                    result.error(
                        "REFERENCE_IMAGE_IMPORT_FAILED",
                        error.message ?: "Reference image import failed.",
                        null,
                    )
                }
            }
        }.start()
    }

    private fun finishLocalFileExport(
        resultCode: Int,
        uri: Uri?,
    ) {
        val result = pendingLocalFileExport ?: return
        pendingLocalFileExport = null

        val sourcePath = pendingLocalFilePath
        pendingLocalFilePath = null

        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(false)
            return
        }

        if (sourcePath.isNullOrBlank()) {
            result.error(
                "SOURCE_FILE_MISSING",
                "The source file was lost before saving.",
                null,
            )
            return
        }

        Thread {
            try {
                val source = File(sourcePath)
                if (!source.isFile) {
                    throw IllegalStateException(
                        "The source file is no longer available.",
                    )
                }
                val output = activity.contentResolver.openOutputStream(uri, "w")
                    ?: throw IllegalStateException(
                        "Unable to open file destination.",
                    )
                source.inputStream().use { input ->
                    output.use { destination ->
                        input.copyTo(destination)
                    }
                }
                activity.runOnUiThread {
                    result.success(true)
                }
            } catch (error: Exception) {
                activity.runOnUiThread {
                    result.error(
                        "LOCAL_FILE_EXPORT_FAILED",
                        error.message ?: "File export failed.",
                        null,
                    )
                }
            }
        }.start()
    }

    private fun queryDisplayName(uri: Uri): String {
        runCatching {
            activity.contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (index >= 0) {
                        val name = cursor.getString(index)?.trim().orEmpty()
                        if (name.isNotBlank()) return name
                    }
                }
            }
        }

        return uri.lastPathSegment
            ?.substringAfterLast('/')
            ?.trim()
            .orEmpty()
            .ifBlank { "reference-image" }
    }

    private fun safeExtension(fileName: String): String? {
        val dot = fileName.lastIndexOf('.')
        if (dot < 0 || dot == fileName.length - 1) return null
        val extension = fileName.substring(dot + 1).lowercase()
        if (extension.length !in 1..8) return null
        if (!extension.matches(Regex("[a-z0-9]+"))) return null
        return ".$extension"
    }
}
