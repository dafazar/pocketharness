// lib/core/inference_manager.dart
// Pocket Harness — Inference Manager
// Wrapper tipis di atas OfflineAiService untuk backward compatibility.
// Semua inference nyata dilakukan oleh OfflineAiService → LlamaPlugin.kt (JNI).
// =============================================================================

import 'package:pocketharness/data/services/offline_ai_service.dart';

class InferenceManager {
  static final InferenceManager instance = InferenceManager._();
  InferenceManager._();

  bool get isRunning => OfflineAiService.instance.isGenerating;
  bool get isReady   => OfflineAiService.instance.isReady;

  Future<void> init() async {
    await OfflineAiService.instance.loadSettings();
    await OfflineAiService.instance.loadActiveModel();
  }

  Future<String> generate(String prompt) async {
    return OfflineAiService.instance.generate(prompt);
  }

  Stream<String> generateStream(String prompt) {
    return OfflineAiService.instance.chatStream(
      systemPrompt: 'Kamu adalah asisten bahasa Jepang yang membantu.',
      history:      [],
      userMessage:  prompt,
    );
  }

  Future<void> stop() async {
    await OfflineAiService.instance.stop();
  }

  void dispose() {
    // OfflineAiService adalah singleton — tidak perlu dispose manual
  }
}
