// android/app/src/main/kotlin/com/pocketharness/app/TermuxBridgePlugin.kt
//
// Pocket Harness — TermuxBridgePlugin (Sesi 7A Bagian 2)
// Native Android bridge untuk menjalankan perintah melalui Termux.
//
// Arsitektur:
//   • FlutterPlugin    — lifecycle plugin (attach/detach engine)
//   • ActivityAware    — akses Activity untuk Intent launch
//   • MethodCallHandler — dispatch tiga method dari Dart
//
// MethodChannel: "com.kanmongo.app/termux"
// Handler:
//   • isTermuxInstalled  → Boolean
//   • runCommand         → Map<String, Any> { stdout, stderr, exitCode }
//   • openTermux         → Unit
//
// Registration: in MainActivity.configureFlutterEngine():
//   flutterEngine.plugins.add(TermuxBridgePlugin())
// Do NOT call register() manually — that method no longer exists.
// =============================================================================
package com.pocketharness.app

import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.BufferedReader
import java.io.InputStreamReader
import java.util.concurrent.TimeUnit

private const val TAG            = "TermuxBridgePlugin"
private const val CHANNEL_NAME   = "com.kanmongo.app/termux"
private const val TERMUX_PACKAGE = "com.termux"

// =============================================================================
// TermuxBridgePlugin
// =============================================================================

class TermuxBridgePlugin : FlutterPlugin, MethodCallHandler, ActivityAware {

    // ── State -----------------------------------------------------------------

    private lateinit var channel  : MethodChannel
    private var appContext        : Context? = null
    private var currentActivity   : Activity? = null

    // Scope untuk semua coroutine plugin — dibatalkan saat plugin di-detach
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    // ── FlutterPlugin ─────────────────────────────────────────────────────────

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel   = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
        Log.d(TAG, "Plugin attached to engine")
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        scope.cancel()
        appContext = null
        Log.d(TAG, "Plugin detached from engine")
    }

    // ── ActivityAware ─────────────────────────────────────────────────────────

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        currentActivity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        currentActivity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        currentActivity = binding.activity
    }

    override fun onDetachedFromActivity() {
        currentActivity = null
    }

    // ── MethodCallHandler ─────────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "isTermuxInstalled" -> handleIsTermuxInstalled(result)
            "runCommand"        -> handleRunCommand(call, result)
            "openTermux"        -> handleOpenTermux(result)
            else                -> result.notImplemented()
        }
    }

    // =========================================================================
    // Handler — isTermuxInstalled
    // =========================================================================

    private fun handleIsTermuxInstalled(result: Result) {
        val ctx = appContext ?: run {
            Log.w(TAG, "isTermuxInstalled: context null")
            result.success(false)
            return
        }
        val installed = isTermuxInstalled(ctx)
        Log.d(TAG, "isTermuxInstalled → $installed")
        result.success(installed)
    }

    // =========================================================================
    // Handler — runCommand
    // =========================================================================

    private fun handleRunCommand(call: MethodCall, result: Result) {
        val command        = call.argument<String>("command") ?: run {
            result.error("INVALID_ARG", "Argument 'command' tidak boleh null", null)
            return
        }
        val timeoutSeconds = call.argument<Int>("timeoutSeconds") ?: 60

        Log.d(TAG, "runCommand: \"$command\" timeout=${timeoutSeconds}s")

        scope.launch {
            try {
                val map = executeCommand(command, timeoutSeconds.toLong())
                result.success(map)
            } catch (e: Exception) {
                Log.e(TAG, "runCommand error", e)
                result.error("EXEC_ERROR", e.message, null)
            }
        }
    }

    // =========================================================================
    // Handler — openTermux
    // =========================================================================

    private fun handleOpenTermux(result: Result) {
        val ctx = appContext ?: run {
            result.error("NO_CONTEXT", "Context tidak tersedia", null)
            return
        }

        val pm     = ctx.packageManager
        val intent = pm.getLaunchIntentForPackage(TERMUX_PACKAGE)

        if (intent == null) {
            Log.w(TAG, "openTermux: Termux tidak terinstall atau tidak ada launch intent")
            result.error("NOT_FOUND", "Termux tidak terinstall", null)
            return
        }

        // Coba pakai Activity agar animasi transisi wajar; fallback ke context
        val activity = currentActivity
        if (activity != null) {
            intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
            activity.startActivity(intent)
        } else {
            intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
            ctx.startActivity(intent)
        }

        Log.d(TAG, "openTermux: Termux dibuka")
        result.success(null)
    }

    // =========================================================================
    // Core — executeCommand
    // =========================================================================

    /**
     * Menjalankan [command] dalam shell (`sh -c`) di IO thread.
     *
     * Stdout dan stderr dibaca secara paralel oleh dua Thread terpisah
     * agar tidak deadlock pada pipe buffer yang penuh.
     * Jika proses tidak selesai dalam [timeoutSeconds] detik, proses
     * dihancurkan secara paksa (destroy → destroyForcibly).
     *
     * @return Map dengan kunci `stdout`, `stderr`, `exitCode`.
     */
    private suspend fun executeCommand(
        command: String,
        timeoutSeconds: Long,
    ): Map<String, Any> = withContext(Dispatchers.IO) {

        val stdoutBuilder = StringBuilder()
        val stderrBuilder = StringBuilder()
        var exitCode      = -1

        // Jalankan proses via sh -c agar pipeline, redirect, dll bekerja
        // BUG FIX: Inject Termux PATH agar binary Termux bisa diakses
        val termuxPrefix = "/data/data/com.termux/files/usr"
        val termuxBin    = "$termuxPrefix/bin"
        val systemPath   = "/system/bin:/system/xbin"
        val fullPath     = "$termuxBin:$systemPath"

        val pb = ProcessBuilder("sh", "-c", command)
        pb.environment().apply {
            put("PATH", fullPath)
            put("PREFIX", termuxPrefix)
            put("LD_LIBRARY_PATH", "$termuxPrefix/lib")
            put("HOME", "/data/data/com.termux/files/home")
            put("TMPDIR", "$termuxPrefix/../tmp")
            put("LANG", "en_US.UTF-8")
            put("TERM", "xterm-256color")
        }
        val process = pb.start()

        // Dua Thread reader — berjalan paralel, hindari deadlock buffer
        val stdoutThread = Thread {
            try {
                BufferedReader(InputStreamReader(process.inputStream)).use { reader ->
                    var line: String?
                    while (reader.readLine().also { line = it } != null) {
                        stdoutBuilder.appendLine(line)
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "stdout reader error: ${e.message}")
            }
        }.also { it.start() }

        val stderrThread = Thread {
            try {
                BufferedReader(InputStreamReader(process.errorStream)).use { reader ->
                    var line: String?
                    while (reader.readLine().also { line = it } != null) {
                        stderrBuilder.appendLine(line)
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "stderr reader error: ${e.message}")
            }
        }.also { it.start() }

        // Tunggu proses selesai dengan timeout
        val finished = process.waitFor(timeoutSeconds, TimeUnit.SECONDS)

        if (!finished) {
            Log.w(TAG, "runCommand timeout (${timeoutSeconds}s) — destroying process")
            process.destroy()
            // destroyForcibly tersedia sejak API 26 (Android 8) — project minSdk 23,
            // sehingga kita guard dengan versi check
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                process.destroyForcibly()
            }
            stderrBuilder.appendLine("[Pocket Harness] Proses timeout setelah ${timeoutSeconds}s dan dihentikan paksa.")
        } else {
            exitCode = process.exitValue()
        }

        // Pastikan reader threads selesai sebelum mengambil output-nya
        stdoutThread.join(2_000)
        stderrThread.join(2_000)

        Log.d(TAG, "runCommand done: exitCode=$exitCode " +
                "stdout=${stdoutBuilder.length}c stderr=${stderrBuilder.length}c")

        mapOf(
            "stdout"   to stdoutBuilder.toString(),
            "stderr"   to stderrBuilder.toString(),
            "exitCode" to exitCode,
        )
    }

    // =========================================================================
    // Helper
    // =========================================================================

    /**
     * Mengecek keberadaan package [TERMUX_PACKAGE] via PackageManager.
     * Handle deprecated API di Android 13+ (API 33).
     */
    private fun isTermuxInstalled(context: Context): Boolean {
        return try {
            val pm = context.packageManager
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                // API 33+ — gunakan PackageInfoFlags
                pm.getPackageInfo(TERMUX_PACKAGE, android.content.pm.PackageManager.PackageInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                pm.getPackageInfo(TERMUX_PACKAGE, 0)
            }
            true
        } catch (_: PackageManager.NameNotFoundException) {
            false
        } catch (e: Exception) {
            Log.e(TAG, "isTermuxInstalled unexpected error", e)
            false
        }
    }
}
