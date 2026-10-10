package com.workspace.client.k7m4

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class IssuerSecretBridge(
    private val activity: FlutterActivity,
) {
    companion object {
        private const val CHANNEL = "app.license_issuer_secret"
        private const val REQUEST_IMPORT = 7201
        private const val REQUEST_EXPORT = 7202
        private const val PREFS = "license_issuer_secure"
        private const val PREF_CIPHER = "private_key_cipher"
        private const val PREF_IV = "private_key_iv"
        private const val KEY_ALIAS = "license_issuer_private_key_wrap"
        private const val PREF_ADMIN_TOKEN_CIPHER = "admin_token_cipher"
        private const val PREF_ADMIN_TOKEN_IV = "admin_token_iv"
        private const val ADMIN_TOKEN_KEY_ALIAS = "license_issuer_admin_token_wrap"
    }

    private var pendingImport: MethodChannel.Result? = null
    private var pendingExport: MethodChannel.Result? = null
    private var pendingExportContent: String? = null

    fun configure(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPrivateKey" -> result.success(hasPrivateKey())
                "readPrivateKey" -> {
                    try {
                        result.success(readPrivateKey())
                    } catch (error: Exception) {
                        result.error(
                            "PRIVATE_KEY_READ_FAILED",
                            error.message ?: "Unable to read private key.",
                            null,
                        )
                    }
                }
                "importPrivateKey" -> handleImport(result)
                "storePrivateKey" -> handleStorePrivateKey(call, result)
                "clearPrivateKey" -> {
                    clearPrivateKey()
                    result.success(null)
                }
                "hasAdminToken" -> result.success(hasAdminToken())
                "readAdminToken" -> {
                    try {
                        result.success(readAdminToken())
                    } catch (error: Exception) {
                        result.error(
                            "ADMIN_TOKEN_READ_FAILED",
                            error.message ?: "Unable to read admin token.",
                            null,
                        )
                    }
                }
                "storeAdminToken" -> {
                    val token = call.argument<String>("token")?.trim().orEmpty()
                    if (token.isBlank()) {
                        result.error("MISSING_ADMIN_TOKEN", "Admin token is missing.", null)
                    } else {
                        try {
                            saveSecret(
                                token,
                                PREF_ADMIN_TOKEN_CIPHER,
                                PREF_ADMIN_TOKEN_IV,
                                ADMIN_TOKEN_KEY_ALIAS,
                            )
                            result.success(null)
                        } catch (error: Exception) {
                            result.error(
                                "ADMIN_TOKEN_STORE_FAILED",
                                error.message ?: "Unable to store admin token.",
                                null,
                            )
                        }
                    }
                }
                "clearAdminToken" -> {
                    clearSecret(
                        PREF_ADMIN_TOKEN_CIPHER,
                        PREF_ADMIN_TOKEN_IV,
                        ADMIN_TOKEN_KEY_ALIAS,
                    )
                    result.success(null)
                }
                "exportText" -> handleExport(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun handleImport(result: MethodChannel.Result) {
        if (pendingImport != null || pendingExport != null) {
            result.error("FILE_DIALOG_BUSY", "A file dialog is already open.", null)
            return
        }

        pendingImport = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
        }
        activity.startActivityForResult(intent, REQUEST_IMPORT)
    }

    private fun handleStorePrivateKey(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val keyText = call.argument<String>("privateKey")
            ?.trim()
            .orEmpty()

        if (keyText.isBlank()) {
            result.error(
                "MISSING_PRIVATE_KEY",
                "Private key is missing.",
                null,
            )
            return
        }

        try {
            validatePrivateKeyText(keyText)
            savePrivateKey(keyText)
            result.success(null)
        } catch (error: Exception) {
            result.error(
                "PRIVATE_KEY_STORE_FAILED",
                error.message ?: "Unable to store private key.",
                null,
            )
        }
    }

    private fun handleExport(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        if (pendingImport != null || pendingExport != null) {
            result.error("FILE_DIALOG_BUSY", "A file dialog is already open.", null)
            return
        }

        val fileName = call.argument<String>("fileName")
            ?.trim()
            .orEmpty()
            .ifBlank { "activation-codes.csv" }
        val content = call.argument<String>("content")
        val mimeType = call.argument<String>("mimeType")
            ?.trim()
            .orEmpty()
            .ifBlank { "text/plain" }

        if (content == null) {
            result.error("MISSING_CONTENT", "Export content is missing.", null)
            return
        }

        pendingExport = result
        pendingExportContent = content

        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mimeType
            putExtra(Intent.EXTRA_TITLE, fileName)
        }
        activity.startActivityForResult(intent, REQUEST_EXPORT)
    }

    fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ): Boolean {
        return when (requestCode) {
            REQUEST_IMPORT -> {
                finishImport(resultCode, data?.data)
                true
            }
            REQUEST_EXPORT -> {
                finishExport(resultCode, data?.data)
                true
            }
            else -> false
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
                ?: throw IllegalStateException("Unable to open private key file.")
            val text = stream.bufferedReader(Charsets.UTF_8).use { it.readText() }
            val keyText = extractPrivateKeyText(text)
            validatePrivateKeyText(keyText)

            // Do not persist yet. Dart first verifies that this private seed
            // really matches the buyer app's embedded public key.
            result.success(keyText)
        } catch (error: Exception) {
            result.error(
                "PRIVATE_KEY_IMPORT_FAILED",
                error.message ?: "Private key import failed.",
                null,
            )
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
            result.error("MISSING_CONTENT", "Export content was lost.", null)
            return
        }

        try {
            val stream = activity.contentResolver.openOutputStream(uri, "wt")
                ?: throw IllegalStateException("Unable to open export destination.")
            stream.bufferedWriter(Charsets.UTF_8).use { writer ->
                writer.write(content)
            }
            result.success(true)
        } catch (error: Exception) {
            result.error(
                "EXPORT_FAILED",
                error.message ?: "Export failed.",
                null,
            )
        }
    }

    private fun extractPrivateKeyText(text: String): String {
        return text
            .lineSequence()
            .map { it.trim() }
            .filter { it.isNotEmpty() && !it.startsWith("#") }
            .lastOrNull()
            ?: throw IllegalArgumentException("Private key file is empty.")
    }

    private fun validatePrivateKeyText(keyText: String) {
        val decoded = Base64.decode(
            keyText,
            Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP,
        )
        if (decoded.size != 32) {
            throw IllegalArgumentException("Private key length is invalid.")
        }
    }

    private fun prefs() =
        activity.getSharedPreferences(PREFS, Activity.MODE_PRIVATE)

    private fun hasPrivateKey(): Boolean =
        hasSecret(PREF_CIPHER, PREF_IV)

    private fun hasAdminToken(): Boolean =
        hasSecret(PREF_ADMIN_TOKEN_CIPHER, PREF_ADMIN_TOKEN_IV)

    private fun savePrivateKey(value: String) {
        saveSecret(value, PREF_CIPHER, PREF_IV, KEY_ALIAS)
    }

    private fun readPrivateKey(): String? =
        readSecret(PREF_CIPHER, PREF_IV, KEY_ALIAS)

    private fun readAdminToken(): String? =
        readSecret(
            PREF_ADMIN_TOKEN_CIPHER,
            PREF_ADMIN_TOKEN_IV,
            ADMIN_TOKEN_KEY_ALIAS,
        )

    private fun clearPrivateKey() {
        clearSecret(PREF_CIPHER, PREF_IV, KEY_ALIAS)
    }

    private fun hasSecret(cipherPref: String, ivPref: String): Boolean {
        val prefs = prefs()
        return prefs.contains(cipherPref) && prefs.contains(ivPref)
    }

    private fun saveSecret(
        value: String,
        cipherPref: String,
        ivPref: String,
        keyAlias: String,
    ) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateSecretKey(keyAlias))
        val encrypted = cipher.doFinal(
            value.toByteArray(StandardCharsets.UTF_8),
        )

        val saved = prefs().edit()
            .putString(
                cipherPref,
                Base64.encodeToString(encrypted, Base64.NO_WRAP),
            )
            .putString(
                ivPref,
                Base64.encodeToString(cipher.iv, Base64.NO_WRAP),
            )
            .commit()
        if (!saved) {
            throw IllegalStateException("Unable to save secure value.")
        }
    }

    private fun readSecret(
        cipherPref: String,
        ivPref: String,
        keyAlias: String,
    ): String? {
        if (!hasSecret(cipherPref, ivPref)) return null

        val prefs = prefs()
        val cipherText = prefs.getString(cipherPref, null) ?: return null
        val ivText = prefs.getString(ivPref, null) ?: return null
        val cipherBytes = Base64.decode(cipherText, Base64.NO_WRAP)
        val ivBytes = Base64.decode(ivText, Base64.NO_WRAP)

        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            getOrCreateSecretKey(keyAlias),
            GCMParameterSpec(128, ivBytes),
        )
        val plain = cipher.doFinal(cipherBytes)
        return String(plain, StandardCharsets.UTF_8)
    }

    private fun clearSecret(
        cipherPref: String,
        ivPref: String,
        keyAlias: String,
    ) {
        val cleared = prefs().edit()
            .remove(cipherPref)
            .remove(ivPref)
            .commit()
        if (!cleared) {
            throw IllegalStateException("Unable to clear secure value.")
        }

        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply {
            load(null)
        }
        if (keyStore.containsAlias(keyAlias)) {
            keyStore.deleteEntry(keyAlias)
        }
    }

    private fun getOrCreateSecretKey(keyAlias: String): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply {
            load(null)
        }

        val existing = keyStore.getKey(keyAlias, null)
        if (existing is SecretKey) return existing

        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            "AndroidKeyStore",
        )
        generator.init(
            KeyGenParameterSpec.Builder(
                keyAlias,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }
}
