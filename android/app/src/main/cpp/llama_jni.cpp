// ════════════════════════════════════════════════════════════════════════════
// KanMon GO — llama.cpp JNI Bridge  (Sesi 6 — Memory V2 API)
//
// CHANGES vs Sesi 5:
//   - Completely new JNI surface aligned with LlamaPlugin.kt Sesi 6
//   - nativeLoadModel: full params (contextSize, gpuLayers, nBatch, nThreads,
//     useFlashAttn, memLock, ropeBase, ropeScale) → returns jlong model handle
//   - nativeReleaseModel(modelHandle): per-handle release
//   - nativeGenerateTokens: full sampler params (temp, topP, topK, maxTokens,
//     seq, repeatPenalty, seed, mirostatMode, mirostatTau, mirostatEta, minP,
//     penalizeNl)
//   - nativeGetModelInfo(path): loads vocab-only, returns JSON
//   - nativeIsReady, nativeGetTokenCount, nativeGetAvailableMemoryMb
//   - Memory V2 API ONLY: llama_memory_clear / llama_memory_seq_rm
//   - Events emitted back to Kotlin via JNI reflection (emitEventFromNative)
//   - NO #ifdef LLAMA_API_MEMORY_V2 — V2 used unconditionally
// ════════════════════════════════════════════════════════════════════════════

#include <jni.h>
#include <string>
#include <vector>
#include <mutex>
#include <atomic>
#include <thread>
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <chrono>
#include <sstream>
#include <signal.h>
#include <android/log.h>

#include "llama.h"

#define LOG_TAG "LlamaJNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN,  LOG_TAG, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)

// ─────────────────────────────────────────────────────────────────────────────
// Global JVM reference (for callback from native threads)
// ─────────────────────────────────────────────────────────────────────────────
static JavaVM* g_jvm          = nullptr;
static jobject g_plugin_obj   = nullptr;   // global ref to LlamaPlugin Kotlin instance
static jmethodID g_emit_method = nullptr;  // LlamaPlugin.emitEventFromNative(...)

// ─────────────────────────────────────────────────────────────────────────────
// Per-model state
// ─────────────────────────────────────────────────────────────────────────────
struct LlamaModelState {
    llama_model*   model   = nullptr;
    llama_context* ctx     = nullptr;
    llama_sampler* sampler = nullptr;

    std::atomic<bool> shouldStop{false};
    std::atomic<bool> isGenerating{false};
    std::mutex modelMutex;

    bool isLoaded() const { return model != nullptr && ctx != nullptr; }

    void clear() {
        if (sampler) { llama_sampler_free(sampler); sampler = nullptr; }
        if (ctx)     { llama_free(ctx);              ctx     = nullptr; }
        if (model)   { llama_model_free(model);      model   = nullptr; }
    }
};

// Single global state (model handle is just the pointer cast to jlong)
static LlamaModelState g_state;

// ─────────────────────────────────────────────────────────────────────────────
// Utility: attach current thread to JVM
// ─────────────────────────────────────────────────────────────────────────────
static JNIEnv* jni_attach(bool& needs_detach) {
    needs_detach = false;
    if (!g_jvm) return nullptr;
    JNIEnv* env = nullptr;
    jint status = g_jvm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6);
    if (status == JNI_EDETACHED) {
        JavaVMAttachArgs args = {JNI_VERSION_1_6, "llama-gen", nullptr};
        if (g_jvm->AttachCurrentThread(&env, &args) == JNI_OK) {
            needs_detach = true;
        } else {
            LOGE("jni_attach: AttachCurrentThread failed");
            return nullptr;
        }
    } else if (status != JNI_OK) {
        LOGE("jni_attach: GetEnv status=%d", (int)status);
        return nullptr;
    }
    return env;
}

// ─────────────────────────────────────────────────────────────────────────────
// Emit event to Kotlin plugin via JNI reflection
// type:  "token" | "done" | "error" | "loading_progress" | "memory_warning"
// ─────────────────────────────────────────────────────────────────────────────
static void emit_to_kotlin(
    JNIEnv* env,
    const char* type,
    const char* token,
    int seq,
    int promptTokens,
    int evalTokens,
    long long promptMs,
    long long evalMs,
    double tokensPerSec,
    const char* errorMsg,
    int availMb)
{
    if (!g_plugin_obj || !g_emit_method || !env) return;

    jstring jType        = env->NewStringUTF(type ? type : "");
    jstring jToken       = env->NewStringUTF(token ? token : "");
    jstring jError       = env->NewStringUTF(errorMsg ? errorMsg : "");

    env->CallVoidMethod(g_plugin_obj, g_emit_method,
        jType,
        jToken,
        (jint)seq,
        (jint)promptTokens,
        (jint)evalTokens,
        (jlong)promptMs,
        (jlong)evalMs,
        (jdouble)tokensPerSec,
        jError,
        (jint)availMb
    );

    env->DeleteLocalRef(jType);
    env->DeleteLocalRef(jToken);
    env->DeleteLocalRef(jError);

    if (env->ExceptionCheck()) {
        env->ExceptionClear();
        LOGW("emit_to_kotlin: exception after CallVoidMethod (type=%s)", type ? type : "?");
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Read /proc/meminfo → MemAvailable in MB
// ─────────────────────────────────────────────────────────────────────────────
static int read_mem_available_mb() {
    FILE* f = fopen("/proc/meminfo", "r");
    if (!f) return -1;
    char line[256];
    long kb = -1;
    while (fgets(line, sizeof(line), f)) {
        if (strncmp(line, "MemAvailable:", 13) == 0) {
            sscanf(line + 13, "%ld", &kb);
            break;
        }
    }
    fclose(f);
    return (kb > 0) ? (int)(kb / 1024) : -1;
}

// ─────────────────────────────────────────────────────────────────────────────
// Optimal thread count
// ─────────────────────────────────────────────────────────────────────────────
static int optimal_threads() {
    int n = (int)std::thread::hardware_concurrency();
    if (n <= 0) return 4;
    if (n >= 8) return 4;
    return std::max(1, n / 2);
}

// ─────────────────────────────────────────────────────────────────────────────
// Native crash handler
// ─────────────────────────────────────────────────────────────────────────────
static void native_crash_handler(int signum, siginfo_t* info, void*) {
    const char* sname = "UNKNOWN";
    switch (signum) {
        case SIGBUS:  sname = "SIGBUS";  break;
        case SIGSEGV: sname = "SIGSEGV"; break;
        case SIGABRT: sname = "SIGABRT"; break;
        case SIGILL:  sname = "SIGILL";  break;
    }
    __android_log_print(ANDROID_LOG_ERROR, LOG_TAG,
        "=== NATIVE CRASH === sig=%d (%s) generating=%s",
        signum, sname,
        g_state.isGenerating.load() ? "YES" : "NO");
    if (info) {
        __android_log_print(ANDROID_LOG_ERROR, LOG_TAG,
            "Fault addr: %p", info->si_addr);
    }
    signal(signum, SIG_DFL);
    raise(signum);
}

// ─────────────────────────────────────────────────────────────────────────────
// JNI_OnLoad / JNI_OnUnload
// ─────────────────────────────────────────────────────────────────────────────
JNIEXPORT jint JNI_OnLoad(JavaVM* vm, void* reserved) {
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

    LOGI("LlamaJNI v2 loaded (Memory V2 API) | threads=%d", optimal_threads());
    return JNI_VERSION_1_6;
}

JNIEXPORT void JNI_OnUnload(JavaVM* vm, void* reserved) {
    g_state.shouldStop = true;
    {
        std::lock_guard<std::mutex> lk(g_state.modelMutex);
        g_state.clear();
    }
    if (g_plugin_obj && g_jvm) {
        JNIEnv* env = nullptr;
        if (g_jvm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) == JNI_OK) {
            env->DeleteGlobalRef(g_plugin_obj);
        }
        g_plugin_obj = nullptr;
    }
    llama_backend_free();
    g_jvm = nullptr;
    LOGI("LlamaJNI unloaded");
}

// ─────────────────────────────────────────────────────────────────────────────
// Called from Kotlin init to register the plugin instance for JNI callbacks
// Signature: registerPlugin()V
// ─────────────────────────────────────────────────────────────────────────────
extern "C" JNIEXPORT void JNICALL
Java_com_kanmongo_app_LlamaPlugin_registerPlugin(JNIEnv* env, jobject thiz) {
    if (g_plugin_obj) {
        env->DeleteGlobalRef(g_plugin_obj);
        g_plugin_obj = nullptr;
    }
    g_plugin_obj = env->NewGlobalRef(thiz);

    jclass cls = env->GetObjectClass(thiz);
    // Method signature for emitEventFromNative:
    // (Ljava/lang/String;Ljava/lang/String;IIIJJDLjava/lang/String;I)V
    g_emit_method = env->GetMethodID(cls, "emitEventFromNative",
        "(Ljava/lang/String;Ljava/lang/String;IIIJJDLjava/lang/String;I)V");
    env->DeleteLocalRef(cls);

    if (!g_emit_method) {
        LOGE("registerPlugin: cannot find emitEventFromNative method");
    } else {
        LOGI("registerPlugin: emitEventFromNative registered OK");
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// nativeLoadModel
// ─────────────────────────────────────────────────────────────────────────────
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

    LOGI("nativeLoadModel: path=%s ctx=%d gpu=%d batch=%d threads=%d flash=%d mlock=%d rope=%.2f/%.2f",
         path.c_str(), (int)contextSize, (int)gpuLayers,
         (int)nBatch, (int)nThreads, (int)useFlashAttn,
         (int)memLock, (float)ropeBase, (float)ropeScale);

    std::lock_guard<std::mutex> lk(g_state.modelMutex);

    // Clear any existing model
    if (g_state.isLoaded()) {
        LOGI("nativeLoadModel: releasing previous model");
        g_state.shouldStop = true;
        g_state.clear();
        g_state.shouldStop = false;
    }

    // Model params
    auto mparams = llama_model_default_params();
    mparams.n_gpu_layers = (int)gpuLayers;
    mparams.use_mlock    = (bool)memLock;
    mparams.use_mmap     = false;  // FIX: mmap=true menyebabkan SIGBUS di Android internal storage

    // Emit initial loading progress
    bool nd = false;
    JNIEnv* cbEnv = jni_attach(nd);
    if (cbEnv) {
        emit_to_kotlin(cbEnv, "loading_progress", "", 0, 0, 0, 0, 0, 0.0, "", 0);
        if (nd) g_jvm->DetachCurrentThread();
    }

    g_state.model = llama_model_load_from_file(path.c_str(), mparams);
    if (!g_state.model) {
        LOGE("nativeLoadModel: llama_model_load_from_file failed");
        return 0L;
    }
    LOGI("nativeLoadModel: model loaded OK");

    // Context params
    auto cparams = llama_context_default_params();
    cparams.n_ctx      = (uint32_t)contextSize;
    cparams.n_batch    = (uint32_t)nBatch;
    cparams.n_threads  = (nThreads > 0) ? (uint32_t)nThreads : (uint32_t)optimal_threads();
    if (ropeBase  > 0.0f) cparams.rope_freq_base  = ropeBase;
    if (ropeScale > 0.0f) cparams.rope_freq_scale = ropeScale;
    // flash_attn field name may differ by version; guarded with existence check at cmake level
    // cparams.flash_attn = (bool)useFlashAttn;  // Uncomment if your llama.cpp version supports it

    g_state.ctx = llama_new_context_with_model(g_state.model, cparams);
    if (!g_state.ctx) {
        LOGE("nativeLoadModel: llama_new_context_with_model failed");
        llama_model_free(g_state.model);
        g_state.model = nullptr;
        return 0L;
    }

    LOGI("nativeLoadModel: context ready ctx=%d threads=%d",
         (int)contextSize, (int)cparams.n_threads);

    

    // Emit loading_progress=1.0 (100% complete) before model_loaded event
    {
        bool nd3 = false;
        JNIEnv* pe = jni_attach(nd3);
        if (pe) {
            emit_to_kotlin(pe, "loading_progress", "", 0, 0, 0, 0, 0, 1.0, "", 0);
            if (nd3) g_jvm->DetachCurrentThread();
        }
    }
    // Emit model_loaded event so LlamaService.dart can transition to ModelStatus.loaded
    {
        bool nd2 = false;
        JNIEnv* evEnv = jni_attach(nd2);
        if (evEnv) {
            char nameStr[256] = "unknown";
            llama_model_meta_val_str(g_state.model, "general.name", nameStr, sizeof(nameStr));
            emit_to_kotlin(evEnv, "model_loaded", nameStr, (int)contextSize,
                           0, 0, 0, 0, 0.0, "", 0);
            if (nd2) g_jvm->DetachCurrentThread();
        }
    }

    return reinterpret_cast<jlong>(g_state.model);
}

// ─────────────────────────────────────────────────────────────────────────────
// nativeReleaseModel
// ─────────────────────────────────────────────────────────────────────────────
extern "C" JNIEXPORT void JNICALL
Java_com_kanmongo_app_LlamaPlugin_nativeReleaseModel(
    JNIEnv* env, jobject thiz, jlong modelHandle)
{
    if (modelHandle == 0L) {
        LOGW("nativeReleaseModel: called with null handle");
        return;
    }

    // Stop any running generation
    g_state.shouldStop = true;

    std::lock_guard<std::mutex> lk(g_state.modelMutex);
    g_state.clear();
    g_state.shouldStop = false;

    LOGI("nativeReleaseModel: released handle=%lld", (long long)modelHandle);
}

// ─────────────────────────────────────────────────────────────────────────────
// nativeGenerateTokens
// ─────────────────────────────────────────────────────────────────────────────
extern "C" JNIEXPORT jboolean JNICALL
Java_com_kanmongo_app_LlamaPlugin_nativeGenerateTokens(
    JNIEnv* env, jobject thiz,
    jlong modelHandle, jstring jPrompt,
    jfloat temp, jfloat topP, jint topK, jint maxTokens,
    jint seq, jfloat repeatPenalty, jint seed,
    jint mirostatMode, jfloat mirostatTau, jfloat mirostatEta,
    jfloat minP, jboolean penalizeNl)
{
    if (!g_state.isLoaded()) {
        LOGE("nativeGenerateTokens: model not loaded seq=%d", (int)seq);
        return JNI_FALSE;
    }

    // Convert prompt
    const char* rawPrompt = env->GetStringUTFChars(jPrompt, nullptr);
    std::string prompt(rawPrompt);
    env->ReleaseStringUTFChars(jPrompt, rawPrompt);

    LOGI("nativeGenerateTokens: seq=%d prompt_len=%zu maxTokens=%d temp=%.2f",
         (int)seq, prompt.size(), (int)maxTokens, (float)temp);

    g_state.shouldStop   = false;
    g_state.isGenerating = true;

    // Attach JNI for callbacks
    bool needs_detach = false;
    JNIEnv* cbEnv = jni_attach(needs_detach);

    auto cleanup = [&]() {
        g_state.isGenerating = false;
        if (needs_detach && g_jvm) g_jvm->DetachCurrentThread();
    };

    if (!cbEnv) {
        LOGE("nativeGenerateTokens: failed to attach JNI env seq=%d", (int)seq);
        g_state.isGenerating = false;
        return JNI_FALSE;
    }

    // Acquire model lock (blocking — bg thread is ok)
    std::unique_lock<std::mutex> lk(g_state.modelMutex);

    if (!g_state.isLoaded()) {
        LOGE("nativeGenerateTokens: model was released before lock acquired seq=%d", (int)seq);
        emit_to_kotlin(cbEnv, "error", "", (int)seq, 0, 0, 0, 0, 0.0,
                       "Model was released before generation could start", 0);
        cleanup();
        return JNI_FALSE;
    }

    // Reset abort flag after acquiring the lock (previous gen already done)
    g_state.shouldStop = false;

    llama_context* ctx   = g_state.ctx;
    llama_model*   model = g_state.model;
    const llama_vocab* vocab = llama_model_get_vocab(model);

    // ── 1. Tokenize ───────────────────────────────────────────────────────────
    std::vector<llama_token> promptToks(prompt.size() + 64);
    int nPrompt = llama_tokenize(vocab,
        prompt.c_str(), (int32_t)prompt.size(),
        promptToks.data(), (int32_t)promptToks.size(),
        true, true);
    if (nPrompt < 0) {
        promptToks.resize(-nPrompt + 8);
        nPrompt = llama_tokenize(vocab,
            prompt.c_str(), (int32_t)prompt.size(),
            promptToks.data(), (int32_t)promptToks.size(),
            true, true);
    }
    if (nPrompt <= 0) {
        LOGE("nativeGenerateTokens: tokenization failed seq=%d", (int)seq);
        emit_to_kotlin(cbEnv, "error", "", (int)seq, 0, 0, 0, 0, 0.0,
                       "Tokenization failed", 0);
        cleanup();
        return JNI_FALSE;
    }
    promptToks.resize(nPrompt);

    // Truncate from the front if prompt is too long
    uint32_t ctxSize = llama_n_ctx(ctx);
    if ((uint32_t)nPrompt >= ctxSize - 64) {
        int keep = (int)ctxSize - 64 - (int)maxTokens;
        if (keep < 32) keep = 32;
        int skip = nPrompt - keep;
        if (skip > 0 && skip < nPrompt) {
            promptToks.erase(promptToks.begin(), promptToks.begin() + skip);
            nPrompt = (int)promptToks.size();
            LOGW("Prompt truncated: removed %d tokens from front, remaining=%d", skip, nPrompt);
        } else {
            char msg[256];
            snprintf(msg, sizeof(msg),
                "Prompt too long (%d tokens, ctx=%u)", nPrompt, ctxSize);
            LOGE("%s seq=%d", msg, (int)seq);
            emit_to_kotlin(cbEnv, "error", "", (int)seq, 0, 0, 0, 0, 0.0, msg, 0);
            cleanup();
            return JNI_FALSE;
        }
    }

    // ── 2. Clear KV cache (Memory V2 API — llama.cpp b10350+) ────────────────
    llama_memory_clear(llama_get_memory(ctx), true);

    // ── 3. Build sampler chain ────────────────────────────────────────────────
    auto sparams = llama_sampler_chain_default_params();
    sparams.no_perf = true;
    llama_sampler* sampler = llama_sampler_chain_init(sparams);

    // Temp
    llama_sampler_chain_add(sampler, llama_sampler_init_temp((float)temp));
    // Top-P
    llama_sampler_chain_add(sampler, llama_sampler_init_top_p((float)topP, 1));
    // Top-K
    llama_sampler_chain_add(sampler, llama_sampler_init_top_k((int)topK));
    // Min-P
    llama_sampler_chain_add(sampler, llama_sampler_init_min_p((float)minP, 1));
    // Penalties
    llama_sampler_chain_add(sampler,
        llama_sampler_init_penalties(
            64,                    // last_n tokens to penalize
            (float)repeatPenalty,  // repeat penalty
            0.0f,                  // freq penalty
            0.0f                   // present penalty (replaces penalize_nl + ignore_eos removed in new API)
        ));
    // Mirostat
    int nVocab = llama_vocab_n_tokens(vocab);
    if (mirostatMode == 1) {
        llama_sampler_chain_add(sampler,
            llama_sampler_init_mirostat(
                nVocab, (uint32_t)seed,
                (float)mirostatTau, (float)mirostatEta, 100));
    } else if (mirostatMode == 2) {
        llama_sampler_chain_add(sampler,
            llama_sampler_init_mirostat_v2(
                (uint32_t)seed, (float)mirostatTau, (float)mirostatEta));
    }
    // Distribution (final sampling)
    llama_sampler_chain_add(sampler,
        llama_sampler_init_dist((uint32_t)seed));

    g_state.sampler = sampler;

    // ── 4. Prefill prompt tokens ──────────────────────────────────────────────
    auto t0 = std::chrono::steady_clock::now();

    {
        llama_batch batch = llama_batch_get_one(promptToks.data(), nPrompt);
        if (llama_decode(ctx, batch) != 0) {
            LOGE("nativeGenerateTokens: prefill failed seq=%d", (int)seq);
            llama_sampler_free(sampler);
            g_state.sampler = nullptr;
            emit_to_kotlin(cbEnv, "error", "", (int)seq, 0, 0, 0, 0, 0.0,
                           "Prefill failed — try reducing context size", 0);
            cleanup();
            return JNI_FALSE;
        }
    }

    auto t1 = std::chrono::steady_clock::now();
    long long promptMs = std::chrono::duration_cast<std::chrono::milliseconds>(t1 - t0).count();
    LOGD("nativeGenerateTokens: prefill %d tokens in %lldms seq=%d",
         nPrompt, promptMs, (int)seq);

    // ── 5. Generation loop ────────────────────────────────────────────────────
    char piece[512];
    int  nEval     = 0;
    bool hitError  = false;

    while (nEval < (int)maxTokens && !g_state.shouldStop) {
        llama_token tok = llama_sampler_sample(sampler, ctx, -1);

        if (llama_vocab_is_eog(vocab, tok)) {
            LOGD("nativeGenerateTokens: EOG at pos=%d seq=%d", nEval, (int)seq);
            break;
        }

        int pl = llama_token_to_piece(vocab, tok, piece, (int)sizeof(piece) - 1, 0, false);
        if (pl > 0) {
            piece[pl] = '\0';
            emit_to_kotlin(cbEnv, "token", piece, (int)seq, 0, 0, 0, 0, 0.0, "", 0);
        }

        llama_sampler_accept(sampler, tok);

        llama_batch b = llama_batch_get_one(&tok, 1);
        if (llama_decode(ctx, b) != 0) {
            LOGW("nativeGenerateTokens: decode failed at pos=%d seq=%d", nEval, (int)seq);
            hitError = true;
            break;
        }
        nEval++;
    }

    // ── 6. Free sampler ───────────────────────────────────────────────────────
    llama_sampler_free(sampler);
    g_state.sampler = nullptr;

    auto t2 = std::chrono::steady_clock::now();
    long long evalMs = std::chrono::duration_cast<std::chrono::milliseconds>(t2 - t1).count();
    double tps = (evalMs > 0) ? (double)nEval / ((double)evalMs / 1000.0) : 0.0;

    LOGI("nativeGenerateTokens: done nEval=%d promptMs=%lld evalMs=%lld tps=%.2f seq=%d",
         nEval, promptMs, evalMs, tps, (int)seq);

    if (hitError) {
        emit_to_kotlin(cbEnv, "error", "", (int)seq, nPrompt, nEval,
                       promptMs, evalMs, tps,
                       "Decode error during generation", 0);
    } else {
        // Emit "done" event with metrics
        emit_to_kotlin(cbEnv, "done", "", (int)seq, nPrompt, nEval,
                       promptMs, evalMs, tps, "", 0);
    }

    cleanup();
    return hitError ? JNI_FALSE : JNI_TRUE;
}

// ─────────────────────────────────────────────────────────────────────────────
// nativeStopGeneration
// ─────────────────────────────────────────────────────────────────────────────
extern "C" JNIEXPORT void JNICALL
Java_com_kanmongo_app_LlamaPlugin_nativeStopGeneration(
    JNIEnv* env, jobject thiz, jlong modelHandle)
{
    g_state.shouldStop = true;
    LOGI("nativeStopGeneration: stop requested handle=%lld", (long long)modelHandle);
}

// ─────────────────────────────────────────────────────────────────────────────
// nativeGetModelInfo — loads vocab-only, extracts metadata, returns JSON
// ─────────────────────────────────────────────────────────────────────────────
extern "C" JNIEXPORT jstring JNICALL
Java_com_kanmongo_app_LlamaPlugin_nativeGetModelInfo(
    JNIEnv* env, jobject thiz, jstring jPath)
{
    const char* rawPath = env->GetStringUTFChars(jPath, nullptr);
    std::string path(rawPath);
    env->ReleaseStringUTFChars(jPath, rawPath);

    LOGI("nativeGetModelInfo: path=%s", path.c_str());

    // Load model in vocab-only mode (fast — no weights)
    auto mparams = llama_model_default_params();
    mparams.n_gpu_layers = 0;
    mparams.vocab_only   = true;

    llama_model* tmpModel = llama_model_load_from_file(path.c_str(), mparams);
    if (!tmpModel) {
        LOGE("nativeGetModelInfo: failed to load model for info");
        return env->NewStringUTF(
            "{\"name\":\"unknown\",\"arch\":\"unknown\",\"contextLength\":0,\"paramCount\":0}");
    }

    // Extract metadata
    char buf[512];
    std::string name = "unknown";
    std::string arch = "unknown";
    long long   ctxLen    = 0;
    long long   paramCount = 0;

    auto getMeta = [&](const char* key, std::string& out) {
        int ret = llama_model_meta_val_str(tmpModel, key, buf, sizeof(buf));
        if (ret >= 0) out = std::string(buf, (size_t)std::min(ret, (int)(sizeof(buf)-1)));
    };

    getMeta("general.name",          name);
    getMeta("general.architecture",  arch);

    int ret = llama_model_meta_val_str(tmpModel, "llama.context_length", buf, sizeof(buf));
    if (ret >= 0) ctxLen = atoll(buf);

    // Estimate param count from tensor info if available
    paramCount = (long long)llama_model_n_params(tmpModel);

    llama_model_free(tmpModel);

    // Build JSON
    std::ostringstream json;
    json << "{"
         << "\"name\":\"" << name << "\","
         << "\"arch\":\"" << arch << "\","
         << "\"contextLength\":" << ctxLen << ","
         << "\"paramCount\":" << paramCount
         << "}";

    LOGI("nativeGetModelInfo: result=%s", json.str().c_str());
    return env->NewStringUTF(json.str().c_str());
}

// ─────────────────────────────────────────────────────────────────────────────
// nativeIsReady
// ─────────────────────────────────────────────────────────────────────────────
extern "C" JNIEXPORT jboolean JNICALL
Java_com_kanmongo_app_LlamaPlugin_nativeIsReady(
    JNIEnv* env, jobject thiz, jlong modelHandle)
{
    return (jboolean)(g_state.isLoaded() && !g_state.isGenerating.load());
}

// ─────────────────────────────────────────────────────────────────────────────
// nativeGetTokenCount
// ─────────────────────────────────────────────────────────────────────────────
extern "C" JNIEXPORT jint JNICALL
Java_com_kanmongo_app_LlamaPlugin_nativeGetTokenCount(
    JNIEnv* env, jobject thiz, jlong modelHandle, jstring jText)
{
    if (!g_state.isLoaded()) {
        LOGE("nativeGetTokenCount: model not loaded");
        return -1;
    }

    const char* rawText = env->GetStringUTFChars(jText, nullptr);
    std::string text(rawText);
    env->ReleaseStringUTFChars(jText, rawText);

    const llama_vocab* vocab = llama_model_get_vocab(g_state.model);
    std::vector<llama_token> toks(text.size() + 16);
    int n = llama_tokenize(vocab,
        text.c_str(), (int32_t)text.size(),
        toks.data(), (int32_t)toks.size(),
        false, false);

    if (n < 0) {
        // Retry with correct buffer size
        toks.resize(-n + 4);
        n = llama_tokenize(vocab,
            text.c_str(), (int32_t)text.size(),
            toks.data(), (int32_t)toks.size(),
            false, false);
    }

    if (n < 0) {
        LOGE("nativeGetTokenCount: tokenization failed");
        return -1;
    }
    return (jint)n;
}

// ─────────────────────────────────────────────────────────────────────────────
// nativeGetAvailableMemoryMb
// ─────────────────────────────────────────────────────────────────────────────
extern "C" JNIEXPORT jint JNICALL
Java_com_kanmongo_app_LlamaPlugin_nativeGetAvailableMemoryMb(
    JNIEnv* env, jobject thiz)
{
    return (jint)read_mem_available_mb();
}
