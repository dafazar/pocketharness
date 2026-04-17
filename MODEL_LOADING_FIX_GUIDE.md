# KanMonAI - Model Loading Fix Guide
## "NativeLoadModel Returned 0 - model failed to load"

---

## 🔴 **MASALAH UTAMA**

Ketika Anda mencoba memuat model, notifikasi error muncul: `"NativeLoadModel Returned 0 - model failed to load"`

Ini berarti:
1. **Dart layer** memanggil `channel.invokeMethod('loadModel', ...)`
2. **Kotlin plugin** menerima dan memanggi `nativeLoadModel()` (C++)
3. **C++ JNI** mengembalikan `0L` (null) → artinya loading GAGAL
4. **Root causes** ada di path file, file permissions, corruption, atau memory issues

---

## 🎯 **ROOT CAUSES & SOLUTIONS**

### **Problem 1: registerPlugin() Tidak Dipanggil**
**Gejala:** Model loading timeout, no error message in logcat

**Penyebab:** `registerPlugin()` di LlamaPlugin.kt tidak dipanggil pada init. Tanpa ini, native callbacks tidak bisa kirim event ke Dart.

**Fix:**
```kotlin
// Di LlamaPlugin.kt, dalam init block:
init {
    context.registerComponentCallbacks(this)
    
    // ✅ TAMBAHKAN INI - CRITICAL!
    try {
        registerPlugin()
        Log.i(TAG, "registerPlugin() called successfully")
    } catch (e: Exception) {
        Log.e(TAG, "registerPlugin() failed: ${e.message}", e)
    }
    
    methodChannel.setMethodCallHandler { call, result -> ...
```

---

### **Problem 2: File Path Tidak Valid**
**Gejala:** "llama_model_load_from_file failed" di logcat

**Penyebab:** Path file model tidak ada, permission denied, atau format path salah untuk Android.

**Checklist:**
```kotlin
// Di handleLoadModel di LlamaPlugin.kt - tambahkan validasi:
private fun handleLoadModel(call: MethodCall, result: MethodChannel.Result) {
    val modelPath = call.argument<String>("modelPath") ?: ""
    
    // ✅ VALIDASI PATH LENGKAP
    if (modelPath.isBlank()) {
        Log.e(TAG, "loadModel: modelPath is empty")
        result.error("LLAMA_ERROR", "modelPath is required", null)
        return
    }
    
    val modelFile = File(modelPath)
    if (!modelFile.exists()) {
        Log.e(TAG, "loadModel: file not found at $modelPath")
        result.error("LLAMA_ERROR", "Model file not found: $modelPath", null)
        return
    }
    
    if (!modelFile.canRead()) {
        Log.e(TAG, "loadModel: no read permission for $modelPath")
        result.error("LLAMA_ERROR", "No read permission: $modelPath", null)
        return
    }
    
    if (modelFile.length() == 0L) {
        Log.e(TAG, "loadModel: file is empty (0 bytes)")
        result.error("LLAMA_ERROR", "Model file is empty", null)
        return
    }
    
    Log.i(TAG, "loadModel: path=$modelPath size=${modelFile.length()} bytes")
    
    // ... proceed dengan loading
}
```

---

### **Problem 3: mmap=true Cause SIGBUS (Android Storage)**
**Gejala:** Native crash, silent failure di internal storage

**Penyebab:** Android internal storage tidak support mmap reliably. Sudah di-set `use_mmap = false` di llama_jni.cpp, tapi perlu double-check.

**Fix di llama_jni.cpp:**
```cpp
// Line ~305 dalam nativeLoadModel
auto mparams = llama_model_default_params();
mparams.n_gpu_layers = (int)gpuLayers;
mparams.use_mlock    = (bool)memLock;
mparams.use_mmap     = false;  // ✅ CRITICAL FIX - Android storage bug workaround

LOGI("nativeLoadModel: mparams setup done - mmap=%d mlock=%d", 
     mparams.use_mmap, mparams.use_mlock);
```

---

### **Problem 4: Memory Allocation Failure**
**Gejala:** "llama_new_context_with_model failed" di logcat, atau return value 0

**Penyebab:**
- Batch size terlalu besar
- Context size tidak cocok dengan available RAM
- GPU layer allocation error

**Fix di handleLoadModel:**
```kotlin
// BEFORE loading - check memory
private fun handleLoadModel(call: MethodCall, result: MethodChannel.Result) {
    val modelPath = call.argument<String>("modelPath") ?: ""
    val contextSize = call.argument<Int>("contextSize") ?: 2048
    val gpuLayers = call.argument<Int>("gpuLayers") ?: 0
    val nBatch = call.argument<Int>("nBatch") ?: 512
    
    // ✅ CHECK AVAILABLE MEMORY BEFORE LOADING
    val availMb = nativeGetAvailableMemoryMb()
    Log.i(TAG, "loadModel: available RAM = $availMb MB")
    
    // Rough estimate: model_size + (context_size * 2) MB
    val estimatedNeededMb = (modelFile.length() / (1024 * 1024)) + (contextSize * 2)
    if (availMb < estimatedNeededMb) {
        Log.e(TAG, "loadModel: insufficient memory. need ~$estimatedNeededMb MB, have $availMb MB")
        result.error("LLAMA_ERROR", 
            "Insufficient memory: need ~${estimatedNeededMb}MB, have ${availMb}MB", null)
        return
    }
    
    // ✅ CLAMP BATCH SIZE to available memory
    val clampedBatch = minOf(nBatch, availMb / 2)  // conservative estimate
    Log.i(TAG, "loadModel: clamping nBatch $nBatch → $clampedBatch for safety")
    
    // Proceed dengan native call
    pluginScope.launch {
        val handle = nativeLoadModel(
            modelPath,
            contextSize,
            gpuLayers,
            clampedBatch,  // ✅ use clamped value
            nThreads,
            useFlashAttn,
            memLock,
            ropeBase,
            ropeScale
        )
        
        if (handle == 0L) {
            Log.e(TAG, "loadModel: nativeLoadModel returned 0 (failed)")
            mainHandler.post {
                result.error("LLAMA_ERROR", "Native model loading failed (returned 0)", null)
            }
        } else {
            Log.i(TAG, "loadModel: success handle=$handle")
            modelHandle = handle
            mainHandler.post { result.success(mapOf("handle" to handle)) }
        }
    }
}
```

---

### **Problem 5: Model File Corruption**
**Gejala:** Model load fails immediately, might be corrupted during import

**Fix - Add integrity check:**
```kotlin
// Utility function untuk validate model file
private fun validateModelFile(file: File): Boolean {
    try {
        if (!file.exists()) {
            Log.e(TAG, "validateModelFile: file not found")
            return false
        }
        
        if (file.length() < 100 * 1024 * 1024) {  // minimum ~100MB untuk model 7B
            Log.e(TAG, "validateModelFile: file too small (${file.length()} bytes)")
            return false
        }
        
        // Check GGUF magic bytes
        val raf = RandomAccessFile(file, "r")
        val magic = ByteArray(4)
        raf.read(magic)
        raf.close()
        
        val magicStr = magic.map { (it.toInt() and 0xFF).toChar() }.joinToString("")
        if (magicStr != "GGUF") {
            Log.e(TAG, "validateModelFile: invalid GGUF magic (got '$magicStr')")
            return false
        }
        
        Log.i(TAG, "validateModelFile: OK - file is valid GGUF")
        return true
    } catch (e: Exception) {
        Log.e(TAG, "validateModelFile: error - ${e.message}")
        return false
    }
}

// Panggil sebelum loading:
if (!validateModelFile(modelFile)) {
    result.error("LLAMA_ERROR", "Model file validation failed (corrupted?)", null)
    return
}
```

---

### **Problem 6: Thread Safety Issues**
**Gejala:** Race condition, crash saat loading + generate bersamaan

**Fix di LlamaPlugin.kt:**
```kotlin
private fun handleLoadModel(call: MethodCall, result: MethodChannel.Result) {
    // ✅ STOP any ongoing generation FIRST
    if (genJob != null && genJob!!.isActive) {
        Log.i(TAG, "loadModel: cancelling active generation job")
        genJob?.cancel()
    }
    
    // ✅ RELEASE previous model under mutex
    if (modelHandle != 0L) {
        Log.i(TAG, "loadModel: releasing previous model handle=$modelHandle")
        pluginScope.launch {
            nativeReleaseModel(modelHandle)
            modelHandle = 0L
        }
        // Wait a bit for native cleanup
        Thread.sleep(500)
    }
    
    // NOW load new model
    pluginScope.launch {
        synchronized(sinkLock) {
            // Load under lock to prevent concurrent access
            val handle = nativeLoadModel(...)
            modelHandle = handle
        }
    }
}
```

---

### **Problem 7: Dart Flutter Not Handling Response**
**Gejala:** loadModel() memanggil native tapi Dart tidak menerima hasil

**Fix di Dart:**
```dart
// Di model_manager.dart atau llama_service.dart
Future<void> loadModel(String modelPath) async {
    try {
        Log.i('[LlamaService] loadModel: $modelPath');
        
        // ✅ Ensure the file actually exists
        final file = File(modelPath);
        if (!await file.exists()) {
            throw Exception('Model file not found: $modelPath');
        }
        
        Log.i('[LlamaService] file exists, size: ${await file.length()} bytes');
        
        // ✅ Call native with proper error handling
        final result = await _methodChannel.invokeMethod<Map>('loadModel', {
            'modelPath': modelPath,
            'contextSize': 2048,
            'gpuLayers': 0,
            'nBatch': 512,
            'nThreads': 4,
            'useFlashAttn': false,
            'memLock': false,
            'ropeBase': 0.0,
            'ropeScale': 1.0,
        });
        
        if (result == null) {
            throw Exception('loadModel returned null');
        }
        
        final handle = result['handle'] as int?;
        if (handle == null || handle == 0) {
            throw Exception('loadModel returned invalid handle: $handle');
        }
        
        Log.i('[LlamaService] ✅ model loaded successfully handle=$handle');
        _modelLoaded = true;
        notifyListeners();
        
    } on PlatformException catch (e) {
        Log.e('[LlamaService] loadModel error: ${e.code} - ${e.message}');
        _modelLoaded = false;
        notifyListeners();
        rethrow;
    } catch (e) {
        Log.e('[LlamaService] loadModel unexpected error: $e');
        _modelLoaded = false;
        notifyListeners();
        rethrow;
    }
}
```

---

## 📋 **CHECKLIST DEBUGGING**

Jalankan ini step by step:

### **1. Check Logcat untuk Native Errors**
```bash
adb logcat | grep -E "LlamaJNI|LlamaPlugin"
```

**Cari pattern:**
- `nativeLoadModel: llama_model_load_from_file failed` → File path issue
- `nativeLoadModel: llama_new_context_with_model failed` → Memory issue
- `registerPlugin: cannot find emitEventFromNative` → Missing method signature
- `SIGBUS` atau `SIGSEGV` → Native crash (mmap issue, memory access)

### **2. Verify Model File Path & Size**
```kotlin
// Tambahkan di handleLoadModel:
val modelFile = File(modelPath)
Log.i(TAG, """
    Model file check:
    - Path: $modelPath
    - Exists: ${modelFile.exists()}
    - Readable: ${modelFile.canRead()}
    - Size: ${modelFile.length()} bytes
    - Absolute: ${modelFile.absolutePath}
""".trimIndent())
```

### **3. Check Memory Availability**
```kotlin
val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
val memInfo = ActivityManager.MemoryInfo()
am.getMemoryInfo(memInfo)
Log.i(TAG, "System RAM: total=${memInfo.totalMem / (1024*1024)}MB, avail=${memInfo.availMem / (1024*1024)}MB")
```

### **4. Verify registerPlugin Called**
```kotlin
// Di init block:
try {
    registerPlugin()
    Log.i(TAG, "✅ registerPlugin() called")
} catch (e: Exception) {
    Log.e(TAG, "❌ registerPlugin() failed: ${e.message}", e)
}
```

### **5. Check File Integrity**
```bash
# On device:
adb shell file /path/to/model.gguf
adb shell head -c 4 /path/to/model.gguf | od -c  # Should show "GGUF"
```

---

## 🔧 **RECOMMENDED FIX ORDER**

1. **✅ Add registerPlugin() call in init**
2. **✅ Add file path validation in handleLoadModel**
3. **✅ Add memory check before native call**
4. **✅ Check logcat for specific error message**
5. **✅ Rebuild APK dan test ulang**
6. **✅ If still fails, check model file integrity**

---

## 📝 **COMPLETE WORKING CODE - handleLoadModel()**

```kotlin
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
    
    // ─────────────────────────────────────────────────────────────
    // STEP 1: Validate path
    // ─────────────────────────────────────────────────────────────
    if (modelPath.isBlank()) {
        Log.e(TAG, "loadModel: modelPath is empty")
        result.error("LLAMA_ERROR", "modelPath is required", null)
        return
    }
    
    val modelFile = File(modelPath)
    if (!modelFile.exists()) {
        Log.e(TAG, "loadModel: file not found at $modelPath")
        result.error("LLAMA_ERROR", "Model file not found: $modelPath", null)
        return
    }
    
    if (!modelFile.canRead()) {
        Log.e(TAG, "loadModel: no read permission for $modelPath")
        result.error("LLAMA_ERROR", "No read permission: $modelPath", null)
        return
    }
    
    val fileSizeMb = modelFile.length() / (1024 * 1024)
    if (modelFile.length() < 100 * 1024 * 1024) {
        Log.w(TAG, "loadModel: file seems too small (${fileSizeMb}MB) - might not be valid")
    }
    
    Log.i(TAG, """
        loadModel: validated
        - path: $modelPath
        - size: ${fileSizeMb}MB
        - ctx: $contextSize
        - gpu: $gpuLayers
        - batch: $nBatch
        - threads: $nThreads
    """.trimIndent())
    
    // ─────────────────────────────────────────────────────────────
    // STEP 2: Check memory
    // ─────────────────────────────────────────────────────────────
    val availMb = nativeGetAvailableMemoryMb()
    Log.i(TAG, "loadModel: available RAM = $availMb MB")
    
    val estimatedNeededMb = fileSizeMb + (contextSize * 2)
    if (availMb < estimatedNeededMb) {
        Log.w(TAG, "loadModel: low memory warning - need ~${estimatedNeededMb}MB, have ${availMb}MB")
    }
    
    // ─────────────────────────────────────────────────────────────
    // STEP 3: Stop any existing generation
    // ─────────────────────────────────────────────────────────────
    if (genJob != null && genJob!!.isActive) {
        Log.i(TAG, "loadModel: cancelling active generation")
        genJob?.cancel()
    }
    
    // ─────────────────────────────────────────────────────────────
    // STEP 4: Release previous model
    // ─────────────────────────────────────────────────────────────
    if (modelHandle != 0L) {
        Log.i(TAG, "loadModel: releasing previous model handle=$modelHandle")
        pluginScope.launch {
            try {
                nativeReleaseModel(modelHandle)
            } catch (e: Exception) {
                Log.e(TAG, "loadModel: error releasing previous model - ${e.message}")
            }
            modelHandle = 0L
        }
        // Give native layer time to cleanup
        try {
            Thread.sleep(300)
        } catch (e: InterruptedException) {
            Thread.currentThread().interrupt()
        }
    }
    
    // ─────────────────────────────────────────────────────────────
    // STEP 5: Call native loading in coroutine
    // ─────────────────────────────────────────────────────────────
    pluginScope.launch {
        try {
            Log.i(TAG, "loadModel: calling nativeLoadModel...")
            
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
            
            // ─────────────────────────────────────────────────────
            // STEP 6: Handle result
            // ─────────────────────────────────────────────────────
            if (handle == 0L) {
                Log.e(TAG, "loadModel: nativeLoadModel returned 0 (FAILED)")
                mainHandler.post {
                    result.error("LLAMA_ERROR", 
                        "Native model loading failed - check logcat for details", null)
                }
            } else {
                Log.i(TAG, "loadModel: ✅ SUCCESS handle=$handle")
                synchronized(sinkLock) {
                    modelHandle = handle
                }
                mainHandler.post {
                    result.success(mapOf(
                        "handle" to handle,
                        "contextSize" to contextSize
                    ))
                }
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "loadModel: exception - ${e.message}", e)
            mainHandler.post {
                result.error("LLAMA_ERROR", e.message, null)
            }
        }
    }
}
```

---

## 🚀 **TESTING AFTER FIX**

1. **Clear cache:** `adb shell pm clear com.kanmongo.app`
2. **Rebuild:** `flutter clean && flutter pub get && flutter run`
3. **Check logcat:** `adb logcat | grep -E "LlamaJNI|LlamaPlugin|loadModel"`
4. **Try loading model** dari app
5. **Verify log messages:**
   - ✅ `registerPlugin() called successfully`
   - ✅ `loadModel: validated`
   - ✅ `nativeLoadModel: model loaded OK`
   - ✅ `loadModel: ✅ SUCCESS handle=...`

---

## 💡 **Additional Notes**

- Model harus dalam format **GGUF** (GGML Universal Format)
- Minimum size untuk model 7B ~4-7GB
- GPU layers hanya efektif jika ada Vulkan compute support (rare di Android)
- Pastikan device punya minimal 2GB RAM available saat loading
- Use **small models** (3B-7B) untuk produksi Android

