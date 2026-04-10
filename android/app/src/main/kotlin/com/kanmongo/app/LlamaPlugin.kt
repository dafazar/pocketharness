// LlamaPlugin.kt — KanMon GO
// SESI 6: Native Android Bridge — Full Refactor
// - New JNI API: nativeLoadModel with full params (context, gpu, batch, threads, flash, mlock, rope)
// - New native declarations aligned with llama_jni.cpp Sesi 6
// - EventChannel: structured events { type, ... } instead of flat token/done fields
// - ForegroundService for background generation
// - ComponentCallbacks2 memory pressure monitoring
// - Coroutine-based background execution
package com.kanmongo.app

import android.app.ActivityManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.ComponentCallbacks2
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

// ─────────────────────────────────────────────────────────────────────────────
// ForegroundService — runs during token generation
// ─────────────────────────────────────────────────────────────────────────────
class LlamaGenerationService : Service() {

    companion object {
        const val CHANNEL_ID   = "kanmongo_ai_generation"
        const val NOTIFICATION_ID = 1001

        fun start(context: Context) {
            val intent = Intent(context, LlamaGenerationService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, LlamaGenerationService::class.java))
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = buildNotification()
        startForeground(NOTIFICATION_ID, notification)
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "KanMon AI Generation",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Active during AI response generation"
                setShowBadge(false)
            }
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("KanMon AI")
            .setContentText("KanMon AI sedang menghasilkan respons...")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setOngoing(true)
            .setProgress(0, 0, true) // indeterminate
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// LlamaPlugin — main Flutter plugin bridge
// ─────────────────────────────────────────────────────────────────────────────
class LlamaPlugin(
    private val messenger: BinaryMessenger,
    private val context: Context
) : ComponentCallbacks2 {

    companion object {
        private const val TAG = "LlamaPlugin"
        private const val MCH = "com.kanmongo.llama/engine"
        private const val ECH = "com.kanmongo.llama/stream"

        init {
            System.loadLibrary("kanmongo_llama")
        }

        fun register(messenger: BinaryMessenger, context: Context): LlamaPlugin =
            LlamaPlugin(messenger, context)
    }

    // ── Flutter channels ──────────────────────────────────────────────────────
    private val methodChannel = MethodChannel(messenger, MCH)
    private val eventChannel  = EventChannel(messenger, ECH)
    private val mainHandler   = Handler(Looper.getMainLooper())

    // ── Coroutine scope for background work ───────────────────────────────────
    private val pluginScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var genJob: Job? = null

    // ── Model handle (returned by nativeLoadModel) ────────────────────────────
    @Volatile private var modelHandle: Long = 0L

    // ── EventSink with thread-safe access ────────────────────────────────────
    private var eventSink: EventChannel.EventSink? = null
    private val sinkLock = Any()

    @Volatile private var isDestroyed = false

    // ── Native declarations ───────────────────────────────────────────────────
    external fun nativeLoadModel(
        path: String, contextSize: Int, gpuLayers: Int,
        nBatch: Int, nThreads: Int, useFlashAttn: Boolean,
        memLock: Boolean, ropeBase: Float, ropeScale: Float
    ): Long

    external fun nativeReleaseModel(modelHandle: Long)

    external fun nativeGenerateTokens(
        modelHandle: Long, prompt: String,
        temp: Float, topP: Float, topK: Int, maxTokens: Int,
        seq: Int, repeatPenalty: Float, seed: Int,
        mirostatMode: Int, mirostatTau: Float, mirostatEta: Float,
        minP: Float, penalizeNl: Boolean
    ): Boolean

    external fun nativeStopGeneration(modelHandle: Long)

    external fun nativeGetModelInfo(path: String): String

    external fun nativeIsReady(modelHandle: Long): Boolean

    external fun nativeGetTokenCount(modelHandle: Long, text: String): Int

    external fun nativeGetAvailableMemoryMb(): Int

    /// Registers this LlamaPlugin instance with the native C++ layer so that
    /// JNI callbacks (token emission) can reach back into Kotlin/Flutter.
    /// MUST be called once in init, after EventChannel is set up.
    /// Without this call, g_plugin_obj in llama_jni.cpp remains null and
    /// ALL token events are silently dropped — AI produces zero output.
    external fun registerPlugin()

    // ── Initializer ──────────────────────────────────────────────────────────
    init {
        context.registerComponentCallbacks(this)

        methodChannel.setMethodCallHandler { call, result ->
            if (isDestroyed) {
                result.error("DESTROYED", "Plugin has been destroyed", null)
                return@setMethodCallHandler
            }
            try {
                when (call.method) {
                    "loadModel"            -> handleLoadModel(call, result)
                    "releaseModel"         -> handleReleaseModel(result)
                    "isModelLoaded"        -> handleIsModelLoaded(result)
                    // Both "generateTokens" (LlamaService) and "startGeneration" (OfflineAiService legacy)
                    // are routed to the same handler.
                    "generateTokens",
                    "startGeneration"      -> handleGenerateTokens(call, result)
                    "stopGeneration"       -> handleStopGeneration(result)
                    "getModelInfo"         -> handleGetModelInfo(call, result)
                    "getAvailableMemoryMb" -> handleGetAvailableMemory(result)
                    "getSystemInfo"        -> handleGetSystemInfo(result)
                    // Soft no-op for unrecognised calls — avoids MissingPluginException in Dart
                    else                   -> {
                        Log.w(TAG, "Unhandled method: ${call.method}")
                        result.success(null)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "MethodChannel error on ${call.method}: ${e.message}", e)
                result.error("LLAMA_ERROR", e.message, null)
            }
        }

        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                Log.d(TAG, "EventChannel onListen")
                synchronized(sinkLock) { eventSink = sink }
            }
            override fun onCancel(arguments: Any?) {
                Log.d(TAG, "EventChannel onCancel")
                synchronized(sinkLock) { eventSink = null }
            }
        })

        // Register this plugin instance with the native C++ layer.
        // This sets g_plugin_obj and g_emit_method in llama_jni.cpp so that
        // nativeGenerateTokens() can emit token events back to Kotlin/Flutter.
        // Without this, ALL tokens are silently dropped and AI sends nothing.
        try {
            registerPlugin()
            Log.i(TAG, "registerPlugin() OK — native callbacks wired")
        } catch (e: Exception) {
            Log.e(TAG, "registerPlugin() FAILED: ${e.message}", e)
        }
    }

    // ── Thread-safe event emitter (called from JNI callbacks too) ─────────────
    fun emitEvent(event: Map<String, Any?>) {
        synchronized(sinkLock) {
            mainHandler.post {
                synchronized(sinkLock) {
                    try {
                        eventSink?.success(event)
                    } catch (e: Exception) {
                        Log.w(TAG, "emitEvent failed: ${e.message}")
                    }
                }
            }
        }
    }

    // Called from C++ JNI via reflection to emit a single token event
    fun emitEventFromNative(type: String, token: String?, seq: Int,
                             promptTokens: Int, evalTokens: Int,
                             promptMs: Long, evalMs: Long, tokensPerSec: Double,
                             errorMsg: String?, availMb: Int) {
        val event: Map<String, Any?> = when (type) {
            "token" -> mapOf(
                "type"  to "token",
                "token" to (token ?: ""),
                "seq"   to seq
            )
            "done" -> mapOf(
                "type"         to "done",
                "seq"          to seq,
                "promptTokens" to promptTokens,
                "evalTokens"   to evalTokens,
                "promptMs"     to promptMs,
                "evalMs"       to evalMs,
                "tokensPerSec" to tokensPerSec
            )
            "error" -> mapOf(
                "type"    to "error",
                "message" to (errorMsg ?: "Unknown native error"),
                "seq"     to seq
            )
            "loading_progress" -> mapOf(
                "type"     to "loading_progress",
                "progress" to tokensPerSec.coerceIn(0.0, 1.0)  // tokensPerSec carries 0.0-1.0 progress value
            )
            "memory_warning" -> mapOf(
                "type"        to "memory_warning",
                "availableMb" to availMb
            )
            else -> mapOf("type" to type)
        }
        emitEvent(event)

        // Stop foreground service when generation is done or errored
        if (type == "done" || type == "error") {
            LlamaGenerationService.stop(context)
        }
    }

    // ── MethodChannel handlers ────────────────────────────────────────────────

    private fun handleLoadModel(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("modelPath")
        if (path.isNullOrBlank()) {
            result.error("LLAMA_ERROR", "modelPath is required", null)
            return
        }
        val contextSize    = call.argument<Int>("contextSize")         ?: 4096
        val gpuLayers      = call.argument<Int>("gpuLayers")           ?: 0
        val nBatch         = call.argument<Int>("nBatch")              ?: 512
        val nThreads       = call.argument<Int>("nThreads")            ?: 4
        val useFlashAttn   = call.argument<Boolean>("useFlashAttention") ?: false
        val useMemLock     = call.argument<Boolean>("useMemoryLock")    ?: false
        val ropeFreqBase   = (call.argument<Double>("ropeFreqBase")    ?: 0.0).toFloat()
        val ropeFreqScale  = (call.argument<Double>("ropeFreqScale")   ?: 0.0).toFloat()

        emitEvent(mapOf("type" to "loading_progress", "progress" to 0.0))

        pluginScope.launch {
            try {
                val handle = nativeLoadModel(
                    path, contextSize, gpuLayers,
                    nBatch, nThreads, useFlashAttn,
                    useMemLock, ropeFreqBase, ropeFreqScale
                )
                if (handle == 0L) {
                    mainHandler.post {
                        result.error("LLAMA_ERROR", "nativeLoadModel returned 0 — model failed to load", null)
                    }
                    return@launch
                }
                modelHandle = handle
                Log.i(TAG, "Model loaded: handle=$handle path=$path")

                // Parse model info after load
                val infoJson = nativeGetModelInfo(path)
                val info = parseModelInfoJson(infoJson)

                val event = mutableMapOf<String, Any?>(
                    "type" to "model_loaded",
                    "name" to (info["name"] ?: "unknown"),
                    "arch" to (info["arch"] ?: "unknown"),
                    "contextLength" to (info["contextLength"] ?: contextSize),
                    "paramCount" to (info["paramCount"] ?: 0)
                )
                emitEvent(event)

                mainHandler.post { result.success(true) }
            } catch (e: Exception) {
                Log.e(TAG, "handleLoadModel error: ${e.message}", e)
                mainHandler.post {
                    result.error("LLAMA_ERROR", e.message, null)
                }
            }
        }
    }

    private fun handleReleaseModel(result: MethodChannel.Result) {
        val handle = modelHandle
        if (handle != 0L) {
            nativeReleaseModel(handle)
            modelHandle = 0L
            Log.i(TAG, "Model released")
        }
        result.success(null)
    }

    private fun handleIsModelLoaded(result: MethodChannel.Result) {
        val handle = modelHandle
        val ready = handle != 0L && nativeIsReady(handle)
        result.success(ready)
    }

    private fun handleGenerateTokens(call: MethodCall, result: MethodChannel.Result) {
        val handle = modelHandle
        if (handle == 0L) {
            result.error("LLAMA_ERROR", "Model is not loaded", null)
            return
        }
        val prompt        = call.argument<String>("prompt")         ?: ""
        val temperature   = (call.argument<Double>("temperature")   ?: 0.7).toFloat()
        val topP          = (call.argument<Double>("topP")          ?: 0.9).toFloat()
        val topK          = call.argument<Int>("topK")              ?: 40
        val maxTokens     = call.argument<Int>("maxTokens")         ?: 512
        val seq           = call.argument<Int>("seq")               ?: 0
        val repeatPenalty = (call.argument<Double>("repeatPenalty") ?: 1.1).toFloat()
        val seedRaw       = call.argument<Int>("seed")              ?: -1
        val seed          = if (seedRaw < 0) (System.currentTimeMillis() and 0xFFFFFFFFL).toInt() else seedRaw
        val mirostatMode  = call.argument<Int>("mirostatMode")      ?: 0
        val mirostatTau   = (call.argument<Double>("mirostatTau")   ?: 5.0).toFloat()
        val mirostatEta   = (call.argument<Double>("mirostatEta")   ?: 0.1).toFloat()
        val minP          = (call.argument<Double>("minP")          ?: 0.05).toFloat()
        val penalizeNl    = call.argument<Boolean>("penalizeNl")    ?: false

        // Return immediately to Dart — generation is async via EventChannel
        result.success(null)

        // Start foreground service
        LlamaGenerationService.start(context)

        genJob = pluginScope.launch {
            try {
                val ok = nativeGenerateTokens(
                    handle, prompt,
                    temperature, topP, topK, maxTokens,
                    seq, repeatPenalty, seed,
                    mirostatMode, mirostatTau, mirostatEta,
                    minP, penalizeNl
                )
                if (!ok) {
                    Log.w(TAG, "nativeGenerateTokens returned false seq=$seq")
                }
            } catch (e: Exception) {
                Log.e(TAG, "generateTokens error seq=$seq: ${e.message}", e)
                emitEvent(mapOf(
                    "type"    to "error",
                    "message" to (e.message ?: "unknown error"),
                    "seq"     to seq
                ))
                LlamaGenerationService.stop(context)
            }
        }
    }

    private fun handleStopGeneration(result: MethodChannel.Result) {
        val handle = modelHandle
        if (handle != 0L) {
            nativeStopGeneration(handle)
        }
        genJob?.cancel()
        LlamaGenerationService.stop(context)
        result.success(null)
    }

    private fun handleGetModelInfo(call: MethodCall, result: MethodChannel.Result) {
        // Support both Map argument {"path": "..."} and bare String argument "..."
        // LlamaService sends Map; legacy code might send a bare String.
        val path: String? = when (val args = call.arguments) {
            is String -> args
            is Map<*, *> -> args["path"] as? String
            else -> null
        }
        if (path.isNullOrBlank()) {
            result.error("LLAMA_ERROR", "path is required (String or Map{path:String})", null)
            return
        }
        pluginScope.launch {
            try {
                val json = nativeGetModelInfo(path)
                val infoMap = parseModelInfoJson(json)
                mainHandler.post { result.success(infoMap) }
            } catch (e: Exception) {
                Log.e(TAG, "getModelInfo error: ${e.message}", e)
                mainHandler.post { result.error("LLAMA_ERROR", e.message, null) }
            }
        }
    }

    private fun handleGetAvailableMemory(result: MethodChannel.Result) {
        var mb = nativeGetAvailableMemoryMb()
        if (mb <= 0) {
            // Fallback ke ActivityManager jika JNI return 0
            try {
                val am = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
                val memInfo = ActivityManager.MemoryInfo()
                am?.getMemoryInfo(memInfo)
                mb = (memInfo.availMem / (1024L * 1024L)).toInt()
            } catch (e: Exception) {
                Log.w(TAG, "ActivityManager fallback error: ${e.message}")
            }
        }
        result.success(mb)
    }

    private fun handleGetSystemInfo(result: MethodChannel.Result) {
        try {
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
            val memInfo = ActivityManager.MemoryInfo()
            am?.getMemoryInfo(memInfo)

            val totalRamMb    = memInfo.totalMem / (1024L * 1024L)
            val availRamMb    = nativeGetAvailableMemoryMb()
            val cpuCores      = Runtime.getRuntime().availableProcessors()
            val gpuAvailable  = false // No Vulkan compute check; can be extended

            result.success(mapOf(
                "totalRamMb"   to totalRamMb,
                "availableRamMb" to availRamMb,
                "cpuCores"     to cpuCores,
                "gpuAvailable" to gpuAvailable
            ))
        } catch (e: Exception) {
            Log.e(TAG, "getSystemInfo error: ${e.message}", e)
            result.error("LLAMA_ERROR", e.message, null)
        }
    }

    // ── ComponentCallbacks2 — memory pressure ─────────────────────────────────
    override fun onTrimMemory(level: Int) {
        // TRIM_MEMORY_CRITICAL (80) dihapus di compileSdk 36 — pakai nilai langsung
        if (level >= 80) {
            Log.w(TAG, "TRIM_MEMORY_CRITICAL (level=$level) — emitting memory_warning")
            emitEvent(mapOf(
                "type"        to "memory_warning",
                "availableMb" to nativeGetAvailableMemoryMb()
            ))
        }
    }

    override fun onConfigurationChanged(newConfig: android.content.res.Configuration) {}
    override fun onLowMemory() {
        Log.w(TAG, "onLowMemory()")
        emitEvent(mapOf(
            "type"        to "memory_warning",
            "availableMb" to nativeGetAvailableMemoryMb()
        ))
    }

    // ── Cleanup ───────────────────────────────────────────────────────────────
    fun destroy() {
        if (isDestroyed) return
        isDestroyed = true
        Log.i(TAG, "destroy()")
        genJob?.cancel()
        val handle = modelHandle
        if (handle != 0L) {
            nativeStopGeneration(handle)
            pluginScope.launch { nativeReleaseModel(handle) }
            modelHandle = 0L
        }
        LlamaGenerationService.stop(context)
        context.unregisterComponentCallbacks(this)
        synchronized(sinkLock) { eventSink = null }
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    /**
     * Parse minimal JSON returned by nativeGetModelInfo.
     * Format: {"name":"...","arch":"...","contextLength":4096,"paramCount":7000000000}
     * Uses manual parsing to avoid adding a JSON dependency.
     */
    private fun parseModelInfoJson(json: String): Map<String, Any> {
        val result = mutableMapOf<String, Any>()
        try {
            // name
            Regex("\"name\"\\s*:\\s*\"([^\"]+)\"").find(json)?.groupValues?.get(1)
                ?.let { result["name"] = it }
            // arch
            Regex("\"arch\"\\s*:\\s*\"([^\"]+)\"").find(json)?.groupValues?.get(1)
                ?.let { result["arch"] = it }
            // contextLength
            Regex("\"contextLength\"\\s*:\\s*(\\d+)").find(json)?.groupValues?.get(1)
                ?.toLongOrNull()?.let { result["contextLength"] = it }
            // paramCount
            Regex("\"paramCount\"\\s*:\\s*(\\d+)").find(json)?.groupValues?.get(1)
                ?.toLongOrNull()?.let { result["paramCount"] = it }
        } catch (e: Exception) {
            Log.w(TAG, "parseModelInfoJson error: ${e.message}")
        }
        return result
    }
}
