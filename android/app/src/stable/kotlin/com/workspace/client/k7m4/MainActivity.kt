package com.workspace.client.k7m4

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private lateinit var backupFileBridge: BackupFileBridge
    private lateinit var feedbackLinkBridge: FeedbackLinkBridge
    private lateinit var orderReminderBridge: OrderReminderBridge
    private lateinit var syncthingBridge: SyncthingBridge

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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
}
