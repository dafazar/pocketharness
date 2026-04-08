
package com.example.app

object LlamaBridge {
    init { System.loadLibrary("llama_jni") }
    external fun generate(prompt: String): String
}
