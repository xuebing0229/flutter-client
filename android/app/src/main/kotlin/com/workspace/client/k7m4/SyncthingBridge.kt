package com.workspace.client.k7m4

import android.content.Context
import android.content.Intent
import android.util.Base64
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.ServerSocket
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
    private var integrationPolicyApplied = false

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
                    shutdownCoreThenStopService()
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
        ensureApiPort()
        val startRequested = startService()

        val ready = pingReady()
        if (ready) {
            applyIntegrationPolicy()
        }
        return linkedMapOf(
            "available" to true,
            "running" to ready,
            "error" to when {
                ready -> null
                !startRequested -> "APP_BACKGROUND_START_DEFERRED"
                else -> "SYNCTHING_STARTING"
            },
        )
    }

    private fun ensureReady() {
        val state = ensureStarted()
        if (state["available"] != true) {
            throw IllegalStateException(state["error"]?.toString() ?: "同步核心不可用")
        }
        if (state["running"] != true) {
            val reason = state["error"]?.toString()
            throw IllegalStateException(
                if (reason == "SYNCTHING_STARTING") {
                    "同步核心正在启动，请稍后重试"
                } else {
                    reason ?: "同步核心正在启动，请稍后重试"
                },
            )
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

        if (!pingReady()) {
            return linkedMapOf(
                "available" to true,
                "running" to false,
            )
        }
        applyIntegrationPolicy()

        val system = JSONObject(request("GET", "/rest/system/status"))
        val version = JSONObject(request("GET", "/rest/system/version"))
        val configured = JSONArray(request("GET", "/rest/config/devices"))
        val folders = JSONArray(request("GET", "/rest/config/folders"))
        val connections = JSONObject(request("GET", "/rest/system/connections"))
            .optJSONObject("connections") ?: JSONObject()

        val allConfiguredDevices = mutableListOf<Map<String, Any?>>()
        for (index in 0 until configured.length()) {
            val item = configured.optJSONObject(index) ?: continue
            val id = item.optString("deviceID")
            if (id.isBlank()) continue
            allConfiguredDevices += linkedMapOf(
                "deviceId" to id,
                "name" to item.optString("name"),
            )
        }

        val allConnectedDeviceIds = mutableListOf<String>()
        val allConnectionKeys = connections.keys()
        while (allConnectionKeys.hasNext()) {
            val id = allConnectionKeys.next()
            val item = connections.optJSONObject(id) ?: continue
            if (item.optBoolean("connected", false)) {
                allConnectedDeviceIds += id
            }
        }

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
        val remoteFolderStates = linkedMapOf<String, String>()
        val folderErrors = mutableListOf<String>()
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

            runCatching {
                JSONObject(
                    request(
                        "GET",
                        "/rest/folder/errors?folder=$encodedFolder",
                    ),
                )
            }.getOrNull()
                ?.optJSONArray("errors")
                ?.let { errors ->
                    for (index in 0 until errors.length()) {
                        val message = errors.optJSONObject(index)
                            ?.optString("error")
                            .orEmpty()
                            .trim()
                        if (message.isNotBlank()) folderErrors += message
                    }
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

                val remoteState = completion.optString("remoteState").trim()
                if (remoteState.isNotEmpty()) {
                    remoteFolderStates[remoteId] = remoteState
                }

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
                    "remoteState" to remoteState,
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
            "allConnectedDeviceIds" to allConnectedDeviceIds,
            "allConfiguredDevices" to allConfiguredDevices,
            "folderState" to folderState,
            "remoteFolderStates" to remoteFolderStates,
            "folderErrors" to folderErrors,
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
            val payload = JSONObject(request("GET", "/rest/config/defaults/folder"))
                .put("id", folderId)
                .put("label", label)
                .put("path", path)
                .put("type", "sendreceive")
                .put("devices", JSONArray())
            request("POST", "/rest/config/folders", payload.toString())
            return
        }

        val unchanged =
            existing.optString("label") == label &&
                existing.optString("path") == path &&
                existing.optString("type") == "sendreceive"
        if (unchanged) return

        val patch = JSONObject()
            .put("label", label)
            .put("path", path)
            .put("type", "sendreceive")
        request(
            "PATCH",
            "/rest/config/folders/" + encodePathSegment(folderId),
            patch.toString(),
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
            val payload = JSONObject(request("GET", "/rest/config/defaults/device"))
                .put("deviceID", normalizedId)
                .put("name", name.ifBlank { normalizedId.take(7) })
                .put("addresses", JSONArray().put("dynamic"))
            request("POST", "/rest/config/devices", payload.toString())
        } else if (
            name.isNotBlank() &&
            existingDevice.optString("name").trim() != name.trim()
        ) {
            request(
                "PATCH",
                "/rest/config/devices/" + encodePathSegment(normalizedId),
                JSONObject().put("name", name.trim()).toString(),
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
            request(
                "PATCH",
                "/rest/config/folders/" + encodePathSegment(folderId),
                JSONObject().put("devices", sharedDevices).toString(),
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

        request(
            "PATCH",
            "/rest/config/folders/" + encodePathSegment(folderId),
            JSONObject().put("devices", filtered).toString(),
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
            request(
                "PATCH",
                "/rest/config/folders/" + encodePathSegment(folderId),
                JSONObject().put("paused", paused).toString(),
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
        if (!hasActiveFolder) shutdownCoreThenStopService()
    }

    private fun startService(): Boolean {
        // Calling startService() again while the process is already alive is
        // unnecessary, and Android rejects that call when the app briefly
        // moves to the background (for example while exchanging the join
        // response code with another device). Keep the existing core alive
        // instead of turning a harmless background transition into a failed
        // device-join session.
        if (SyncthingService.isRunning) return true

        val intent = Intent(activity, SyncthingService::class.java).apply {
            action = SyncthingService.ACTION_START
        }
        return try {
            // This remains a normal started service: there is still no
            // permanent foreground-service notification.
            activity.startService(intent)
            true
        } catch (error: IllegalStateException) {
            val message = error.message.orEmpty()
            val backgroundBlocked =
                message.contains("Not allowed to start service") &&
                    message.contains("app is in background")
            if (!backgroundBlocked) throw error

            // Android 8+ can reject a brand-new normal service start while the
            // app is backgrounded. Surface a stable deferred state so the
            // Flutter join loop can keep the session intact and retry after
            // the app returns to the foreground.
            Log.i(
                "EmbeddedSyncthing",
                "Deferring Syncthing start until app returns to foreground",
                error,
            )
            false
        }
    }

    private fun stopService() {
        activity.stopService(Intent(activity, SyncthingService::class.java))
    }

    private fun shutdownCoreThenStopService() {
        if (SyncthingService.isRunning) {
            // Syncthing's Windows service guidance uses a ten-second graceful
            // shutdown window. Use the same conservative lifecycle boundary on
            // Android before tearing down the wrapper service.
            val deadlineNanos = System.nanoTime() + 10_000_000_000L
            runCatching {
                request("POST", "/rest/system/shutdown")
            }
            while (System.nanoTime() < deadlineNanos) {
                val stillReady = runCatching {
                    request("GET", "/rest/system/ping")
                    true
                }.getOrDefault(false)
                if (!stillReady) {
                    integrationPolicyApplied = false
                    stopService()
                    return
                }
                val remainingMillis =
                    ((deadlineNanos - System.nanoTime()) / 1_000_000L)
                        .coerceAtLeast(1L)
                Thread.sleep(minOf(100L, remainingMillis))
            }
        }
        integrationPolicyApplied = false
        stopService()
    }

    private fun applyIntegrationPolicy() {
        if (integrationPolicyApplied) return
        val payload = JSONObject()
            .put("urAccepted", -1)
            .put("crashReportingEnabled", false)
            .put("autoUpgradeIntervalH", 0)
        request("PATCH", "/rest/config/options", payload.toString())
        integrationPolicyApplied = true
    }

    private fun pingReady(): Boolean {
        return runCatching {
            request("GET", "/rest/system/ping")
            true
        }.getOrDefault(false)
    }

    private fun request(
        method: String,
        path: String,
        body: String? = null,
    ): String {
        val apiPort = ensureApiPort()
        val connection = URL("http://127.0.0.1:$apiPort$path")
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

    private fun ensureApiPort(): Int {
        val preferences = activity.getSharedPreferences(
            SyncthingService.PREF_FILE,
            Context.MODE_PRIVATE,
        )
        val existing = preferences.getInt(SyncthingService.PREF_API_PORT, 0)
        if (existing in 1024..65535) return existing

        val loopback = InetAddress.getByName("127.0.0.1")
        val port = ServerSocket(0, 1, loopback).use { socket ->
            socket.localPort
        }
        check(port in 1024..65535) { "无法分配本机同步端口" }

        val saved = preferences.edit()
            .putInt(SyncthingService.PREF_API_PORT, port)
            .commit()
        check(saved) { "无法保存本机同步端口" }
        return port
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
