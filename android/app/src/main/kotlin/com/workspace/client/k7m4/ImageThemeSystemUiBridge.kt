package com.workspace.client.k7m4

import android.app.Activity
import android.graphics.Color
import android.os.Build
import androidx.core.view.WindowCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Temporarily enables edge-to-edge only while the imported-image theme is
 * active, then restores the exact Android window state that existed before it.
 *
 * Color themes never call this bridge on startup, so their original system-bar
 * behavior remains untouched.
 */
class ImageThemeSystemUiBridge(
    private val activity: Activity,
) {
    companion object {
        private const val CHANNEL = "app.image_theme_system_ui"
    }

    private data class WindowSnapshot(
        val statusBarColor: Int,
        val navigationBarColor: Int,
        val navigationBarDividerColor: Int?,
        val systemUiVisibility: Int,
        val statusBarContrastEnforced: Boolean?,
        val navigationBarContrastEnforced: Boolean?,
    )

    private var snapshot: WindowSnapshot? = null

    fun configure(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "enterImageTheme" -> {
                    activity.runOnUiThread {
                        enterImageTheme()
                        result.success(null)
                    }
                }

                "exitImageTheme" -> {
                    activity.runOnUiThread {
                        exitImageTheme()
                        result.success(null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun enterImageTheme() {
        val window = activity.window
        if (snapshot == null) {
            snapshot = WindowSnapshot(
                statusBarColor = window.statusBarColor,
                navigationBarColor = window.navigationBarColor,
                navigationBarDividerColor =
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        window.navigationBarDividerColor
                    } else {
                        null
                    },
                systemUiVisibility = window.decorView.systemUiVisibility,
                statusBarContrastEnforced =
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        window.isStatusBarContrastEnforced
                    } else {
                        null
                    },
                navigationBarContrastEnforced =
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        window.isNavigationBarContrastEnforced
                    } else {
                        null
                    },
            )
        }

        WindowCompat.setDecorFitsSystemWindows(window, false)
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.navigationBarDividerColor = Color.TRANSPARENT
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isStatusBarContrastEnforced = false
            window.isNavigationBarContrastEnforced = false
        }
    }

    private fun exitImageTheme() {
        val original = snapshot ?: return
        val window = activity.window

        WindowCompat.setDecorFitsSystemWindows(window, true)
        window.statusBarColor = original.statusBarColor
        window.navigationBarColor = original.navigationBarColor
        window.decorView.systemUiVisibility = original.systemUiVisibility

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            original.navigationBarDividerColor?.let {
                window.navigationBarDividerColor = it
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            original.statusBarContrastEnforced?.let {
                window.isStatusBarContrastEnforced = it
            }
            original.navigationBarContrastEnforced?.let {
                window.isNavigationBarContrastEnforced = it
            }
        }

        snapshot = null
    }
}
