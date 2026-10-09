package com.workspace.client.k7m4

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import java.io.File
import java.util.concurrent.Executors

class SyncthingService : Service() {
    companion object {
        const val ACTION_START = "com.workspace.client.k7m4.SYNCTHING_START"
        const val ACTION_STOP = "com.workspace.client.k7m4.SYNCTHING_STOP"
        const val CHANNEL_ID = "device_sync"
        const val NOTIFICATION_ID = 4107
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

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

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
        return START_STICKY
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
            ensureForeground()
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

        ensureForeground()

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

    private fun ensureForeground() {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun buildNotification(): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent()
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setContentTitle("冒险者公会 · 设备同步")
            .setContentText("同步已开启，有改动时会自动传输")
            .setContentIntent(pendingIntent)
            // Android 13+ allows foreground-service notifications to be
            // dismissed by the user. Do not force this low-priority standby
            // notice to stay pinned in the notification shade.
            .setOngoing(Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "设备同步",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "用于手机和电脑之间的端到端数据同步"
                setShowBadge(false)
            },
        )
    }
}
