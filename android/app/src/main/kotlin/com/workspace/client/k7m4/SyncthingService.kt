package com.workspace.client.k7m4

import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.util.Log
import java.io.File
import java.util.concurrent.Executors

class SyncthingService : Service() {
    companion object {
        const val ACTION_START = "com.workspace.client.k7m4.SYNCTHING_START"
        const val ACTION_STOP = "com.workspace.client.k7m4.SYNCTHING_STOP"
        const val API_PORT = BuildConfig.SYNCTHING_API_PORT
        const val PREF_FILE = "embedded_syncthing"
        const val PREF_API_KEY = "api_key"
        private const val TAG = "EmbeddedSyncthing"

        @Volatile
        var isRunning: Boolean = false
            private set
    }

    private val executor = Executors.newSingleThreadExecutor()
    private var process: Process? = null

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int,
    ): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopSyncthing()
                stopSelf()
                return START_NOT_STICKY
            }

            else -> startSyncthing()
        }
        // The sync core now exists only while the app itself is in the
        // foreground. Do not ask Android to recreate this service later.
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        stopSyncthing()
        executor.shutdownNow()
        super.onDestroy()
    }

    private fun startSyncthing() {
        if (process?.isAlive == true) {
            isRunning = true
            return
        }

        val apiKey = getSharedPreferences(PREF_FILE, MODE_PRIVATE)
            .getString(PREF_API_KEY, null)
        if (apiKey.isNullOrBlank()) {
            Log.e(TAG, "Missing local API key")
            stopSelf()
            return
        }

        val binary = File(applicationInfo.nativeLibraryDir, "libsyncthing.so")
        if (!binary.exists()) {
            Log.e(TAG, "Embedded Syncthing binary not found: ${binary.absolutePath}")
            stopSelf()
            return
        }

        executor.execute {
            try {
                val configDir = File(filesDir, "syncthing-config").apply {
                    mkdirs()
                }

                val started = ProcessBuilder(
                    binary.absolutePath,
                    "--home",
                    configDir.absolutePath,
                    "--gui-address",
                    "127.0.0.1:$API_PORT",
                    "--gui-apikey",
                    apiKey,
                    "--no-browser",
                    "--no-restart",
                    "--log-max-old-files=0",
                ).apply {
                    redirectErrorStream(true)
                    environment()["STNORESTART"] = "1"
                    environment()["STNODEFAULTFOLDER"] = "1"
                }.start()

                process = started
                isRunning = true

                Thread {
                    runCatching {
                        started.inputStream.bufferedReader().useLines { lines ->
                            lines.forEach { line -> Log.d(TAG, line) }
                        }
                    }
                }.start()

                val exitCode = started.waitFor()
                Log.i(TAG, "Syncthing exited with code $exitCode")
            } catch (error: Exception) {
                Log.e(TAG, "Syncthing process failed", error)
            } finally {
                process = null
                isRunning = false
                stopSelf()
            }
        }
    }

    private fun stopSyncthing() {
        runCatching { process?.destroy() }
        process = null
        isRunning = false
    }

}
