// llama_stub.cpp — Fallback when llama.cpp is not compiled
// Used by CMakeLists.txt when ${LLAMA_SRC}/CMakeLists.txt does not exist.
//
// ALL method signatures MUST exactly match LlamaPlugin.kt external fun declarations.
// Verified against LlamaPlugin.kt (com.kanmongo.app) as of Session 3 audit.
//
// Correct signatures:
//   nativeLoadModel(path, contextSize, gpuLayers, nBatch, nThreads,
//                   useFlashAttn, memLock, ropeBase, ropeScale) → Long (jlong)
//   nativeReleaseModel(modelHandle: Long)
//   nativeGenerateTokens(modelHandle, prompt, temp, topP, topK, maxTokens,
//                        seq, repeatPenalty, seed, mirostatMode, mirostatTau,
//                        mirostatEta, minP, penalizeNl) → Boolean
//   nativeStopGeneration(modelHandle: Long)
//   nativeGetModelInfo(path: String) → String
//   nativeIsReady(modelHandle: Long) → Boolean
//   nativeGetTokenCount(modelHandle: Long, text: String) → Int
//   nativeGetAvailableMemoryMb() → Int
//   registerPlugin()

#include <jni.h>
#include <android/log.h>

#define LOG_TAG "KanMongoLlama"
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  LOG_TAG, __VA_ARGS__)

static const char* STUB_MSG =
    "GGUF model tidak tersedia: llama.cpp belum dikompilasi.\n"
    "Jalankan: bash scripts/setup_llama.sh lalu build ulang.";

// ── JNI_OnLoad ────────────────────────────────────────────────────────────────
extern "C" JNIEXPORT jint JNICALL
JNI_OnLoad(JavaVM* vm, void* reserved) {
    LOGI("llama.cpp STUB loaded — GGUF inference disabled");
    LOGI("To enable: bash scripts/setup_llama.sh && rebuild");
    return JNI_VERSION_1_6;
}

// ── registerPlugin ────────────────────────────────────────────────────────────
extern "C" JNIEXPORT void JNICALL
Java_com_kanmongo_app_LlamaPlugin_registerPlugin(JNIEnv* env, jobject thiz) {
    LOGI("registerPlugin (STUB) — no-op");
}

// ── nativeLoadModel ───────────────────────────────────────────────────────────
extern "C" JNIEXPORT jlong JNICALL
Java_com_kanmongo_app_LlamaPlugin_nativeLoadModel(
    JNIEnv* env, jobject thiz,
    jstring path, jint contextSize, jint gpuLayers,
    jint nBatch, jint nThreads, jboolean useFlashAttn,
    jboolean memLock, jfloat ropeBase, jfloat ropeScale)
{
    LOGE("nativeLoadModel (STUB): %s", STUB_MSG);
    return 0L;
}

// ── nativeReleaseModel ────────────────────────────────────────────────────────
extern "C" JNIEXPORT void JNICALL
Java_com_kanmongo_app_LlamaPlugin_nativeReleaseModel(
    JNIEnv* env, jobject thiz, jlong modelHandle)
{
    LOGI("nativeReleaseModel (STUB): no-op, handle=%lld", (long long)modelHandle);
}

// ── nativeGenerateTokens ──────────────────────────────────────────────────────
extern "C" JNIEXPORT jboolean JNICALL
Java_com_kanmongo_app_LlamaPlugin_nativeGenerateTokens(
    JNIEnv* env, jobject thiz,
    jlong modelHandle, jstring prompt,
    jfloat temp, jfloat topP, jint topK, jint maxTokens,
    jint seq, jfloat repeatPenalty, jint seed,
    jint mirostatMode, jfloat mirostatTau, jfloat mirostatEta,
    jfloat minP, jboolean penalizeNl)
{
    LOGE("nativeGenerateTokens (STUB): %s", STUB_MSG);
    return JNI_FALSE;
}

// ── nativeStopGeneration ──────────────────────────────────────────────────────
extern "C" JNIEXPORT void JNICALL
Java_com_kanmongo_app_LlamaPlugin_nativeStopGeneration(
    JNIEnv* env, jobject thiz, jlong modelHandle)
{
    LOGI("nativeStopGeneration (STUB): no-op");
}

// ── nativeGetModelInfo ────────────────────────────────────────────────────────
extern "C" JNIEXPORT jstring JNICALL
Java_com_kanmongo_app_LlamaPlugin_nativeGetModelInfo(
    JNIEnv* env, jobject thiz, jstring path)
{
    LOGI("nativeGetModelInfo (STUB): returning stub JSON");
    return env->NewStringUTF(
        "{\"name\":\"stub\",\"arch\":\"stub\","
        "\"contextLength\":0,\"paramCount\":0,"
        "\"stub\":true}");
}

// ── nativeIsReady ─────────────────────────────────────────────────────────────
extern "C" JNIEXPORT jboolean JNICALL
Java_com_kanmongo_app_LlamaPlugin_nativeIsReady(
    JNIEnv* env, jobject thiz, jlong modelHandle)
{
    return JNI_FALSE;
}

// ── nativeGetTokenCount ───────────────────────────────────────────────────────
extern "C" JNIEXPORT jint JNICALL
Java_com_kanmongo_app_LlamaPlugin_nativeGetTokenCount(
    JNIEnv* env, jobject thiz, jlong modelHandle, jstring text)
{
    return -1;
}

// ── nativeGetAvailableMemoryMb ────────────────────────────────────────────────
extern "C" JNIEXPORT jint JNICALL
Java_com_kanmongo_app_LlamaPlugin_nativeGetAvailableMemoryMb(
    JNIEnv* env, jobject thiz)
{
    return 0;
}
