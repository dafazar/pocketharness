// llama_jni.cpp — Pocket Harness — JNI bridge for llama.cpp on Android
//
// KEY FIXES:
// 1. use_mmap=true di Android internal storage → SIGBUS/crash → FIX: set false
// 2. Path tidak valid / file tidak ada → llama_model_load_from_file returns nullptr → FIX: add validation
// 3. Context creation fails → llama_new_context_with_model returns nullptr → FIX: add error logging
// 4. Memory allocation failure → context params terlalu besar → FIX: graceful error handling
// [SESSION 1] registerPlugin() stub fix + emit_to_kotlin static→instance call fix
// [SESSION 4] seq forwarding fix + all emit_to_kotlin call sites updated (12 args)

// ── Standard C/C++ headers ────────────────────────────────────────────────────
#include <jni.h>
#include <android/log.h>

#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <csignal>
#include <string>
#include <mutex>
#include <atomic>
#include <thread>
#include <functional>
#include <vector>
#include <chrono>

// ── llama.cpp headers ─────────────────────────────────────────────────────────
#include "llama.h"
#include "ggml.h"

// ── Android log macros ────────────────────────────────────────────────────────
#define LOG_TAG "PocketHarnessLlama"
#define LOGV(...) __android_log_print(ANDROID_LOG_VERBOSE, LOG_TAG, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG,   LOG_TAG, __VA_ARGS__)
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,    LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN,    LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR,   LOG_TAG, __VA_ARGS__)

// ── JVM global reference (set in JNI_OnLoad) ─────────────────────────────────
static JavaVM* g_jvm = nullptr;

// ── Global reference to LlamaPlugin Kotlin instance (set in registerPlugin) ─
// Required for instance-method JNI callbacks (emitEventFromNative).
static jobject    g_plugin_obj   = nullptr;   // GlobalRef to LlamaPlugin instance
static jclass     g_plugin_cls   = nullptr;   // GlobalRef to LlamaPlugin class
static jmethodID  g_emit_mid     = nullptr;   // emitEventFromNative method ID

// ── Forward declarations ──────────────────────────────────────────────────────
static JNIEnv* jni_attach(bool& needsDetach);
static int     optimal_threads();
static void    native_crash_handler(int sig, siginfo_t* info, void* ctx);
static void    emit_to_kotlin(JNIEnv* env, const char* event,
                              const char* text, int promptTokens,
                              int genTokens, int totalTokens,
                              int tps, int ttft, int seq,
                              double progress, const char* error, int errorCode);

// ── Global inference state ────────────────────────────────────────────────────
struct LlamaState {
    llama_model*   model   = nullptr;
    llama_context* ctx     = nullptr;
    llama_sampler* sampler = nullptr;
    std::atomic<bool> shouldStop{false};
    std::mutex modelMutex;

    bool isLoaded() const { return model != nullptr && ctx != nullptr; }

    void clear() {
        if (sampler) { llama_sampler_free(sampler); sampler = nullptr; }
        if (ctx)     { llama_free(ctx);              ctx     = nullptr; }
        if (model)   { llama_model_free(model);      model   = nullptr; }
    }
};
static LlamaState g_state;

// ── JNI helper: attach current thread ────────────────────────────────────────
static JNIEnv* jni_attach(bool& needsDetach) {
    if (!g_jvm) return nullptr;
    JNIEnv* env = nullptr;
    jint r = g_jvm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6);
    if (r == JNI_OK) { needsDetach = false; return env; }
    if (r == JNI_EDETACHED) {
        if (g_jvm->AttachCurrentThread(&env, nullptr) == JNI_OK) {
            needsDetach = true;
            return env;
        }
    }
    return nullptr;
}

// ── Optimal thread count (leave 1 core for UI) ───────────────────────────────
static int optimal_threads() {
    int n = (int)std::thread::hardware_concurrency();
    return (n > 1) ? n - 1 : 1;
}

// ── Crash handler ─────────────────────────────────────────────────────────────
static void native_crash_handler(int sig, siginfo_t* /*info*/, void* /*ctx*/) {
    LOGE("NATIVE CRASH signal=%d in LlamaJNI", sig);
    g_state.shouldStop = true;
}

// ── emit_to_kotlin — call LlamaPlugin.emitEventFromNative() on cached instance.
// [SESSION 1 FIX] Uses CallVoidMethod (instance) instead of CallStaticVoidMethod.
// [SESSION 4 FIX] Added int seq parameter; forwarded to emitEventFromNative.
//
// Parameter mapping to Kotlin fun emitEventFromNative:
//   event       → type         (String)
//   text        → token        (String)
//   seq         → seq          (Int) — [S4] forwarded from nativeGenerateTokens
//   promptTokens→ promptTokens (Int)
//   genTokens   → evalTokens   (Int)
//   ttft        → promptMs     (Long)
//   progress    → evalMs       (Long, via *1000)
//   tps         → tokensPerSec (Double)
//   error       → errorMsg     (String)
//   errorCode   → availMb      (Int)
static void emit_to_kotlin(JNIEnv* env, const char* event,
                            const char* text, int promptTokens,
                            int genTokens, int totalTokens,
                            int tps, int ttft, int seq,
                            double progress, const char* error, int errorCode) {
    if (!env || !event) return;

    // Guard: plugin must be registered via registerPlugin()
    if (g_plugin_obj == nullptr || g_plugin_cls == nullptr || g_emit_mid == nullptr) {
        LOGW("emit_to_kotlin: plugin not registered — dropping event '%s'", event);
        return;
    }

    // Build JNI strings
    jstring jType   = env->NewStringUTF(event ? event : "");
    jstring jToken  = env->NewStringUTF(text  ? text  : "");
    jstring jErrMsg = env->NewStringUTF(error ? error : "");

    if (!jType || !jToken || !jErrMsg) {
        LOGE("emit_to_kotlin: NewStringUTF failed (OOM?)");
        if (jType)   env->DeleteLocalRef(jType);
        if (jToken)  env->DeleteLocalRef(jToken);
        if (jErrMsg) env->DeleteLocalRef(jErrMsg);
        return;
    }

    // [SESSION 1 FIX] CallVoidMethod (instance) — NOT CallStaticVoidMethod
    // [SESSION 4 FIX] (jint)seq passed instead of hardcoded (jint)0
    env->CallVoidMethod(
        g_plugin_obj,
        g_emit_mid,
        jType,
        jToken,
        (jint)seq,                        // seq — forwarded from nativeGenerateTokens
        (jint)promptTokens,
        (jint)genTokens,
        (jlong)ttft,                      // promptMs
        (jlong)(long)(progress * 1000.0), // evalMs
        (jdouble)tps,                     // tokensPerSec
        jErrMsg,
        (jint)errorCode                   // availMb reused
    );

    // Clear any exception that occurred during the callback
    if (env->ExceptionCheck()) {
        env->ExceptionDescribe();
        env->ExceptionClear();
        LOGE("emit_to_kotlin: exception during CallVoidMethod for event '%s'", event);
    }

    env->DeleteLocalRef(jType);
    env->DeleteLocalRef(jToken);
    env->DeleteLocalRef(jErrMsg);
}

// ═════════════════════════════════════════════════════════════════════════════
// nativeLoadModel
// ═════════════════════════════════════════════════════════════════════════════

extern "C" JNIEXPORT jlong JNICALL
Java_com_pocketharness_app_LlamaPlugin_nativeLoadModel(
    JNIEnv* env, jobject thiz,
    jstring jPath, jint contextSize, jint gpuLayers,
    jint nBatch, jint nThreads, jboolean useFlashAttn,
    jboolean memLock, jfloat ropeBase, jfloat ropeScale)
{
    const char* rawPath = env->GetStringUTFChars(jPath, nullptr);
    std::string path(rawPath);
    env->ReleaseStringUTFChars(jPath, rawPath);

    LOGI("nativeLoadModel: START");
    LOGI("  path=%s", path.c_str());
    LOGI("  ctx=%d gpu=%d batch=%d threads=%d flash=%d mlock=%d rope=%.2f/%.2f",
         (int)contextSize, (int)gpuLayers,
         (int)nBatch, (int)nThreads, (int)useFlashAttn,
         (int)memLock, (float)ropeBase, (float)ropeScale);

    if (path.empty()) {
        LOGE("nativeLoadModel: path is empty!");
        return 0L;
    }

    FILE* test_file = fopen(path.c_str(), "rb");
    if (!test_file) {
        LOGE("nativeLoadModel: cannot open file - errno=%d (%s)", errno, strerror(errno));
        return 0L;
    }

    fseek(test_file, 0, SEEK_END);
    long file_size = ftell(test_file);
    fseek(test_file, 0, SEEK_SET);

    LOGI("nativeLoadModel: file opened, size=%ld bytes (%.1f MB)",
         file_size, file_size / (1024.0 * 1024.0));

    if (file_size < 1024 * 1024) {
        LOGE("nativeLoadModel: file too small (%ld bytes)", file_size);
        fclose(test_file);
        return 0L;
    }

    unsigned char magic[4];
    size_t nread = fread(magic, 1, 4, test_file);
    fclose(test_file);

    if (nread != 4 || magic[0] != 'G' || magic[1] != 'G' || magic[2] != 'U' || magic[3] != 'F') {
        LOGE("nativeLoadModel: invalid GGUF magic (got %02x%02x%02x%02x)",
             magic[0], magic[1], magic[2], magic[3]);
        return 0L;
    }

    LOGI("nativeLoadModel: GGUF magic verified");

    std::lock_guard<std::mutex> lk(g_state.modelMutex);

    if (g_state.isLoaded()) {
        LOGI("nativeLoadModel: releasing previous model");
        g_state.shouldStop = true;
        g_state.clear();
        g_state.shouldStop = false;
    }

    auto mparams = llama_model_default_params();
    mparams.n_gpu_layers = (int)gpuLayers;
    mparams.use_mlock    = (bool)memLock;
    mparams.use_mmap     = false; // CRITICAL: mmap=true causes SIGBUS on Android internal storage!

    LOGI("nativeLoadModel: model params - gpu_layers=%d mlock=%d mmap=%d",
         mparams.n_gpu_layers, mparams.use_mlock, mparams.use_mmap);

    // Emit initial loading progress — seq=0 (not a generation event)
    {
        bool nd = false;
        JNIEnv* cbEnv = jni_attach(nd);
        if (cbEnv) {
            emit_to_kotlin(cbEnv, "loading_progress", "", 0, 0, 0, 0, 0, 0, 0.0, "", 0);
            if (nd) g_jvm->DetachCurrentThread();
        }
    }

    LOGI("nativeLoadModel: calling llama_model_load_from_file...");
    g_state.model = llama_model_load_from_file(path.c_str(), mparams);

    if (!g_state.model) {
        LOGE("nativeLoadModel: llama_model_load_from_file FAILED - returned nullptr");
        return 0L;
    }

    LOGI("nativeLoadModel: model loaded OK");

    char model_name[256] = "unknown";
    llama_model_meta_val_str(g_state.model, "general.name", model_name, sizeof(model_name));
    int model_ctx = (int)llama_model_n_ctx_train(g_state.model);
    LOGI("  model name: %s", model_name);
    LOGI("  model context size: %d", model_ctx);

    auto cparams = llama_context_default_params();
    cparams.n_ctx     = (uint32_t)contextSize;
    cparams.n_batch   = (uint32_t)nBatch;
    cparams.n_threads = (nThreads > 0) ? (uint32_t)nThreads : (uint32_t)optimal_threads();

    if (cparams.n_ctx > (uint32_t)model_ctx) {
        LOGW("nativeLoadModel: clamping context %d to %d (model max)",
             (int)cparams.n_ctx, model_ctx);
        cparams.n_ctx = (uint32_t)model_ctx;
    }

    if (ropeBase  > 0.0f) cparams.rope_freq_base  = ropeBase;
    if (ropeScale > 0.0f) cparams.rope_freq_scale = ropeScale;

    LOGI("nativeLoadModel: context params - n_ctx=%d n_batch=%d n_threads=%d",
         (int)cparams.n_ctx, (int)cparams.n_batch, (int)cparams.n_threads);

    LOGI("nativeLoadModel: calling llama_new_context_with_model...");
    g_state.ctx = llama_new_context_with_model(g_state.model, cparams);

    if (!g_state.ctx) {
        LOGE("nativeLoadModel: llama_new_context_with_model FAILED");
        llama_model_free(g_state.model);
        g_state.model = nullptr;
        return 0L;
    }

    LOGI("nativeLoadModel: context ready ctx=%d threads=%d batch=%d",
         (int)contextSize, (int)cparams.n_threads, (int)cparams.n_batch);

    g_state.sampler = llama_sampler_chain_init(llama_sampler_chain_default_params());
    if (!g_state.sampler) {
        LOGE("nativeLoadModel: sampler creation failed");
        llama_free(g_state.ctx);
        llama_model_free(g_state.model);
        g_state.ctx = nullptr;
        g_state.model = nullptr;
        return 0L;
    }

    // Emit loading complete — seq=0 (not a generation event)
    {
        bool nd3 = false;
        JNIEnv* pe = jni_attach(nd3);
        if (pe) {
            emit_to_kotlin(pe, "loading_progress", "", 0, 0, 0, 0, 0, 0, 1.0, "", 0);
            if (nd3) g_jvm->DetachCurrentThread();
        }
    }

    // Emit model_loaded event — seq=0 (not a generation event)
    {
        bool nd2 = false;
        JNIEnv* evEnv = jni_attach(nd2);
        if (evEnv) {
            emit_to_kotlin(evEnv, "model_loaded", model_name, (int)contextSize,
                           0, 0, 0, 0, 0, 0.0, "", 0);
            if (nd2) g_jvm->DetachCurrentThread();
        }
    }

    LOGI("nativeLoadModel: SUCCESS - handle=%p", g_state.model);
    return reinterpret_cast<jlong>(g_state.model);
}

// ─────────────────────────────────────────────────────────────────────────────
// Memory utility
// ─────────────────────────────────────────────────────────────────────────────

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
            if (sscanf(line + 13, "%ld", &kb) == 1 && kb > 0) break;
        }
    }
    fclose(f);
    if (kb <= 0) {
        LOGW("read_mem_available_mb: cannot parse MemAvailable");
        return -1;
    }
    int mb = (int)(kb / 1024);
    LOGD("read_mem_available_mb: %d MB available", mb);
    return mb;
}

static jint nativeLoadModel_check_errors(JNIEnv* /*env*/, const char* path) {
    if (!path || !*path) return 1;
    FILE* f = fopen(path, "rb");
    if (!f) {
        if (errno == ENOENT) return 1;
        if (errno == EACCES) return 2;
        return 1;
    }
    unsigned char magic[4];
    if (fread(magic, 1, 4, f) != 4 ||
        magic[0] != 'G' || magic[1] != 'G' || magic[2] != 'U' || magic[3] != 'F') {
        fclose(f);
        return 3;
    }
    fclose(f);
    return 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// JNI_OnLoad
// ─────────────────────────────────────────────────────────────────────────────

extern "C" JNIEXPORT jint JNI_OnLoad(JavaVM* vm, void* reserved) {
    LOGI("Pocket Harness - LlamaJNI Initializing");
    LOGI("[S1] registerPlugin + instance-method callback fixed");
    LOGI("[S4] seq forwarding fixed");

    g_jvm = vm;

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
        if (lvl == GGML_LOG_LEVEL_ERROR)     LOGE("[ll] %s", s.c_str());
        else if (lvl == GGML_LOG_LEVEL_WARN) LOGW("[ll] %s", s.c_str());
        else                                  LOGD("[ll] %s", s.c_str());
    }, nullptr);

    LOGI("LlamaJNI initialized - CPU threads: %d", optimal_threads());
    return JNI_VERSION_1_6;
}

static void log_loading_diagnostics(const char* path) {
    LOGI("MODEL LOADING DIAGNOSTICS");
    if (!path || !*path) { LOGE("Path is empty"); return; }
    LOGI("Path: %s", path);
    FILE* f = fopen(path, "rb");
    if (!f) { LOGE("File not found: errno=%d: %s", errno, strerror(errno)); return; }
    LOGI("File exists");
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);
    LOGI("File size: %ld bytes (%.1f MB)", size, size / (1024.0 * 1024.0));
    unsigned char magic[4];
    size_t nr = fread(magic, 1, 4, f);
    if (nr == 4 && magic[0]=='G' && magic[1]=='G' && magic[2]=='U' && magic[3]=='F')
        LOGI("GGUF magic verified");
    else
        LOGE("Invalid GGUF magic: %02x %02x %02x %02x", magic[0], magic[1], magic[2], magic[3]);
    fclose(f);
    LOGI("Available memory: %d MB", read_mem_available_mb());
}

// ═════════════════════════════════════════════════════════════════════════════
// [SESSION 1 FIX] registerPlugin — store GlobalRef to LlamaPlugin instance
// so that emit_to_kotlin can call emitEventFromNative() as an instance method.
// ═════════════════════════════════════════════════════════════════════════════

extern "C" JNIEXPORT void JNICALL
Java_com_pocketharness_app_LlamaPlugin_registerPlugin(JNIEnv* env, jobject thiz) {
    LOGI("registerPlugin: storing global plugin reference...");

    // Release any previous references to avoid leaking on re-register
    if (g_plugin_obj != nullptr) {
        env->DeleteGlobalRef(g_plugin_obj);
        g_plugin_obj = nullptr;
    }
    if (g_plugin_cls != nullptr) {
        env->DeleteGlobalRef(g_plugin_cls);
        g_plugin_cls = nullptr;
    }
    g_emit_mid = nullptr;

    // Store GlobalRef to LlamaPlugin instance (thiz)
    // Local ref is only valid for the current JNI call stack frame.
    // GlobalRef survives across threads and call frames.
    g_plugin_obj = env->NewGlobalRef(thiz);
    if (g_plugin_obj == nullptr) {
        LOGE("registerPlugin: NewGlobalRef(thiz) failed — out of memory?");
        return;
    }

    // Cache class as GlobalRef (FindClass is expensive and thread-unsafe on background threads)
    jclass localCls = env->GetObjectClass(thiz);
    if (localCls == nullptr) {
        LOGE("registerPlugin: GetObjectClass failed");
        env->DeleteGlobalRef(g_plugin_obj);
        g_plugin_obj = nullptr;
        return;
    }
    g_plugin_cls = reinterpret_cast<jclass>(env->NewGlobalRef(localCls));
    env->DeleteLocalRef(localCls);

    if (g_plugin_cls == nullptr) {
        LOGE("registerPlugin: NewGlobalRef(class) failed");
        env->DeleteGlobalRef(g_plugin_obj);
        g_plugin_obj = nullptr;
        return;
    }

    // Cache method ID for emitEventFromNative.
    // Signature: (Ljava/lang/String;Ljava/lang/String;IIIJJDLjava/lang/String;I)V
    // Matches Kotlin: fun emitEventFromNative(
    //   type:String, token:String, seq:Int,
    //   promptTokens:Int, evalTokens:Int,
    //   promptMs:Long, evalMs:Long,
    //   tokensPerSec:Double, errorMsg:String, availMb:Int)
    g_emit_mid = env->GetMethodID(
        g_plugin_cls,
        "emitEventFromNative",
        "(Ljava/lang/String;Ljava/lang/String;IIIJJDLjava/lang/String;I)V"
    );
    if (g_emit_mid == nullptr) {
        LOGE("registerPlugin: GetMethodID(emitEventFromNative) failed — signature mismatch?");
        env->ExceptionClear();
        env->DeleteGlobalRef(g_plugin_cls);
        env->DeleteGlobalRef(g_plugin_obj);
        g_plugin_cls = nullptr;
        g_plugin_obj = nullptr;
        return;
    }

    LOGI("registerPlugin: OK g_plugin_obj=%p g_emit_mid=%p", g_plugin_obj, g_emit_mid);
}

// ═════════════════════════════════════════════════════════════════════════════
// nativeReleaseModel
// ═════════════════════════════════════════════════════════════════════════════

extern "C" JNIEXPORT void JNICALL
Java_com_pocketharness_app_LlamaPlugin_nativeReleaseModel(
    JNIEnv* env, jobject thiz, jlong modelHandle)
{
    LOGI("nativeReleaseModel: handle=%lld", (long long)modelHandle);
    std::lock_guard<std::mutex> lk(g_state.modelMutex);
    g_state.shouldStop = true;
    g_state.clear();
    g_state.shouldStop = false;
    // Note: do NOT release g_plugin_obj / g_plugin_cls here — they are needed
    // for any final "done" or "error" callbacks that may arrive on background
    // threads. They are released and re-set only in registerPlugin().
    LOGI("nativeReleaseModel: done (plugin refs retained for callbacks)");
}

// ═════════════════════════════════════════════════════════════════════════════
// nativeStopGeneration
// ═════════════════════════════════════════════════════════════════════════════

extern "C" JNIEXPORT void JNICALL
Java_com_pocketharness_app_LlamaPlugin_nativeStopGeneration(
    JNIEnv* env, jobject thiz, jlong modelHandle)
{
    LOGI("nativeStopGeneration: requested");
    g_state.shouldStop = true;
}

// ═════════════════════════════════════════════════════════════════════════════
// nativeIsReady
// ═════════════════════════════════════════════════════════════════════════════

extern "C" JNIEXPORT jboolean JNICALL
Java_com_pocketharness_app_LlamaPlugin_nativeIsReady(
    JNIEnv* env, jobject thiz, jlong modelHandle)
{
    return g_state.isLoaded() ? JNI_TRUE : JNI_FALSE;
}

// ═════════════════════════════════════════════════════════════════════════════
// nativeGetTokenCount
// ═════════════════════════════════════════════════════════════════════════════

extern "C" JNIEXPORT jint JNICALL
Java_com_pocketharness_app_LlamaPlugin_nativeGetTokenCount(
    JNIEnv* env, jobject thiz, jlong modelHandle, jstring jText)
{
    if (!g_state.isLoaded() || !jText) return -1;

    const char* raw = env->GetStringUTFChars(jText, nullptr);
    if (!raw) return -1;
    std::string text(raw);
    env->ReleaseStringUTFChars(jText, raw);

    int n = (int)text.size() + 16;
    std::vector<llama_token> tokens(n);
    const llama_vocab* vocab_tc = llama_model_get_vocab(g_state.model);
    int count = llama_tokenize(vocab_tc, text.c_str(), (int)text.size(),
                               tokens.data(), n, true, false);
    return (count < 0) ? 0 : count;
}

// ═════════════════════════════════════════════════════════════════════════════
// nativeGetAvailableMemoryMb
// ═════════════════════════════════════════════════════════════════════════════

extern "C" JNIEXPORT jint JNICALL
Java_com_pocketharness_app_LlamaPlugin_nativeGetAvailableMemoryMb(
    JNIEnv* env, jobject thiz)
{
    return (jint)read_mem_available_mb();
}

// ═════════════════════════════════════════════════════════════════════════════
// nativeGetModelInfo  →  JSON string
// ═════════════════════════════════════════════════════════════════════════════

extern "C" JNIEXPORT jstring JNICALL
Java_com_pocketharness_app_LlamaPlugin_nativeGetModelInfo(
    JNIEnv* env, jobject thiz, jstring jPath)
{
    const char* raw = jPath ? env->GetStringUTFChars(jPath, nullptr) : nullptr;
    std::string path = raw ? raw : "";
    if (raw) env->ReleaseStringUTFChars(jPath, raw);

    int err = nativeLoadModel_check_errors(env, path.c_str());
    if (err != 0) {
        char buf[256];
        snprintf(buf, sizeof(buf),
                 "{\"error\":\"file_check_failed\",\"code\":%d,\"path\":\"%s\"}",
                 err, path.c_str());
        return env->NewStringUTF(buf);
    }

    auto mparams = llama_model_default_params();
    mparams.n_gpu_layers = 0;
    mparams.use_mmap     = false;
    mparams.use_mlock    = false;
    llama_model* m = llama_model_load_from_file(path.c_str(), mparams);
    if (!m) {
        return env->NewStringUTF(
            "{\"error\":\"load_failed\",\"name\":\"unknown\","
            "\"arch\":\"unknown\",\"contextLength\":0,\"paramCount\":0}");
    }

    char name[256] = "unknown";
    char arch[64]  = "unknown";
    llama_model_meta_val_str(m, "general.name",         name, sizeof(name));
    llama_model_meta_val_str(m, "general.architecture", arch, sizeof(arch));
    int ctx_train = (int)llama_model_n_ctx_train(m);
    int n_params  = (int)(llama_model_n_params(m) / 1000000LL);

    llama_model_free(m);

    char json[1024];
    snprintf(json, sizeof(json),
             "{\"name\":\"%s\",\"arch\":\"%s\","
             "\"contextLength\":%d,\"paramCount\":%d,\"stub\":false}",
             name, arch, ctx_train, n_params);
    return env->NewStringUTF(json);
}

// ═════════════════════════════════════════════════════════════════════════════
// nativeGenerateTokens  — streaming inference
// [SESSION 4 FIX] All emit_to_kotlin calls now pass (int)seq as 9th argument.
// ═════════════════════════════════════════════════════════════════════════════

extern "C" JNIEXPORT jboolean JNICALL
Java_com_pocketharness_app_LlamaPlugin_nativeGenerateTokens(
    JNIEnv* env, jobject thiz,
    jlong modelHandle, jstring jPrompt,
    jfloat temp, jfloat topP, jint topK, jint maxTokens,
    jint seq, jfloat repeatPenalty, jint seed,
    jint mirostatMode, jfloat mirostatTau, jfloat mirostatEta,
    jfloat minP, jboolean penalizeNl)
{
    if (!g_state.isLoaded()) {
        LOGE("nativeGenerateTokens: model not loaded");
        return JNI_FALSE;
    }
    if (!jPrompt) {
        LOGE("nativeGenerateTokens: null prompt");
        return JNI_FALSE;
    }

    const char* rawPrompt = env->GetStringUTFChars(jPrompt, nullptr);
    std::string prompt(rawPrompt ? rawPrompt : "");
    if (rawPrompt) env->ReleaseStringUTFChars(jPrompt, rawPrompt);

    LOGI("nativeGenerateTokens: prompt_len=%d max_tokens=%d temp=%.2f seq=%d",
         (int)prompt.size(), (int)maxTokens, (float)temp, (int)seq);

    g_state.shouldStop = false;

    // ── Tokenize prompt ───────────────────────────────────────────────────────
    int n_ctx = (int)llama_n_ctx(g_state.ctx);
    std::vector<llama_token> promptTokens(n_ctx);
    const llama_vocab* vocab = llama_model_get_vocab(g_state.model);
    int n_prompt = llama_tokenize(vocab,
                                  prompt.c_str(), (int)prompt.size(),
                                  promptTokens.data(), (int)promptTokens.size(),
                                  true, false);
    if (n_prompt < 0) {
        LOGE("nativeGenerateTokens: tokenize failed (n_prompt=%d)", n_prompt);
        return JNI_FALSE;
    }
    promptTokens.resize(n_prompt);

    if (n_prompt >= n_ctx) {
        int trim = n_ctx - 4;
        LOGW("nativeGenerateTokens: prompt too long (%d), trimming to %d", n_prompt, trim);
        promptTokens.erase(promptTokens.begin(), promptTokens.begin() + (n_prompt - trim));
        n_prompt = (int)promptTokens.size();
    }

    // ── KV cache clear ────────────────────────────────────────────────────────
    auto* mem = llama_get_memory(g_state.ctx);
    if (mem) llama_memory_clear(mem, true);

    // ── Sampler setup ─────────────────────────────────────────────────────────
    if (g_state.sampler) {
        llama_sampler_free(g_state.sampler);
        g_state.sampler = nullptr;
    }
    g_state.sampler = llama_sampler_chain_init(llama_sampler_chain_default_params());

    if (mirostatMode == 1) {
        llama_sampler_chain_add(g_state.sampler,
            llama_sampler_init_mirostat(llama_vocab_n_tokens(llama_model_get_vocab(g_state.model)),
                                        (uint32_t)seed, mirostatTau, mirostatEta, 100));
    } else if (mirostatMode == 2) {
        llama_sampler_chain_add(g_state.sampler,
            llama_sampler_init_mirostat_v2((uint32_t)seed, mirostatTau, mirostatEta));
    } else {
        if (topK > 0)
            llama_sampler_chain_add(g_state.sampler, llama_sampler_init_top_k(topK));
        if (minP > 0.0f)
            llama_sampler_chain_add(g_state.sampler, llama_sampler_init_min_p(minP, 1));
        if (topP < 1.0f)
            llama_sampler_chain_add(g_state.sampler, llama_sampler_init_top_p(topP, 1));
        if (repeatPenalty != 1.0f)
            llama_sampler_chain_add(g_state.sampler,
                llama_sampler_init_penalties(64, repeatPenalty, 0.0f, 0.0f));
        if (temp > 0.0f)
            llama_sampler_chain_add(g_state.sampler, llama_sampler_init_temp(temp));
        llama_sampler_chain_add(g_state.sampler,
            llama_sampler_init_dist((seed >= 0) ? (uint32_t)seed : LLAMA_DEFAULT_SEED));
    }

    // ── Batch: prompt eval ────────────────────────────────────────────────────
    llama_batch batch = llama_batch_get_one(promptTokens.data(), n_prompt);
    if (llama_decode(g_state.ctx, batch) != 0) {
        LOGE("nativeGenerateTokens: llama_decode (prompt) failed");
        return JNI_FALSE;
    }

    auto t_start = std::chrono::steady_clock::now();
    int  n_gen   = 0;
    int  ttft_ms = -1;
    std::string accumulated;

    llama_token eos = llama_vocab_eos(llama_model_get_vocab(g_state.model));

    // ── Generation loop ───────────────────────────────────────────────────────
    while (n_gen < (int)maxTokens && !g_state.shouldStop) {
        llama_token tok = llama_sampler_sample(g_state.sampler, g_state.ctx, -1);
        llama_sampler_accept(g_state.sampler, tok);

        if (tok == eos) {
            LOGI("nativeGenerateTokens: EOS reached after %d tokens", n_gen);
            break;
        }

        char piece[256] = {};
        int  plen = llama_token_to_piece(llama_model_get_vocab(g_state.model),
                                         tok, piece, sizeof(piece) - 1, 0, true);
        if (plen > 0) {
            piece[plen] = '\0';
            accumulated += piece;

            if (n_gen == 0) {
                auto now = std::chrono::steady_clock::now();
                ttft_ms  = (int)std::chrono::duration_cast<std::chrono::milliseconds>(
                               now - t_start).count();
            }

            // [SESSION 4 FIX] pass (int)seq as 9th argument
            bool nd = false;
            JNIEnv* cbEnv = jni_attach(nd);
            if (cbEnv) {
                int elapsed_ms = (int)std::chrono::duration_cast<std::chrono::milliseconds>(
                    std::chrono::steady_clock::now() - t_start).count();
                int tps = (elapsed_ms > 0) ? (int)(n_gen * 1000.0 / elapsed_ms) : 0;
                emit_to_kotlin(cbEnv, "token", piece,
                               n_prompt, n_gen + 1, n_prompt + n_gen + 1,
                               tps, ttft_ms, (int)seq, 0.0, "", 0);
                if (nd) g_jvm->DetachCurrentThread();
            }
        }

        n_gen++;

        llama_batch next = llama_batch_get_one(&tok, 1);
        if (llama_decode(g_state.ctx, next) != 0) {
            LOGW("nativeGenerateTokens: llama_decode (next token) failed at gen=%d", n_gen);
            break;
        }
    }

    bool stopped = g_state.shouldStop.load();
    LOGI("nativeGenerateTokens: done gen=%d stopped=%d seq=%d", n_gen, stopped, (int)seq);

    // Emit generation_complete — [SESSION 4 FIX] pass (int)seq as 9th argument
    {
        auto now = std::chrono::steady_clock::now();
        int elapsed_ms = (int)std::chrono::duration_cast<std::chrono::milliseconds>(
            now - t_start).count();
        int tps = (elapsed_ms > 0) ? (int)(n_gen * 1000.0 / elapsed_ms) : 0;

        bool nd = false;
        JNIEnv* cbEnv = jni_attach(nd);
        if (cbEnv) {
            emit_to_kotlin(cbEnv, "generation_complete", accumulated.c_str(),
                           n_prompt, n_gen, n_prompt + n_gen,
                           tps, ttft_ms, (int)seq, 1.0, "", 0);
            if (nd) g_jvm->DetachCurrentThread();
        }
    }

    return stopped ? JNI_FALSE : JNI_TRUE;
}
