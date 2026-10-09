// android/app/src/main/kotlin/com/pocketharness/app/NativeEnvPlugin.kt
//
// PocketHarness — NativeEnvPlugin (Sesi 3)
// Kotlin bridge untuk menjalankan binary dari internal storage (bundled tools).
// Digunakan sebagai fallback jika Termux tidak tersedia.
//
// MethodChannel: "com.kanmongo.app/native_env"
// Methods:
//   • runCommand       — jalankan executable dari internal storage
//   • chmodExecutable  — set executable bit pada file
//   • fileExists       — cek apakah file ada
// =============================================================================

package com.pocketharness.app

import android.content.Context
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import java.io.File
import java.util.concurrent.TimeUnit

private const val TAG_ENV = "NativeEnvPlugin"
private const val CHANNEL_ENV = "com.kanmongo.app/native_env"

class NativeEnvPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel
    private var appContext: Context? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_ENV)
        channel.setMethodCallHandler(this)
        Log.d(TAG_ENV, "NativeEnvPlugin attached")
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        scope.cancel()
        appContext = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "runCommand"       -> handleRunCommand(call, result)
            "chmodExecutable"  -> handleChmod(call, result)
            "fileExists"       -> handleFileExists(call, result)
            else               -> result.notImplemented()
        }
    }

    // ── runCommand ──────────────────────────────────────────────────────────

    private fun handleRunCommand(call: MethodCall, result: MethodChannel.Result) {
        val executable = call.argument<String>("executable") ?: run {
            result.error("MISSING_ARG", "executable is required", null)
            return
        }
        val args      = call.argument<List<String>>("args") ?: emptyList()
        val workDir   = call.argument<String>("workDir")
        val envMap    = call.argument<Map<String, String>>("env") ?: emptyMap()
        val timeoutMs = call.argument<Int>("timeoutMs") ?: 30_000

        scope.launch {
            try {
                val command = mutableListOf(executable).also { it.addAll(args) }
                val pb = ProcessBuilder(command).apply {
                    workDir?.let { directory(File(it)) }
                    environment().putAll(envMap)
                    redirectErrorStream(false)
                }

                val proc = pb.start()

                // Read stdout/stderr in parallel to avoid buffer deadlock
                val stdoutJob = async(Dispatchers.IO) {
                    proc.inputStream.bufferedReader().readText()
                }
                val stderrJob = async(Dispatchers.IO) {
                    proc.errorStream.bufferedReader().readText()
                }

                val stdout = stdoutJob.await()
                val stderr = stderrJob.await()

                val exited = proc.waitFor(timeoutMs.toLong(), TimeUnit.MILLISECONDS)
                if (!exited) {
                    proc.destroyForcibly()
                    Log.w(TAG_ENV, "Process timed out after ${timeoutMs}ms: $executable")
                }
                val exitCode = if (exited) proc.exitValue() else -1

                withContext(Dispatchers.Main) {
                    result.success(
                        mapOf(
                            "stdout"   to stdout,
                            "stderr"   to stderr,
                            "exitCode" to exitCode,
                        )
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG_ENV, "runCommand error for '$executable': ${e.message}")
                withContext(Dispatchers.Main) {
                    result.error("EXEC_ERROR", e.message ?: "Unknown error", null)
                }
            }
        }
    }

    // ── chmodExecutable ─────────────────────────────────────────────────────

    private fun handleChmod(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path") ?: run {
            result.error("MISSING_ARG", "path is required", null)
            return
        }
        scope.launch {
            try {
                val file = File(path)
                val ok = file.exists() &&
                         file.setExecutable(true, false) &&
                         file.setReadable(true, false)
                Log.d(TAG_ENV, "chmod $path → $ok")
                withContext(Dispatchers.Main) { result.success(ok) }
            } catch (e: Exception) {
                Log.e(TAG_ENV, "chmod error: ${e.message}")
                withContext(Dispatchers.Main) {
                    result.error("CHMOD_ERROR", e.message ?: "Unknown error", null)
                }
            }
        }
    }

    // ── fileExists ──────────────────────────────────────────────────────────

    private fun handleFileExists(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path") ?: run {
            result.error("MISSING_ARG", "path is required", null)
            return
        }
        result.success(File(path).exists())
    }
}
