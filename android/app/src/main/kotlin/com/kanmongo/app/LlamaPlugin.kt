// LlamaPlugin.kt — KanMon GO (FIXED VERSION)
// SESI 6: Native Android Bridge — Full Refactor
// - New JNI API: nativeLoadModel with full params (context, gpu, batch, threads, flash, mlock, rope)
// - New native declarations aligned with llama_jni.cpp Sesi 6
// - EventChannel: structured events { type, ... } instead of flat token/done fields
// - ForegroundService for background generation
// - ComponentCallbacks2 memory pressure monitoring
// - Coroutine-based background execution
// - 🆕 FIXES: registerPlugin() call, file validation, memory check, detailed error logging
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
import java.io.File
import java.io.RandomAccessFile

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
// LlamaPlugin — main Flutter plugin bridge (FIXED)
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
        
        // 🆕 FIX: Call registerPlugin() immediately after loading library
        try {
            registerPlugin()
            Log.i(TAG, "✅ registerPlugin() called successfully in init")
        } catch (e: Exception) {
            Log.e(TAG, "❌ registerPlugin() failed in init: ${e.message}", e)
        }

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
                    "generateTokens",
                    "startGeneration"      -> handleGenerateTokens(call, result)
                    "stopGeneration"       -> handleStopGeneration(result)
                    "getModelInfo"         -> handleGetModelInfo(call, result)
                    "getAvailableMemoryMb" -> handleGetAvailableMemory(result)
                    "getSystemInfo"        -> handleGetSystemInfo(result)
                    else                   -> {
                        Log.w(TAG, "Unknown method: ${call.method}")
                        result.notImplemented()
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Method handler exception: ${e.message}", e)
                result.error("EXCEPTION", e.message, null)
            }
        }

        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, events: EventChannel.EventSink?) {
                synchronized(sinkLock) { eventSink = events }
                Log.i(TAG, "EventSink listener attached")
            }

            override fun onCancel(args: Any?) {
                synchronized(sinkLock) { eventSink = null }
                Log.i(TAG, "EventSink listener detached")
            }
        })
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 🆕 FIX: File validation utility
    // ─────────────────────────────────────────────────────────────────────────
    private fun validateModelFile(file: File): Pair<Boolean, String> {
        try {
            if (!file.exists()) {
                return Pair(false, "File not found: ${file.absolutePath}")
            }
            
            if (!file.canRead()) {
                return Pair(false, "No read permission: ${file.absolutePath}")
            }
            
            val sizeMb = file.length() / (1024 * 1024)
            if (file.length() == 0L) {
                return Pair(false, "File is empty (0 bytes)")
            }
            
            if (file.length() < 50 * 1024 * 1024) {
                Log.w(TAG, "validateModelFile: file seems small (${sizeMb}MB) - might not be a valid model")
            }
            
            // Check GGUF magic bytes
            try {
                val raf = RandomAccessFile(file, "r")
                val magic = ByteArray(4)
                val bytesRead = raf.read(magic)
                raf.close()
                
                if (bytesRead < 4) {
                    return Pair(false, "File too small to check GGUF magic")
                }
                
                val magicStr = magic.map { (it.toInt() and 0xFF).toChar() }.joinToString("")
                if (magicStr != "GGUF") {
                    return Pair(false, "Invalid GGUF magic bytes (got '$magicStr', expected 'GGUF')")
                }
            } catch (e: Exception) {
                Log.w(TAG, "validateModelFile: could not verify GGUF magic - ${e.message}")
                // Don't fail on this, might be permission issue
            }
            
            return Pair(true, "File valid - size=${sizeMb}MB")
        } catch (e: Exception) {
            return Pair(false, "Validation error: ${e.message}")
        }
    }

    // 🆕 FIX: Enhanced loadModel with full validation & error handling
    private fun handleLoadModel(call: MethodCall, result: MethodChannel.Result) {
        val modelPath = call.argument<String>("modelPath") ?: ""
        val contextSize = call.argument<Int>("contextSize") ?: 2048
        val gpuLayers = call.argument<Int>("gpuLayers") ?: 0
        val nBatch = call.argument<Int>("nBatch") ?: 512
        val nThreads = call.argument<Int>("nThreads") ?: 4
        val useFlashAttn = call.argument<Boolean>("useFlashAttn") ?: false
        val memLock = call.argument<Boolean>("memLock") ?: false
        val ropeBase = (call.argument<Double>("ropeBase") ?: 0.0).toFloat()
        val ropeScale = (call.argument<Double>("ropeScale") ?: 1.0).toFloat()

        // ─── STEP 1: Validate path ───────────────────────────────────────────
        if (modelPath.isBlank()) {
            Log.e(TAG, "loadModel: modelPath is empty")
            result.error("LLAMA_ERROR", "modelPath is required", null)
            return
        }

        // ─── STEP 2: Validate file exists & readable ─────────────────────────
        val modelFile = File(modelPath)
        val (isValid, validationMsg) = validateModelFile(modelFile)
        if (!isValid) {
            Log.e(TAG, "loadModel: file validation failed - $validationMsg")
            result.error("LLAMA_ERROR", validationMsg, null)
            return
        }
        
        Log.i(TAG, "loadModel: file validation passed - $validationMsg")

        // ─── STEP 3: Check available memory ─────────────────────────────────
        val availMb = nativeGetAvailableMemoryMb()
        val fileSizeMb = modelFile.length() / (1024 * 1024)
        val estimatedNeededMb = fileSizeMb + (contextSize * 2)
        
        Log.i(TAG, """
            loadModel: memory check
            - available: ${availMb}MB
            - model size: ${fileSizeMb}MB
            - estimated needed: ${estimatedNeededMb}MB
            - context: ${contextSize}
        """.trimIndent())
        
        if (availMb < estimatedNeededMb) {
            Log.w(TAG, "loadModel: memory warning - may not have enough RAM")
        }

        // ─── STEP 4: Stop any ongoing generation ────────────────────────────
        if (genJob != null && genJob!!.isActive) {
            Log.i(TAG, "loadModel: cancelling active generation job")
            genJob?.cancel()
        }

        // ─── STEP 5: Release previous model ─────────────────────────────────
        if (modelHandle != 0L) {
            Log.i(TAG, "loadModel: releasing previous model handle=$modelHandle")
            pluginScope.launch {
                try {
                    nativeReleaseModel(modelHandle)
                    Log.i(TAG, "loadModel: previous model released")
                } catch (e: Exception) {
                    Log.e(TAG, "loadModel: error releasing previous model - ${e.message}", e)
                }
            }
            // Give native layer time to cleanup
            try {
                Thread.sleep(300)
            } catch (e: InterruptedException) {
                Thread.currentThread().interrupt()
            }
        }

        // ─── STEP 6: Call native loading in coroutine ──────────────────────
        Log.i(TAG, "loadModel: launching native load coroutine")
        pluginScope.launch {
            try {
                Log.i(TAG, """
                    loadModel: calling nativeLoadModel with:
                    - path: $modelPath
                    - contextSize: $contextSize
                    - gpuLayers: $gpuLayers
                    - nBatch: $nBatch
                    - nThreads: $nThreads
                    - useFlashAttn: $useFlashAttn
                    - memLock: $memLock
                    - ropeBase: $ropeBase
                    - ropeScale: $ropeScale
                """.trimIndent())

                val handle = nativeLoadModel(
                    modelPath,
                    contextSize,
                    gpuLayers,
                    nBatch,
                    nThreads,
                    useFlashAttn,
                    memLock,
                    ropeBase,
                    ropeScale
                )

                // ─── STEP 7: Handle result ────────────────────────────────
                if (handle == 0L) {
                    Log.e(TAG, "❌ loadModel: nativeLoadModel returned 0 (FAILED)")
                    Log.e(TAG, "Check logcat with: adb logcat | grep -E 'LlamaJNI|LlamaPlugin'")
                    mainHandler.post {
                        result.error("LLAMA_ERROR",
                            "Native model loading failed (returned 0). Check device logcat for details.",
                            mapOf("path" to modelPath))
                    }
                } else {
                    Log.i(TAG, "✅ loadModel: SUCCESS handle=$handle")
                    synchronized(sinkLock) {
                        modelHandle = handle
                    }
                    mainHandler.post {
                        result.success(mapOf(
                            "handle" to handle,
                            "contextSize" to contextSize,
                            "path" to modelPath,
                            "fileSizeMb" to fileSizeMb
                        ))
                    }
                }

            } catch (e: Exception) {
                Log.e(TAG, "❌ loadModel: exception during native call - ${e.message}", e)
                mainHandler.post {
                    result.error("LLAMA_EXCEPTION", e.message, e.stackTrace.take(5).joinToString("\n"))
                }
            }
        }
    }

    private fun handleReleaseModel(result: MethodChannel.Result) {
        val handle = modelHandle
        if (handle == 0L) {
            result.success(null)
            return
        }
        genJob?.cancel()
        modelHandle = 0L
        pluginScope.launch {
            try {
                nativeReleaseModel(handle)
                Log.i(TAG, "Model released handle=$handle")
            } catch (e: Exception) {
                Log.e(TAG, "Error releasing model: ${e.message}", e)
            }
        }
        result.success(null)
    }

    private fun handleIsModelLoaded(result: MethodChannel.Result) {
        val isLoaded = modelHandle != 0L
        try {
            val ready = if (isLoaded) nativeIsReady(modelHandle) else false
            result.success(ready)
        } catch (e: Exception) {
            Log.w(TAG, "isModelLoaded check error: ${e.message}")
            result.success(false)
        }
    }

    private fun emitEvent(eventMap: Map<String, Any?>) {
        synchronized(sinkLock) {
            try {
                eventSink?.success(eventMap)
            } catch (e: Exception) {
                Log.w(TAG, "emitEvent error: ${e.message}")
            }
        }
    }

    fun emitEventFromNative(
        type: String,
        token: String,
        seq: Int,
        promptTokens: Int,
        evalTokens: Int,
        promptMs: Long,
        evalMs: Long,
        tokensPerSec: Double,
        errorMsg: String,
        availMb: Int
    ) {
        emitEvent(mapOf(
            "type" to type,
            "token" to token,
            "seq" to seq,
            "promptTokens" to promptTokens,
            "evalTokens" to evalTokens,
            "promptMs" to promptMs,
            "evalMs" to evalMs,
            "tokensPerSec" to tokensPerSec,
            "errorMsg" to errorMsg,
            "availMb" to availMb
        ))
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

        result.success(null)

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
            val gpuAvailable  = false

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

    override fun onTrimMemory(level: Int) {
        if (level >= 80) {
            Log.w(TAG, "TRIM_MEMORY_CRITICAL (level=$level)")
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

    private fun parseModelInfoJson(json: String): Map<String, Any> {
        val result = mutableMapOf<String, Any>()
        try {
            Regex("\"name\"\\s*:\\s*\"([^\"]+)\"").find(json)?.groupValues?.get(1)
                ?.let { result["name"] = it }
            Regex("\"arch\"\\s*:\\s*\"([^\"]+)\"").find(json)?.groupValues?.get(1)
                ?.let { result["arch"] = it }
            Regex("\"contextLength\"\\s*:\\s*(\\d+)").find(json)?.groupValues?.get(1)
                ?.toLongOrNull()?.let { result["contextLength"] = it }
            Regex("\"paramCount\"\\s*:\\s*(\\d+)").find(json)?.groupValues?.get(1)
                ?.toLongOrNull()?.let { result["paramCount"] = it }
        } catch (e: Exception) {
            Log.w(TAG, "parseModelInfoJson error: ${e.message}")
        }
        return result
    }
}
