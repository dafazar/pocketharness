// llama_stub.cpp — dipakai ketika llama.cpp/ tidak ada saat build
#include <jni.h>
#include <android/log.h>
#define LOG_TAG "KanMongoLlama"
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
static const char* STUB =
    "GGUF tidak tersedia: llama.cpp belum dikompilasi.\n"
    "Jalankan: bash scripts/setup_llama.sh lalu build ulang.";
extern "C" JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM*, void*) {
    LOGE("llama.cpp STUB — GGUF disabled"); return JNI_VERSION_1_6;
}
extern "C" JNIEXPORT jboolean JNICALL
Java_com_kanmongo_app_LlamaPlugin_nativeLoadModel(JNIEnv*,jobject,jstring,jint,jint)
{ LOGE("%s", STUB); return JNI_FALSE; }

// nativeStartGeneration: signature baru pakai TokenCallback bukan GenerationCallback
extern "C" JNIEXPORT void JNICALL
Java_com_kanmongo_app_LlamaPlugin_nativeStartGeneration(
    JNIEnv* env, jobject, jstring, jint, jfloat, jfloat, jfloat, jobject cb)
{
    jclass c  = env->GetObjectClass(cb);
    jmethodID m = env->GetMethodID(c, "onError", "(Ljava/lang/String;)V");
    jstring js  = env->NewStringUTF(STUB);
    env->CallVoidMethod(cb, m, js);
    env->DeleteLocalRef(js);
    env->DeleteLocalRef(c);
}
extern "C" JNIEXPORT void     JNICALL Java_com_kanmongo_app_LlamaPlugin_nativeFreeModel(JNIEnv*,jobject){}
extern "C" JNIEXPORT void     JNICALL Java_com_kanmongo_app_LlamaPlugin_nativeStopGeneration(JNIEnv*,jobject){}
extern "C" JNIEXPORT jboolean JNICALL Java_com_kanmongo_app_LlamaPlugin_nativeIsModelLoaded(JNIEnv*,jobject){ return JNI_FALSE; }
extern "C" JNIEXPORT jstring  JNICALL Java_com_kanmongo_app_LlamaPlugin_nativeGetModelInfo(JNIEnv* env,jobject){
    return env->NewStringUTF("{\"loaded\":false,\"stub\":true}"); }
extern "C" JNIEXPORT jlong    JNICALL Java_com_kanmongo_app_LlamaPlugin_nativeGetAvailableRamMb(JNIEnv*,jobject){ return 0L; }
