// lib/core/ai/inference_isolate.dart
// KanMon GO — Inference Isolate (legacy stub, tidak digunakan aktif)
//
// Inference aktual dilakukan oleh OfflineAiService → LlamaPlugin.kt → llama.cpp JNI.
// Dart Isolate tidak bisa memanggil JNI secara langsung karena MethodChannel
// hanya tersedia di main isolate. File ini dipertahankan agar tidak ada
// import error, tetapi tidak mengandung logika inference nyata.
// =============================================================================

// Tidak ada class yang di-export dari file ini.
// Gunakan OfflineAiService.instance.chatStream() untuk inference.
