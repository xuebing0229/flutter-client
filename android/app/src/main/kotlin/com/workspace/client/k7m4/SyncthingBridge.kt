package com.workspace.client.k7m4

import android.content.Context
import android.content.Intent
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URI
import java.net.URLEncoder
import java.net.URL
import java.security.SecureRandom
import java.util.concurrent.Executors

class SyncthingBridge(
    private val activity: FlutterActivity,
) {
    companion object {
        private const val CHANNEL = "app.syncthing"
    }

    private val executor = Executors.newSingleThreadExecutor()

    fun configure(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAutoStartEnabled" -> background(result) {
                    val folderId = required(call.argument<String>("folderId"), "folderId")
                    autoStartEnabled(folderId)
                }

                "ensureStarted" -> background(result) {
                    ensureStarted()
                }

                "status" -> background(result) {
                    val folderId = call.argument<String>("folderId").orEmpty()
                    status(folderId)
                }

                "configureFolder" -> background(result) {
                    val folderId = required(call.argument<String>("folderId"), "folderId")
                    val label = required(call.argument<String>("label"), "label")
                    val path = required(call.argument<String>("path"), "path")
                    ensureReady()
                    configureFolder(folderId, label, path)
                    null
                }

                "pairDevice" -> background(result) {
                    val folderId = required(call.argument<String>("folderId"), "folderId")
                    val deviceId = required(call.argument<String>("deviceId"), "deviceId")
                    val name = call.argument<String>("name").orEmpty()
                    ensureReady()
                    pairDevice(folderId, deviceId, name)
                    activity.getSharedPreferences(
                        SyncthingService.PREF_FILE,
                        Context.MODE_PRIVATE,
                    ).edit()
                        .putBoolean(autoStartKey(folderId), true)
                        .apply()
                    null
                }

                "unshareDevice" -> background(result) {
                    val folderId = required(call.argument<String>("folderId"), "folderId")
                    val deviceId = required(call.argument<String>("deviceId"), "deviceId")
                    ensureReady()
                    unshareDevice(folderId, deviceId)
                    null
                }

                "removeFolder" -> background(result) {
                    val folderId = required(call.argument<String>("folderId"), "folderId")
                    ensureReady()
                    removeFolder(folderId)
                    activity.getSharedPreferences(
                        SyncthingService.PREF_FILE,
                        Context.MODE_PRIVATE,
                    ).edit()
                        .remove(autoStartKey(folderId))
                        .remove(pausedKey(folderId))
                        .apply()
                    null
                }

                "requestScan" -> background(result) {
                    val folderId = required(call.argument<String>("folderId"), "folderId")
                    ensureReady()
                    request(
                        method = "POST",
                        path = "/rest/db/scan?folder=" +
                            URLEncoder.encode(folderId, Charsets.UTF_8.name()),
                    )
                    null
                }

                "setFolderPaused" -> background(result) {
                    val folderId = required(call.argument<String>("folderId"), "folderId")
                    val paused = call.argument<Boolean>("paused") ?: false
                    ensureReady()
                    setFolderPaused(folderId, paused)
                    null
                }

                "stop" -> background(result) {
                    stopService()
                    null
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun background(
        result: MethodChannel.Result,
        action: () -> Any?,
    ) {
        executor.execute {
            try {
                val value = action()
                activity.runOnUiThread { result.success(value) }
            } catch (error: Exception) {
                activity.runOnUiThread {
                    result.error(
                        "SYNCTHING_ERROR",
                        error.message ?: error.javaClass.simpleName,
                        null,
                    )
                }
            }
        }
    }

    private fun autoStartEnabled(folderId: String): Boolean {
        return activity.getSharedPreferences(
            SyncthingService.PREF_FILE,
            Context.MODE_PRIVATE,
        ).getBoolean(autoStartKey(folderId), false)
    }

    private fun autoStartKey(folderId: String): String {
        return "auto_start_${folderId.replace(Regex("[^A-Za-z0-9._-]"), "_")}"
    }

    private fun ensureStarted(): Map<String, Any?> {
        val binary = binaryFile()
        if (!binary.exists()) {
            return linkedMapOf(
                "available" to false,
                "running" to false,
                "error" to "安装包中缺少同步核心",
            )
        }

        ensureApiKey()
        startService()

        val ready = waitForReady()
        return linkedMapOf(
            "available" to true,
            "running" to ready,
        )
    }

    private fun ensureReady() {
        val state = ensureStarted()
        if (state["available"] != true) {
            throw IllegalStateException(state["error"]?.toString() ?: "同步核心不可用")
        }
        if (state["running"] != true) {
            throw IllegalStateException("同步核心启动超时")
        }
    }

    private fun status(folderId: String): Map<String, Any?> {
        val binary = binaryFile()
        if (!binary.exists()) {
            return linkedMapOf(
                "available" to false,
                "running" to false,
                "error" to "安装包中缺少同步核心",
            )
        }

        if (!SyncthingService.isRunning) {
            return linkedMapOf(
                "available" to true,
                "running" to false,
            )
        }

        if (!waitForReady(maxAttempts = 2)) {
            return linkedMapOf(
                "available" to true,
                "running" to false,
            )
        }

        val system = JSONObject(request("GET", "/rest/system/status"))
        val version = JSONObject(request("GET", "/rest/system/version"))
        val configured = JSONArray(request("GET", "/rest/config/devices"))
        val folders = JSONArray(request("GET", "/rest/config/folders"))
        val connections = JSONObject(request("GET", "/rest/system/connections"))
            .optJSONObject("connections") ?: JSONObject()

        val folderDeviceIds = mutableSetOf<String>()
        for (index in 0 until folders.length()) {
            val folder = folders.optJSONObject(index) ?: continue
            if (folder.optString("id") != folderId) continue
            val devices = folder.optJSONArray("devices") ?: JSONArray()
            for (deviceIndex in 0 until devices.length()) {
                val id = devices.optJSONObject(deviceIndex)
                    ?.optString("deviceID")
                    .orEmpty()
                if (id.isNotBlank()) folderDeviceIds += id
            }
            break
        }

        val configuredDevices = mutableListOf<Map<String, Any?>>()
        for (index in 0 until configured.length()) {
            val item = configured.optJSONObject(index) ?: continue
            val id = item.optString("deviceID")
            if (id !in folderDeviceIds) continue
            configuredDevices += linkedMapOf(
                "deviceId" to id,
                "name" to item.optString("name"),
            )
        }

        val connectedDeviceIds = mutableListOf<String>()
        val connectionKeys = connections.keys()
        while (connectionKeys.hasNext()) {
            val id = connectionKeys.next()
            if (id !in folderDeviceIds) continue
            val item = connections.optJSONObject(id) ?: continue
            if (item.optBoolean("connected", false)) {
                connectedDeviceIds += id
            }
        }

        var folderState: String? = null
        var syncProgress: Map<String, Any?>? = null
        if (folderId.isNotBlank()) {
            val encodedFolder = URLEncoder.encode(folderId, Charsets.UTF_8.name())
            val candidates = mutableListOf<Map<String, Any?>>()
            val folderStatus = runCatching {
                JSONObject(
                    request(
                        "GET",
                        "/rest/db/status?folder=$encodedFolder",
                    ),
                )
            }.getOrNull()

            if (folderStatus != null) {
                folderState = folderStatus.optString("state").ifBlank { null }
                val globalBytes = folderStatus.optLong("globalBytes", 0L)
                val needBytes = folderStatus.optLong("needBytes", 0L)
                val globalItems = when {
                    folderStatus.has("globalTotalItems") ->
                        folderStatus.optLong("globalTotalItems", 0L)
                    else -> folderStatus.optLong("globalFiles", 0L)
                }
                val needItems = when {
                    folderStatus.has("needTotalItems") ->
                        folderStatus.optLong("needTotalItems", 0L)
                    else -> folderStatus.optLong("needFiles", 0L)
                }
                val completion = when {
                    globalBytes > 0L ->
                        ((globalBytes - needBytes).toDouble() / globalBytes.toDouble() * 100.0)
                            .coerceIn(0.0, 100.0)
                    globalItems > 0L ->
                        ((globalItems - needItems).toDouble() / globalItems.toDouble() * 100.0)
                            .coerceIn(0.0, 100.0)
                    else -> 100.0
                }
                candidates += linkedMapOf(
                    "deviceId" to "",
                    "deviceName" to "本机",
                    "direction" to "receiving",
                    "completion" to completion,
                    "globalBytes" to globalBytes,
                    "needBytes" to needBytes,
                    "globalItems" to globalItems,
                    "needItems" to needItems,
                )
            }

            for (remoteId in connectedDeviceIds) {
                val completion = runCatching {
                    JSONObject(
                        request(
                            "GET",
                            "/rest/db/completion?folder=$encodedFolder&device=" +
                                URLEncoder.encode(remoteId, Charsets.UTF_8.name()),
                        ),
                    )
                }.getOrNull() ?: continue

                val rawCompletion = completion.optDouble("completion", Double.NaN)
                if (rawCompletion.isNaN()) continue

                val configuredName = configuredDevices
                    .firstOrNull { it["deviceId"] == remoteId }
                    ?.get("name")
                    ?.toString()
                    ?.trim()
                    .orEmpty()
                candidates += linkedMapOf(
                    "deviceId" to remoteId,
                    "deviceName" to configuredName.ifBlank { remoteId.take(7) },
                    "direction" to "sending",
                    "completion" to rawCompletion.coerceIn(0.0, 100.0),
                    "globalBytes" to completion.optLong("globalBytes", 0L),
                    "needBytes" to completion.optLong("needBytes", 0L),
                    "globalItems" to completion.optLong("globalItems", 0L),
                    "needItems" to completion.optLong("needItems", 0L),
                )
            }

            syncProgress = candidates.minByOrNull {
                (it["completion"] as? Number)?.toDouble() ?: 100.0
            }
        }

        return linkedMapOf(
            "available" to true,
            "running" to true,
            "deviceId" to system.optString("myID"),
            "version" to version.optString("version"),
            "connectedDeviceIds" to connectedDeviceIds,
            "configuredDevices" to configuredDevices,
            "folderState" to folderState,
            "syncProgress" to syncProgress,
        )
    }

    private fun configureFolder(
        folderId: String,
        label: String,
        path: String,
    ) {
        val folders = JSONArray(request("GET", "/rest/config/folders"))
        var existing: JSONObject? = null
        for (index in 0 until folders.length()) {
            val item = folders.optJSONObject(index) ?: continue
            if (item.optString("id") == folderId) {
                existing = item
                break
            }
        }

        if (existing == null) {
            val payload = JSONObject()
                .put("id", folderId)
                .put("label", label)
                .put("path", path)
                .put("type", "sendreceive")
                .put("devices", JSONArray())
            request("POST", "/rest/config/folders", payload.toString())
            return
        }

        existing
            .put("label", label)
            .put("path", path)
            .put("type", "sendreceive")
        request(
            "PUT",
            "/rest/config/folders/" + encodePathSegment(folderId),
            existing.toString(),
        )
    }

    private fun pairDevice(
        folderId: String,
        remoteDeviceId: String,
        name: String,
    ) {
        val normalizedId = remoteDeviceId.trim()
        if (normalizedId.length < 20) {
            throw IllegalArgumentException("同步设备 ID 格式无效")
        }

        val devices = JSONArray(request("GET", "/rest/config/devices"))
        var existingDevice: JSONObject? = null
        for (index in 0 until devices.length()) {
            val item = devices.optJSONObject(index) ?: continue
            if (item.optString("deviceID") == normalizedId) {
                existingDevice = item
                break
            }
        }

        if (existingDevice == null) {
            val payload = JSONObject()
                .put("deviceID", normalizedId)
                .put("name", name.ifBlank { normalizedId.take(7) })
                .put("addresses", JSONArray().put("dynamic"))
            request("POST", "/rest/config/devices", payload.toString())
        } else if (name.isNotBlank()) {
            existingDevice.put("name", name)
            request(
                "PUT",
                "/rest/config/devices/" + encodePathSegment(normalizedId),
                existingDevice.toString(),
            )
        }

        val folders = JSONArray(request("GET", "/rest/config/folders"))
        var folder: JSONObject? = null
        for (index in 0 until folders.length()) {
            val item = folders.optJSONObject(index) ?: continue
            if (item.optString("id") == folderId) {
                folder = item
                break
            }
        }
        if (folder == null) {
            throw IllegalStateException("同步目录尚未准备好")
        }

        val sharedDevices = folder.optJSONArray("devices") ?: JSONArray()
        var present = false
        for (index in 0 until sharedDevices.length()) {
            val item = sharedDevices.optJSONObject(index) ?: continue
            if (item.optString("deviceID") == normalizedId) {
                present = true
                break
            }
        }
        if (!present) {
            sharedDevices.put(JSONObject().put("deviceID", normalizedId))
            folder.put("devices", sharedDevices)
            request(
                "PUT",
                "/rest/config/folders/" + encodePathSegment(folderId),
                folder.toString(),
            )
        }
    }

    private fun unshareDevice(
        folderId: String,
        remoteDeviceId: String,
    ) {
        val normalizedId = remoteDeviceId.trim()
        if (normalizedId.isEmpty()) return

        val folders = JSONArray(request("GET", "/rest/config/folders"))
        var folder: JSONObject? = null
        for (index in 0 until folders.length()) {
            val item = folders.optJSONObject(index) ?: continue
            if (item.optString("id") == folderId) {
                folder = item
                break
            }
        }
        if (folder == null) return

        val current = folder.optJSONArray("devices") ?: JSONArray()
        val filtered = JSONArray()
        var changed = false
        for (index in 0 until current.length()) {
            val item = current.optJSONObject(index) ?: continue
            if (item.optString("deviceID") == normalizedId) {
                changed = true
                continue
            }
            filtered.put(item)
        }
        if (!changed) return

        folder.put("devices", filtered)
        request(
            "PUT",
            "/rest/config/folders/" + encodePathSegment(folderId),
            folder.toString(),
        )
    }

    private fun removeFolder(folderId: String) {
        val folders = JSONArray(request("GET", "/rest/config/folders"))
        var exists = false
        for (index in 0 until folders.length()) {
            val item = folders.optJSONObject(index) ?: continue
            if (item.optString("id") == folderId) {
                exists = true
                break
            }
        }
        if (!exists) return

        request(
            "DELETE",
            "/rest/config/folders/" + encodePathSegment(folderId),
        )
    }

    private fun setFolderPaused(folderId: String, paused: Boolean) {
        val folders = JSONArray(request("GET", "/rest/config/folders"))
        var folder: JSONObject? = null
        for (index in 0 until folders.length()) {
            val item = folders.optJSONObject(index) ?: continue
            if (item.optString("id") == folderId) {
                folder = item
                break
            }
        }
        if (folder == null) return
        if (folder.optBoolean("paused", false) != paused) {
            folder.put("paused", paused)
            request(
                "PUT",
                "/rest/config/folders/" + encodePathSegment(folderId),
                folder.toString(),
            )
        }
        activity.getSharedPreferences(
            SyncthingService.PREF_FILE,
            Context.MODE_PRIVATE,
        ).edit()
            .putBoolean(pausedKey(folderId), paused)
            .apply()
        if (paused) stopServiceIfNoActiveFolders()
    }

    private fun pausedKey(folderId: String): String {
        return "folder_paused_${folderId.replace(Regex("[^A-Za-z0-9._-]"), "_")}"
    }

    private fun stopServiceIfNoActiveFolders() {
        val preferences = activity.getSharedPreferences(
            SyncthingService.PREF_FILE,
            Context.MODE_PRIVATE,
        )
        val hasActiveFolder = preferences.all.any { (key, value) ->
            if (!key.startsWith("auto_start_") || value != true) return@any false
            val folderId = key.removePrefix("auto_start_")
            !preferences.getBoolean("folder_paused_$folderId", false)
        }
        if (!hasActiveFolder) stopService()
    }

    private fun startService() {
        val intent = Intent(activity, SyncthingService::class.java).apply {
            action = SyncthingService.ACTION_START
        }
        // This is intentionally a normal started service. The Flutter layer
        // stops it as soon as the app leaves the foreground, so a permanent
        // foreground-service notification is unnecessary.
        activity.startService(intent)
    }

    private fun stopService() {
        activity.stopService(Intent(activity, SyncthingService::class.java))
    }

    private fun waitForReady(maxAttempts: Int = 32): Boolean {
        repeat(maxAttempts) {
            try {
                request("GET", "/rest/system/ping")
                return true
            } catch (_: Exception) {
                Thread.sleep(250)
            }
        }
        return false
    }

    private fun request(
        method: String,
        path: String,
        body: String? = null,
    ): String {
        val connection = URL("http://127.0.0.1:${SyncthingService.API_PORT}$path")
            .openConnection() as HttpURLConnection
        connection.requestMethod = method
        connection.connectTimeout = 2500
        connection.readTimeout = 6000
        connection.useCaches = false
        connection.setRequestProperty("X-API-Key", ensureApiKey())
        connection.setRequestProperty("Accept", "application/json")

        if (body != null || method == "POST" || method == "PUT" || method == "PATCH") {
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json")
            connection.outputStream.use { output ->
                if (body != null) {
                    output.write(body.toByteArray(Charsets.UTF_8))
                }
            }
        }

        try {
            val status = connection.responseCode
            val stream =
                if (status in 200..299) connection.inputStream else connection.errorStream
            val response = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
            if (status !in 200..299) {
                throw IllegalStateException(
                    "Syncthing API HTTP $status" +
                        if (response.isBlank()) "" else ": $response",
                )
            }
            return response
        } finally {
            connection.disconnect()
        }
    }

    private fun ensureApiKey(): String {
        val preferences = activity.getSharedPreferences(
            SyncthingService.PREF_FILE,
            Context.MODE_PRIVATE,
        )
        val existing = preferences.getString(
            SyncthingService.PREF_API_KEY,
            null,
        )
        if (!existing.isNullOrBlank()) return existing

        val bytes = ByteArray(32)
        SecureRandom().nextBytes(bytes)
        val generated = Base64.encodeToString(
            bytes,
            Base64.NO_WRAP or Base64.URL_SAFE,
        )
        preferences.edit()
            .putString(SyncthingService.PREF_API_KEY, generated)
            .apply()
        return generated
    }

    private fun binaryFile(): File {
        return File(activity.applicationInfo.nativeLibraryDir, "libsyncthing.so")
    }

    private fun encodePathSegment(value: String): String {
        return URI(null, null, value, null).rawPath
    }

    private fun required(value: String?, name: String): String {
        val normalized = value?.trim().orEmpty()
        if (normalized.isEmpty()) {
            throw IllegalArgumentException("$name is required")
        }
        return normalized
    }
}
