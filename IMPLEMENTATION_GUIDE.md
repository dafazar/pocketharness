# KanMonAI - QUICK IMPLEMENTATION GUIDE
## Fix "NativeLoadModel Returned 0" Error

---

## 🎯 RINGKASAN MASALAH

Ketika menekan tombol "Muat" model, muncul notifikasi error:
```
"NativeLoadModel Returned 0 - model failed to load"
```

**Root Causes:**
1. ❌ `registerPlugin()` tidak dipanggil di Kotlin init
2. ❌ File path tidak valid / file tidak ada
3. ❌ `use_mmap=true` di Android storage → SIGBUS crash
4. ❌ Memory allocation failure
5. ❌ Corrupted model file
6. ❌ Thread safety issues
7. ❌ Dart tidak handle response dengan benar

---

## ✅ SOLUSI - IMPLEMENT CHANGES

### **FILE 1: LlamaPlugin.kt** 
**Lokasi:** `android/app/src/main/kotlin/com/kanmongo/app/LlamaPlugin.kt`

**Changes Required:**

#### Step A: Add registerPlugin() in init (CRITICAL!)
```kotlin
init {
    context.registerComponentCallbacks(this)
    
    // 🆕 ADD THIS - CRITICAL FIX!
    try {
        registerPlugin()
        Log.i(TAG, "✅ registerPlugin() called successfully")
    } catch (e: Exception) {
        Log.e(TAG, "❌ registerPlugin() failed: ${e.message}", e)
    }
    
    methodChannel.setMethodCallHandler { call, result -> ...
```

#### Step B: Add file validation utility
```kotlin
// Add this new function in LlamaPlugin class
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
                return Pair(false, "Invalid GGUF magic bytes (got '$magicStr')")
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not verify GGUF magic - ${e.message}")
        }
        
        return Pair(true, "File valid - size=${sizeMb}MB")
    } catch (e: Exception) {
        return Pair(false, "Validation error: ${e.message}")
    }
}
```

#### Step C: Replace entire handleLoadModel() function
See file: `LlamaPlugin_FIXED.kt` - copy entire `handleLoadModel()` function

#### Step D: Import statements
```kotlin
import java.io.File
import java.io.RandomAccessFile
```

**Checklist:**
- [ ] Add registerPlugin() call in init
- [ ] Add validateModelFile() function
- [ ] Replace handleLoadModel() with fixed version
- [ ] Add import statements

---

### **FILE 2: llama_jni.cpp**
**Lokasi:** `android/app/src/main/cpp/llama_jni.cpp`

**Critical Changes:**

#### Step A: Fix nativeLoadModel function (CRITICAL!)
Replace entire `nativeLoadModel` function body with:
See file: `llama_jni_CRITICAL_FIXES.cpp` - copy entire function

**Key fixes:**
- ✅ Path validation before loading
- ✅ File magic bytes check (GGUF)
- ✅ `use_mmap = false` (Android SIGBUS fix)
- ✅ Error logging untuk debugging

#### Step B: Improve JNI_OnLoad initialization
See file: `llama_jni_CRITICAL_FIXES.cpp` - enhanced logging

#### Step C: Keep existing functions unchanged
- `nativeReleaseModel()`
- `nativeGenerateTokens()`
- Other functions stay as-is

**Checklist:**
- [ ] Replace nativeLoadModel() function
- [ ] Verify use_mmap = false
- [ ] Keep other functions intact

---

### **FILE 3: Dart Model Loading**
**Lokasi:** `lib/services/llama_service.dart` atau `lib/model_manager.dart`

Replace atau enhance function dengan: `llama_service_FIXED.dart`

**Key improvements:**
- ✅ File validation in Dart before calling native
- ✅ Proper error handling dan error messages
- ✅ Memory checks
- ✅ GGUF magic verification
- ✅ Diagnostic function
- ✅ Event stream listening

**Checklist:**
- [ ] Add loadModel() with validation
- [ ] Add generateTokens() with event listening
- [ ] Add diagnosticCheck() function
- [ ] Update error messages

---

## 🔧 IMPLEMENTATION CHECKLIST

### Phase 1: Quick Fixes (10 minutes)
- [ ] **Kotlin:** Add `registerPlugin()` call in init
- [ ] **C++:** Change `use_mmap = true` → `use_mmap = false`
- [ ] **Rebuild:** `flutter clean && flutter pub get && flutter run`

### Phase 2: File Validation (20 minutes)
- [ ] **Kotlin:** Add `validateModelFile()` function
- [ ] **Kotlin:** Call validation in `handleLoadModel()`
- [ ] **C++:** Add path + file validation in `nativeLoadModel()`
- [ ] **Rebuild and test**

### Phase 3: Error Handling (30 minutes)
- [ ] **Replace entire handleLoadModel()** with fixed version
- [ ] **Replace Dart loadModel()** with fixed version
- [ ] **Add diagnostic check** function
- [ ] **Rebuild and test**

---

## 🧪 TESTING STEPS

### 1. Build & Clean
```bash
cd /path/to/kanmonai
flutter clean
flutter pub get
flutter run -v
```

### 2. Monitor Logcat
```bash
adb logcat | grep -E "LlamaJNI|LlamaPlugin|loadModel"
```

### 3. Check for Success Messages
Look for:
- ✅ `registerPlugin() called successfully`
- ✅ `loadModel: file validation passed`
- ✅ `nativeLoadModel: model loaded OK`
- ✅ `loadModel: ✅ SUCCESS`

### 4. Expected Error Messages (if file wrong)
- ❌ `File not found: /path/to/model.gguf`
- ❌ `Invalid GGUF magic bytes`
- ❌ `File is empty`

### 5. If Still Fails
```bash
# Get full logcat
adb logcat > logcat.txt

# Check logcat.txt for pattern: "LlamaJNI" atau "nativeLoadModel"
grep -i "llama\|native" logcat.txt
```

---

## 🐛 DEBUGGING COMMANDS

### See native logs
```bash
adb logcat | grep "LlamaJNI"
```

### See Kotlin logs
```bash
adb logcat | grep "LlamaPlugin"
```

### See both
```bash
adb logcat | grep -E "LlamaJNI|LlamaPlugin"
```

### Full Dart/Flutter logs
```bash
adb logcat | grep "flutter"
```

### Check if model file exists on device
```bash
adb shell ls -lh /path/to/model.gguf
```

### Check GGUF magic bytes
```bash
adb shell head -c 4 /path/to/model.gguf | od -c
# Should output: G G U F
```

---

## 📊 EXPECTED LOGCAT OUTPUT (Success Case)

```
I/LlamaJNI: nativeLoadModel: START
I/LlamaJNI: path=/data/data/com.kanmongo.app/models/model.gguf
I/LlamaJNI: file opened, size=6200000000 bytes (5912.3 MB)
I/LlamaJNI: GGUF magic verified ✓
I/LlamaJNI: model params - gpu_layers=0 mlock=0 mmap=0
I/LlamaJNI: calling llama_model_load_from_file...
I/LlamaJNI: ✓ nativeLoadModel: model loaded OK
I/LlamaJNI: context params - n_ctx=2048 n_batch=512 n_threads=4
I/LlamaJNI: calling llama_new_context_with_model...
I/LlamaJNI: ✓ nativeLoadModel: context ready
I/LlamaJNI: ✅ nativeLoadModel: SUCCESS - handle=0x123456789
I/LlamaPlugin: ✅ loadModel: nativeLoadModel returned success
```

---

## 📊 EXPECTED LOGCAT OUTPUT (Failure Case with Diagnosis)

```
I/LlamaJNI: nativeLoadModel: START
I/LlamaJNI: path=/data/data/com.kanmongo.app/models/nonexistent.gguf
I/LlamaJNI: cannot open file - errno=2 (No such file or directory)
I/LlamaJNI: ❌ nativeLoadModel: llama_model_load_from_file FAILED

I/LlamaPlugin: ❌ loadModel: nativeLoadModel returned 0 (FAILED)
E/LlamaPlugin: Check logcat with: adb logcat | grep -E 'LlamaJNI|LlamaPlugin'
```

---

## 🚀 COMMON ISSUES & SOLUTIONS

| Issue | Cause | Solution |
|-------|-------|----------|
| `returned 0` immediately | `registerPlugin()` not called | Add call in init block |
| `SIGBUS` crash | `use_mmap=true` on Android storage | Set to `false` |
| `file not found` | Wrong path or file doesn't exist | Check adb shell ls |
| `insufficient memory` | Not enough RAM | Close apps, use smaller model |
| `Invalid GGUF magic` | Corrupted file or wrong format | Redownload model |
| No event in Dart | `registerPlugin()` failed | Check Kotlin logcat |
| Dart loadModel() hangs | Native not returning | Check C++ nativeLoadModel |

---

## 💡 PRO TIPS

### Tip 1: Test model file validity before loading
```bash
adb shell file /path/to/model.gguf
# Should output: "data" or binary file info
```

### Tip 2: Monitor memory during loading
```bash
adb shell "cat /proc/meminfo | grep MemAvailable"
# Should be > 2000000 kB for 7B model
```

### Tip 3: Use smaller models for testing
- **Smallest:** TinyLlama (1B params) - works on old phones
- **Recommended:** Phi-2 (2.7B) - best performance/size ratio  
- **Production:** Llama 2 7B - good quality

### Tip 4: Enable verbose logging in Dart
```dart
// Add at app startup
if (kDebugMode) {
  print('DEBUG: Model service initialized');
}
```

---

## 📝 FILE SUMMARY

| File | Purpose | Status |
|------|---------|--------|
| `LlamaPlugin_FIXED.kt` | Kotlin plugin with full fixes | ✅ Ready |
| `llama_jni_CRITICAL_FIXES.cpp` | C++ JNI critical fixes | ✅ Ready |
| `llama_service_FIXED.dart` | Dart service with error handling | ✅ Ready |
| `MODEL_LOADING_FIX_GUIDE.md` | Detailed guide | ✅ Ready |

---

## 🎓 LEARNING RESOURCES

### Android JNI
- [Android NDK - JNI Basics](https://developer.android.com/training/articles/on-device-debugging)
- [JNI Error Handling](https://docs.oracle.com/javase/8/docs/technotes/guides/jni/spec/design.html)

### Kotlin Plugin Development
- [Flutter Kotlin Plugin Guide](https://flutter.dev/docs/development/platform-integration/platform-channels)
- [Android Memory Management](https://developer.android.com/training/articles/memory)

### GGUF Format
- [GGUF Specification](https://github.com/ggerganov/ggml/blob/master/docs/gguf.md)

---

## 📞 SUPPORT

**If error persists after all fixes:**

1. Check logcat for specific error:
   ```bash
   adb logcat | grep -i "error\|failed\|exception" | head -20
   ```

2. Collect full logs:
   ```bash
   adb logcat > full_logs.txt
   # Try loading model
   # Stop with Ctrl+C
   ```

3. Share logs + model info:
   - Full logcat output
   - Model file name and size
   - Device specs (RAM, Android version, CPU)
   - Which step the error occurs

---

## ✨ FINAL CHECKLIST

Before declaring "DONE":

- [ ] registerPlugin() called in Kotlin init
- [ ] use_mmap=false in C++ nativeLoadModel
- [ ] File validation in both Kotlin and Dart
- [ ] Error handling with meaningful messages
- [ ] All 3 files updated (Kotlin, C++, Dart)
- [ ] Rebuilt apk with `flutter run`
- [ ] Tested with valid model file
- [ ] Logcat shows SUCCESS messages
- [ ] Model actually loads and can generate text

**Once all checks pass, your KanMonAI should work perfectly! 🎉**

