
#include <jni.h>
#include <string>

extern "C"
JNIEXPORT jstring JNICALL
Java_com_example_app_LlamaBridge_generate(JNIEnv *env, jobject, jstring prompt) {
    const char *input = env->GetStringUTFChars(prompt, 0);
    std::string out = "AI (llama.cpp): ";
    out += input;
    return env->NewStringUTF(out.c_str());
}
