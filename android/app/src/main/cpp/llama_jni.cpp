// llama_jni.cpp — KEY FIXES untuk NativeLoadModel Returned 0
// 
// MASALAH & SOLUSI:
// 1. use_mmap=true di Android internal storage → SIGBUS/crash → FIX: set false
// 2. Path tidak valid / file tidak ada → llama_model_load_from_file returns nullptr → FIX: add validation
// 3. Context creation fails → llama_new_context_with_model returns nullptr → FIX: add error logging
// 4. Memory allocation failure → context params terlalu besar → FIX: graceful error handling

// ═════════════════════════════════════════════════════════════════════════════
// 🔴 CRITICAL FIX: nativeLoadModel function
// ═════════════════════════════════════════════════════════════════════════════

extern "C" JNIEXPORT jlong JNICALL
Java_com_kanmongo_app_LlamaPlugin_nativeLoadModel(
    JNIEnv* env, jobject thiz,
    jstring jPath, jint contextSize, jint gpuLayers,
    jint nBatch, jint nThreads, jboolean useFlashAttn,
    jboolean memLock, jfloat ropeBase, jfloat ropeScale)
{
    // Convert path
    const char* rawPath = env->GetStringUTFChars(jPath, nullptr);
    std::string path(rawPath);
    env->ReleaseStringUTFChars(jPath, rawPath);

    LOGI("nativeLoadModel: START");
    LOGI("  path=%s", path.c_str());
    LOGI("  ctx=%d gpu=%d batch=%d threads=%d flash=%d mlock=%d rope=%.2f/%.2f",
         (int)contextSize, (int)gpuLayers,
         (int)nBatch, (int)nThreads, (int)useFlashAttn,
         (int)memLock, (float)ropeBase, (float)ropeScale);

    // 🆕 FIX: Validate path before loading
    if (path.empty()) {
        LOGE("nativeLoadModel: path is empty!");
        return 0L;
    }
    
    FILE* test_file = fopen(path.c_str(), "rb");
    if (!test_file) {
        LOGE("nativeLoadModel: cannot open file - errno=%d (%s)", errno, strerror(errno));
        return 0L;
    }
    
    // Check file size
    fseek(test_file, 0, SEEK_END);
    long file_size = ftell(test_file);
    fseek(test_file, 0, SEEK_SET);
    
    LOGI("nativeLoadModel: file opened, size=%ld bytes (%.1f MB)", 
         file_size, file_size / (1024.0 * 1024.0));
    
    if (file_size < 1024 * 1024) {  // Less than 1MB
        LOGE("nativeLoadModel: file too small (%ld bytes)", file_size);
        fclose(test_file);
        return 0L;
    }
    
    // Check GGUF magic
    unsigned char magic[4];
    size_t read = fread(magic, 1, 4, test_file);
    fclose(test_file);
    
    if (read != 4 || magic[0] != 'G' || magic[1] != 'G' || magic[2] != 'U' || magic[3] != 'F') {
        LOGE("nativeLoadModel: invalid GGUF magic (got %02x%02x%02x%02x, expected 47474655)",
             magic[0], magic[1], magic[2], magic[3]);
        return 0L;
    }
    
    LOGI("nativeLoadModel: GGUF magic verified ✓");

    std::lock_guard<std::mutex> lk(g_state.modelMutex);

    // Clear any existing model
    if (g_state.isLoaded()) {
        LOGI("nativeLoadModel: releasing previous model");
        g_state.shouldStop = true;
        g_state.clear();
        g_state.shouldStop = false;
    }

    // 🆕 FIX: Model params with proper Android storage settings
    auto mparams = llama_model_default_params();
    mparams.n_gpu_layers = (int)gpuLayers;
    mparams.use_mlock    = (bool)memLock;
    mparams.use_mmap     = false;  // 🔥 CRITICAL: mmap=true causes SIGBUS on Android internal storage!

    LOGI("nativeLoadModel: model params - gpu_layers=%d mlock=%d mmap=%d",
         mparams.n_gpu_layers, mparams.use_mlock, mparams.use_mmap);

    // Emit initial loading progress
    {
        bool nd = false;
        JNIEnv* cbEnv = jni_attach(nd);
        if (cbEnv) {
            emit_to_kotlin(cbEnv, "loading_progress", "", 0, 0, 0, 0, 0, 0.0, "", 0);
            if (nd) g_jvm->DetachCurrentThread();
        }
    }

    // 🆕 FIX: Load model with explicit error checking
    LOGI("nativeLoadModel: calling llama_model_load_from_file...");
    g_state.model = llama_model_load_from_file(path.c_str(), mparams);
    
    if (!g_state.model) {
        LOGE("❌ nativeLoadModel: llama_model_load_from_file FAILED - returned nullptr");
        LOGE("    Possible causes:");
        LOGE("    1. File path invalid or file doesn't exist");
        LOGE("    2. File corrupted or not a valid GGUF model");
        LOGE("    3. Insufficient memory");
        LOGE("    4. Model architecture not supported by this llama.cpp version");
        return 0L;
    }
    
    LOGI("✓ nativeLoadModel: model loaded OK");
    
    // 🆕 FIX: Log model info
    char model_name[256] = "unknown";
    llama_model_meta_val_str(g_state.model, "general.name", model_name, sizeof(model_name));
    int model_ctx = (int)llama_model_n_ctx_train(g_state.model);
    LOGI("  model name: %s", model_name);
    LOGI("  model context size: %d", model_ctx);

    // Context params with clamping
    auto cparams = llama_context_default_params();
    cparams.n_ctx      = (uint32_t)contextSize;
    cparams.n_batch    = (uint32_t)nBatch;
    cparams.n_threads  = (nThreads > 0) ? (uint32_t)nThreads : (uint32_t)optimal_threads();
    
    // Clamp context to model's max
    if (cparams.n_ctx > (uint32_t)model_ctx) {
        LOGW("nativeLoadModel: clamping context %d → %d (model max)", 
             (int)cparams.n_ctx, model_ctx);
        cparams.n_ctx = (uint32_t)model_ctx;
    }
    
    if (ropeBase  > 0.0f) cparams.rope_freq_base  = ropeBase;
    if (ropeScale > 0.0f) cparams.rope_freq_scale = ropeScale;

    LOGI("nativeLoadModel: context params - n_ctx=%d n_batch=%d n_threads=%d",
         (int)cparams.n_ctx, (int)cparams.n_batch, (int)cparams.n_threads);

    // 🆕 FIX: Create context with explicit error handling
    LOGI("nativeLoadModel: calling llama_new_context_with_model...");
    g_state.ctx = llama_new_context_with_model(g_state.model, cparams);
    
    if (!g_state.ctx) {
        LOGE("❌ nativeLoadModel: llama_new_context_with_model FAILED - returned nullptr");
        LOGE("    Possible causes:");
        LOGE("    1. Insufficient memory for context (need ~%d MB)", 
             (int)((contextSize * 2) / 1024));
        LOGE("    2. Context size (%d) exceeds model max (%d)", contextSize, model_ctx);
        LOGE("    3. Batch size (%d) too large", (int)nBatch);
        
        llama_model_free(g_state.model);
        g_state.model = nullptr;
        return 0L;
    }

    LOGI("✓ nativeLoadModel: context ready ctx=%d threads=%d batch=%d",
         (int)contextSize, (int)cparams.n_threads, (int)cparams.n_batch);

    // Create sampler
    g_state.sampler = llama_sampler_chain_init(llama_sampler_chain_default_params());
    if (!g_state.sampler) {
        LOGE("❌ nativeLoadModel: sampler creation failed");
        llama_free(g_state.ctx);
        llama_model_free(g_state.model);
        g_state.ctx = nullptr;
        g_state.model = nullptr;
        return 0L;
    }

    // Emit loading complete
    {
        bool nd3 = false;
        JNIEnv* pe = jni_attach(nd3);
        if (pe) {
            emit_to_kotlin(pe, "loading_progress", "", 0, 0, 0, 0, 0, 1.0, "", 0);
            if (nd3) g_jvm->DetachCurrentThread();
        }
    }

    // Emit model_loaded event
    {
        bool nd2 = false;
        JNIEnv* evEnv = jni_attach(nd2);
        if (evEnv) {
            emit_to_kotlin(evEnv, "model_loaded", model_name, (int)contextSize,
                           0, 0, 0, 0, 0.0, "", 0);
            if (nd2) g_jvm->DetachCurrentThread();
        }
    }

    LOGI("✅ nativeLoadModel: SUCCESS - handle=%p", g_state.model);
    return reinterpret_cast<jlong>(g_state.model);
}

// ═════════════════════════════════════════════════════════════════════════════
// Additional helper fixes in llama_jni.cpp
// ═════════════════════════════════════════════════════════════════════════════

// 🆕 FIX: Better memory check utility
static int read_mem_available_mb() {
    FILE* f = fopen("/proc/meminfo", "r");
    if (!f) {
        LOGW("read_mem_available_mb: cannot open /proc/meminfo");
        return -1;
    }
    
    char line[256];
    long kb = -1;
    while (fgets(line, sizeof(line), f)) {
        if (strncmp(line, "MemAvailable:", 13) == 0) {
            if (sscanf(line + 13, "%ld", &kb) == 1 && kb > 0) {
                break;
            }
        }
    }
    fclose(f);
    
    if (kb <= 0) {
        LOGW("read_mem_available_mb: cannot parse MemAvailable from /proc/meminfo");
        return -1;
    }
    
    int mb = (int)(kb / 1024);
    LOGD("read_mem_available_mb: %d MB available", mb);
    return mb;
}

// 🆕 FIX: JNI error codes lebih informatif
static jint nativeLoadModel_check_errors(JNIEnv* env, const char* path) {
    // Return error code yang bisa di-interpret di Dart:
    // 0 = OK, 1 = file not found, 2 = permission denied, 3 = invalid format, 4 = memory error
    
    if (!path || !*path) return 1;  // empty path
    
    FILE* f = fopen(path, "rb");
    if (!f) {
        if (errno == ENOENT) return 1;      // not found
        if (errno == EACCES) return 2;      // permission denied
        return 1;                            // other open error
    }
    
    // Check magic
    unsigned char magic[4];
    if (fread(magic, 1, 4, f) != 4 || 
        magic[0] != 'G' || magic[1] != 'G' || magic[2] != 'U' || magic[3] != 'F') {
        fclose(f);
        return 3;  // invalid format
    }
    
    fclose(f);
    return 0;  // OK
}

// ═════════════════════════════════════════════════════════════════════════════
// Call this at JNI_OnLoad untuk initialize properly
// ═════════════════════════════════════════════════════════════════════════════

JNIEXPORT jint JNI_OnLoad(JavaVM* vm, void* reserved) {
    LOGI("╔════════════════════════════════════════════════════════════════╗");
    LOGI("║          KanMon AI - LlamaJNI v2 Initializing                  ║");
    LOGI("║  📌 FIX: use_mmap=false, proper file validation, memory checks ║");
    LOGI("╚════════════════════════════════════════════════════════════════╝");
    
    g_jvm = vm;

    // Install crash handlers
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_sigaction = native_crash_handler;
    sa.sa_flags = SA_SIGINFO | SA_RESETHAND;
    sigaction(SIGBUS,  &sa, nullptr);
    sigaction(SIGSEGV, &sa, nullptr);
    sigaction(SIGABRT, &sa, nullptr);
    sigaction(SIGILL,  &sa, nullptr);

    llama_backend_init();
    llama_numa_init(GGML_NUMA_STRATEGY_DISABLED);

    llama_log_set([](ggml_log_level lvl, const char* txt, void*) {
        if (!txt || !*txt) return;
        std::string s(txt);
        if (!s.empty() && s.back() == '\n') s.pop_back();
        if (s.empty()) return;
        if (lvl == GGML_LOG_LEVEL_ERROR)      LOGE("[ll] %s", s.c_str());
        else if (lvl == GGML_LOG_LEVEL_WARN)  LOGW("[ll] %s", s.c_str());
        else                                   LOGD("[ll] %s", s.c_str());
    }, nullptr);

    int threads = optimal_threads();
    LOGI("✓ LlamaJNI initialized successfully");
    LOGI("  - CPU threads: %d", threads);
    LOGI("  - Memory strategy: NUMA disabled");
    LOGI("  - Crash handlers: installed");
    LOGI("  - Flash attention: check llama.h for support");
    
    return JNI_VERSION_1_6;
}

// ═════════════════════════════════════════════════════════════════════════════
// Print detailed diagnostics ketika model loading fails
// ═════════════════════════════════════════════════════════════════════════════

static void log_loading_diagnostics(const char* path) {
    LOGI("╔════════════════════════════════════════════════════════════════╗");
    LOGI("║              MODEL LOADING DIAGNOSTICS                         ║");
    LOGI("╚════════════════════════════════════════════════════════════════╝");
    
    if (!path || !*path) {
        LOGE("❌ Path is empty");
        return;
    }
    
    LOGI("Path: %s", path);
    
    // Check if file exists
    FILE* f = fopen(path, "rb");
    if (!f) {
        LOGE("❌ File not found or cannot be opened");
        LOGE("   errno=%d: %s", errno, strerror(errno));
        return;
    }
    LOGI("✓ File exists");
    
    // Check size
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);
    LOGI("✓ File size: %ld bytes (%.1f MB)", size, size / (1024.0 * 1024.0));
    
    // Check magic
    unsigned char magic[4];
    size_t read = fread(magic, 1, 4, f);
    if (read == 4 && magic[0] == 'G' && magic[1] == 'G' && 
        magic[2] == 'U' && magic[3] == 'F') {
        LOGI("✓ GGUF magic verified");
    } else {
        LOGE("❌ Invalid GGUF magic: %02x %02x %02x %02x", 
             magic[0], magic[1], magic[2], magic[3]);
    }
    
    fclose(f);
    
    // Check memory
    int avail_mb = read_mem_available_mb();
    LOGI("✓ Available memory: %d MB", avail_mb);
    
    LOGI("╚════════════════════════════════════════════════════════════════╝");
}
