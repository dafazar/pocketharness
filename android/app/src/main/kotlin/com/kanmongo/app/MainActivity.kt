// android/app/src/main/kotlin/com/kanmongo/app/MainActivity.kt
//
// MainActivity for KanMonAI
//
// Registers:
//   ✅ LlamaPlugin          — GGUF offline inference (MethodChannel + EventChannel)
//   ✅ TermuxBridgePlugin   — Termux RUN_COMMAND integration
//   ✅ device_info channel  — getSdkInt() used by Dart permission logic
//   ✅ storage_permission   — requestManageExternalStorage() for model import

package com.kanmongo.app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL_DEVICE_INFO  = "kanmongo/device_info"
        private const val CHANNEL_STORAGE_PERM = "kanmongo/storage_permission"
    }

    private var llamaPlugin: LlamaPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── LlamaPlugin ─────────────────────────────────────────────────────
        llamaPlugin = LlamaPlugin.register(
            flutterEngine.dartExecutor.binaryMessenger,
            applicationContext
        )

        // ── TermuxBridgePlugin ───────────────────────────────────────────────
        flutterEngine.plugins.add(TermuxBridgePlugin())

        // ── NativeEnvPlugin ──────────────────────────────────────────────────
        // Fallback untuk menjalankan bundled binary tanpa Termux
        flutterEngine.plugins.add(NativeEnvPlugin())

        // ── Device Info Channel ──────────────────────────────────────────────
        // Used by Dart to get SDK_INT without device_info_plus dependency
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_DEVICE_INFO
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getSdkInt" -> result.success(Build.VERSION.SDK_INT)
                else        -> result.notImplemented()
            }
        }

        // ── Storage Permission Channel ───────────────────────────────────────
        // Handles MANAGE_EXTERNAL_STORAGE which cannot be requested via
        // permission_handler on Android 11+ (API 30+). Must open Settings intent.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_STORAGE_PERM
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isManageExternalStorageGranted" -> {
                    val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        Environment.isExternalStorageManager()
                    } else {
                        // Below Android 11: READ_EXTERNAL_STORAGE is sufficient
                        true
                    }
                    result.success(granted)
                }

                "requestManageExternalStorage" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        if (Environment.isExternalStorageManager()) {
                            result.success(true)
                        } else {
                            try {
                                val intent = Intent(
                                    Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                                    Uri.parse("package:${applicationContext.packageName}")
                                )
                                startActivity(intent)
                                // Return false — Dart must re-check after user returns
                                result.success(false)
                            } catch (e: Exception) {
                                try {
                                    val intent = Intent(
                                        Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION
                                    )
                                    startActivity(intent)
                                    result.success(false)
                                } catch (e2: Exception) {
                                    result.error(
                                        "SETTINGS_ERROR",
                                        "Cannot open storage settings: ${e2.message}",
                                        null
                                    )
                                }
                            }
                        }
                    } else {
                        // Android < 11: MANAGE_EXTERNAL_STORAGE not needed
                        result.success(true)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        llamaPlugin?.destroy()
        llamaPlugin = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
