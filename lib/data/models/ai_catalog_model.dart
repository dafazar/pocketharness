// lib/data/models/ai_catalog_model.dart
// KanMon GO — AI Model Catalog Data
// Daftar lengkap model AI yang bisa dijalankan di Android
// =============================================================================

enum ModelVariant {
  standard,    // Model resmi/normal dengan safety filter
  uncensored,  // Fine-tune tanpa safety filter (legal, dari komunitas)
  reasoning,   // Dioptimalkan untuk penalaran & logika
  coding,      // Dioptimalkan untuk kode
  multilingual,// Dioptimalkan untuk banyak bahasa
  vision,      // Support input gambar
  tiny,        // Ultra ringan < 500MB
}

enum ModelSize { tiny, small, medium, large, xlarge }
enum ModelLicense { mit, apache2, llama, gemma, qwen, deepseek, proprietary, other }
enum ModelLang { indonesian, english, multilingual, chinese, japanese }

class CatalogModel {
  final String id;
  final String name;
  final String maker;          // Google, Meta, Microsoft, dll
  final String description;
  final String sizeStr;        // "~650MB"
  final int sizeMb;            // angka MB untuk filter
  final String ramStr;         // "2GB+"
  final int ramGb;             // angka GB untuk filter
  final String format;         // GGUF, TFLite, ONNX
  final String downloadUrl;
  final String huggingFaceUrl; // untuk buka di browser
  final List<ModelVariant> variants;
  final ModelSize sizeCategory;
  final ModelLicense license;
  final List<ModelLang> languages;
  final int popularityScore;   // 1-100
  final String emoji;
  final bool isRecommended;
  final List<String> tags;     // ["chat", "coding", "reasoning", dll]

  const CatalogModel({
    required this.id,
    required this.name,
    required this.maker,
    required this.description,
    required this.sizeStr,
    required this.sizeMb,
    required this.ramStr,
    required this.ramGb,
    required this.format,
    required this.downloadUrl,
    required this.huggingFaceUrl,
    required this.variants,
    required this.sizeCategory,
    required this.license,
    required this.languages,
    required this.popularityScore,
    this.emoji = '🤖',
    this.isRecommended = false,
    this.tags = const [],
  });
}

// ═════════════════════════════════════════════════════════════════════════════
// KATALOG LENGKAP — 50+ Model AI untuk Android
// ═════════════════════════════════════════════════════════════════════════════
const List<CatalogModel> kAiCatalog = [

  // ══════════════════════════════════════════════════════════════════════════
  // GOOGLE — GEMMA SERIES (TFLite/.task — paling stabil di Android)
  // ══════════════════════════════════════════════════════════════════════════

  CatalogModel(
    id: 'gemma3-1b-tflite',
    name: 'Gemma 3 1B IT',
    maker: 'Google',
    description: 'Model ringan terbaik dari Google. Stabil di semua HP Android. Format .task dioptimalkan untuk MediaPipe.',
    sizeStr: '~650MB', sizeMb: 650,
    ramStr: '2GB+', ramGb: 2,
    format: 'TFLite/.task',
    downloadUrl: 'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/gemma3-1b-it-int4.task',
    huggingFaceUrl: 'https://huggingface.co/litert-community/Gemma3-1B-IT',
    variants: [ModelVariant.standard, ModelVariant.multilingual],
    sizeCategory: ModelSize.small,
    license: ModelLicense.gemma,
    languages: [ModelLang.english, ModelLang.multilingual],
    popularityScore: 95,
    emoji: '💎',
    isRecommended: true,
    tags: ['chat', 'general', 'stable', 'google'],
  ),

  CatalogModel(
    id: 'gemma2-2b-tflite',
    name: 'Gemma 2 2B IT',
    maker: 'Google',
    description: 'Generasi sebelumnya Gemma. Lebih besar dari 1B, kualitas lebih baik untuk pertanyaan kompleks.',
    sizeStr: '~1.1GB', sizeMb: 1100,
    ramStr: '3GB+', ramGb: 3,
    format: 'TFLite/.task',
    downloadUrl: 'https://huggingface.co/litert-community/Gemma2-2B-IT/resolve/main/gemma2-2b-it-cpu-int4.task',
    huggingFaceUrl: 'https://huggingface.co/litert-community/Gemma2-2B-IT',
    variants: [ModelVariant.standard],
    sizeCategory: ModelSize.medium,
    license: ModelLicense.gemma,
    languages: [ModelLang.english, ModelLang.multilingual],
    popularityScore: 82,
    emoji: '💎',
    tags: ['chat', 'general', 'google'],
  ),

  // ══════════════════════════════════════════════════════════════════════════
  // META — LLAMA SERIES (GGUF)
  // ══════════════════════════════════════════════════════════════════════════

  CatalogModel(
    id: 'llama32-1b-gguf',
    name: 'Llama 3.2 1B Instruct',
    maker: 'Meta',
    description: 'Model terbaru Meta untuk perangkat mobile. Cepat dan efisien untuk HP mid-range.',
    sizeStr: '~800MB', sizeMb: 800,
    ramStr: '3GB+', ramGb: 3,
    format: 'GGUF',
    downloadUrl: 'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf',
    huggingFaceUrl: 'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF',
    variants: [ModelVariant.standard],
    sizeCategory: ModelSize.small,
    license: ModelLicense.llama,
    languages: [ModelLang.english, ModelLang.multilingual],
    popularityScore: 88,
    emoji: '🦙',
    isRecommended: true,
    tags: ['chat', 'meta', 'fast'],
  ),

  CatalogModel(
    id: 'llama32-3b-gguf',
    name: 'Llama 3.2 3B Instruct',
    maker: 'Meta',
    description: 'Versi 3B lebih pintar dari 1B, cocok HP dengan RAM 4GB+.',
    sizeStr: '~2GB', sizeMb: 2000,
    ramStr: '4GB+', ramGb: 4,
    format: 'GGUF',
    downloadUrl: 'https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf',
    huggingFaceUrl: 'https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF',
    variants: [ModelVariant.standard],
    sizeCategory: ModelSize.medium,
    license: ModelLicense.llama,
    languages: [ModelLang.english, ModelLang.multilingual],
    popularityScore: 85,
    emoji: '🦙',
    tags: ['chat', 'meta'],
  ),

  CatalogModel(
    id: 'llama31-8b-gguf',
    name: 'Llama 3.1 8B Instruct',
    maker: 'Meta',
    description: 'Kualitas tinggi untuk HP flagship. Salah satu open-source terbaik untuk kemampuan umum.',
    sizeStr: '~4.7GB', sizeMb: 4700,
    ramStr: '8GB+', ramGb: 8,
    format: 'GGUF',
    downloadUrl: 'https://huggingface.co/bartowski/Meta-Llama-3.1-8B-Instruct-GGUF/resolve/main/Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf',
    huggingFaceUrl: 'https://huggingface.co/bartowski/Meta-Llama-3.1-8B-Instruct-GGUF',
    variants: [ModelVariant.standard],
    sizeCategory: ModelSize.large,
    license: ModelLicense.llama,
    languages: [ModelLang.english, ModelLang.multilingual],
    popularityScore: 90,
    emoji: '🦙',
    tags: ['chat', 'meta', 'powerful'],
  ),

  // ══════════════════════════════════════════════════════════════════════════
  // META LLAMA — UNCENSORED (fine-tune komunitas, legal)
  // ══════════════════════════════════════════════════════════════════════════

  CatalogModel(
    id: 'dolphin-llama3-8b-gguf',
    name: 'Dolphin 2.9 Llama3 8B',
    maker: 'Cognitive Computations',
    description: 'Fine-tune Llama3 tanpa safety filter. Menjawab pertanyaan apa saja tanpa penolakan. Populer untuk developer & riset.',
    sizeStr: '~4.7GB', sizeMb: 4700,
    ramStr: '8GB+', ramGb: 8,
    format: 'GGUF',
    downloadUrl: 'https://huggingface.co/cognitivecomputations/dolphin-2.9-llama3-8b-GGUF/resolve/main/dolphin-2.9-llama3-8b.Q4_K_M.gguf',
    huggingFaceUrl: 'https://huggingface.co/cognitivecomputations/dolphin-2.9-llama3-8b-GGUF',
    variants: [ModelVariant.uncensored],
    sizeCategory: ModelSize.large,
    license: ModelLicense.llama,
    languages: [ModelLang.english, ModelLang.multilingual],
    popularityScore: 87,
    emoji: '🐬',
    tags: ['uncensored', 'chat', 'no-filter'],
  ),

  CatalogModel(
    id: 'dolphin-llama32-1b-gguf',
    name: 'Dolphin Llama3.2 1B',
    maker: 'Cognitive Computations',
    description: 'Versi ringan Dolphin berbasis Llama 3.2 1B. Uncensored, cocok untuk HP mid-range.',
    sizeStr: '~800MB', sizeMb: 800,
    ramStr: '3GB+', ramGb: 3,
    format: 'GGUF',
    downloadUrl: 'https://huggingface.co/cognitivecomputations/dolphin-2.9.4-llama3.2-1b-gguf/resolve/main/dolphin-2.9.4-llama3.2-1b-Q4_K_M.gguf',
    huggingFaceUrl: 'https://huggingface.co/cognitivecomputations/dolphin-2.9.4-llama3.2-1b-gguf',
    variants: [ModelVariant.uncensored, ModelVariant.tiny],
    sizeCategory: ModelSize.small,
    license: ModelLicense.llama,
    languages: [ModelLang.english, ModelLang.multilingual],
    popularityScore: 78,
    emoji: '🐬',
    tags: ['uncensored', 'lightweight', 'no-filter'],
  ),

  CatalogModel(
    id: 'hermes3-llama31-8b-gguf',
    name: 'Hermes 3 Llama 3.1 8B',
    maker: 'NousResearch',
    description: 'Fine-tune premium dari NousResearch. Sangat pintar untuk percakapan kompleks dan analisis.',
    sizeStr: '~4.7GB', sizeMb: 4700,
    ramStr: '8GB+', ramGb: 8,
    format: 'GGUF',
    downloadUrl: 'https://huggingface.co/NousResearch/Hermes-3-Llama-3.1-8B-GGUF/resolve/main/Hermes-3-Llama-3.1-8B.Q4_K_M.gguf',
    huggingFaceUrl: 'https://huggingface.co/NousResearch/Hermes-3-Llama-3.1-8B-GGUF',
    variants: [ModelVariant.uncensored, ModelVariant.reasoning],
    sizeCategory: ModelSize.large,
    license: ModelLicense.llama,
    languages: [ModelLang.english, ModelLang.multilingual],
    popularityScore: 85,
    emoji: '⚡',
    tags: ['uncensored', 'reasoning', 'smart'],
  ),

  // ══════════════════════════════════════════════════════════════════════════
  // MICROSOFT — PHI SERIES (GGUF)
  // ══════════════════════════════════════════════════════════════════════════

  CatalogModel(
    id: 'phi4-mini-gguf',
    name: 'Phi-4 Mini Instruct',
    maker: 'Microsoft',
    description: 'Model terbaru Microsoft. Sangat pintar untuk ukurannya. Terbaik untuk penalaran & coding.',
    sizeStr: '~2.3GB', sizeMb: 2300,
    ramStr: '6GB+', ramGb: 6,
    format: 'GGUF',
    downloadUrl: 'https://huggingface.co/bartowski/phi-4-mini-instruct-GGUF/resolve/main/phi-4-mini-instruct-Q4_K_M.gguf',
    huggingFaceUrl: 'https://huggingface.co/bartowski/phi-4-mini-instruct-GGUF',
    variants: [ModelVariant.standard, ModelVariant.reasoning, ModelVariant.coding],
    sizeCategory: ModelSize.medium,
    license: ModelLicense.mit,
    languages: [ModelLang.english, ModelLang.multilingual],
    popularityScore: 88,
    emoji: '🔷',
    isRecommended: true,
    tags: ['reasoning', 'coding', 'microsoft', 'smart'],
  ),

  CatalogModel(
    id: 'phi3-mini-gguf',
    name: 'Phi-3 Mini 3.8B',
    maker: 'Microsoft',
    description: 'Generasi sebelumnya Phi. Lebih ringan, cocok HP mid-range dengan kualitas baik.',
    sizeStr: '~2.2GB', sizeMb: 2200,
    ramStr: '4GB+', ramGb: 4,
    format: 'GGUF',
    downloadUrl: 'https://huggingface.co/bartowski/Phi-3-mini-4k-instruct-GGUF/resolve/main/Phi-3-mini-4k-instruct-Q4_K_M.gguf',
    huggingFaceUrl: 'https://huggingface.co/bartowski/Phi-3-mini-4k-instruct-GGUF',
    variants: [ModelVariant.standard, ModelVariant.reasoning],
    sizeCategory: ModelSize.medium,
    license: ModelLicense.mit,
    languages: [ModelLang.english, ModelLang.multilingual],
    popularityScore: 82,
    emoji: '🔷',
    tags: ['reasoning', 'microsoft'],
  ),

  // ══════════════════════════════════════════════════════════════════════════
  // ALIBABA — QWEN SERIES (GGUF) — BAGUS UNTUK BAHASA ASIA
  // ══════════════════════════════════════════════════════════════════════════

  CatalogModel(
    id: 'qwen3-06b-gguf',
    name: 'Qwen3 0.6B',
    maker: 'Alibaba',
    description: 'Ultra ringan, sangat bagus untuk Bahasa Indonesia & Asia. Cocok semua HP.',
    sizeStr: '~500MB', sizeMb: 500,
    ramStr: '1.5GB+', ramGb: 2,
    format: 'GGUF',
    downloadUrl: 'https://huggingface.co/Qwen/Qwen3-0.6B-GGUF/resolve/main/qwen3-0.6b-q4_k_m.gguf',
    huggingFaceUrl: 'https://huggingface.co/Qwen/Qwen3-0.6B-GGUF',
    variants: [ModelVariant.standard, ModelVariant.multilingual, ModelVariant.tiny],
    sizeCategory: ModelSize.tiny,
    license: ModelLicense.apache2,
    languages: [ModelLang.indonesian, ModelLang.chinese, ModelLang.multilingual],
    popularityScore: 80,
    emoji: '🌐',
    isRecommended: true,
    tags: ['indonesian', 'multilingual', 'tiny', 'alibaba'],
  ),

  CatalogModel(
    id: 'qwen3-1b-gguf',
    name: 'Qwen3 1.7B',
    maker: 'Alibaba',
    description: 'Versi lebih besar Qwen3. Lebih pintar untuk Bahasa Indonesia dan teks Asia.',
    sizeStr: '~1.1GB', sizeMb: 1100,
    ramStr: '3GB+', ramGb: 3,
    format: 'GGUF',
    downloadUrl: 'https://huggingface.co/Qwen/Qwen3-1.7B-GGUF/resolve/main/qwen3-1.7b-q4_k_m.gguf',
    huggingFaceUrl: 'https://huggingface.co/Qwen/Qwen3-1.7B-GGUF',
    variants: [ModelVariant.standard, ModelVariant.multilingual],
    sizeCategory: ModelSize.small,
    license: ModelLicense.apache2,
    languages: [ModelLang.indonesian, ModelLang.chinese, ModelLang.multilingual],
    popularityScore: 82,
    emoji: '🌐',
    tags: ['indonesian', 'multilingual', 'alibaba'],
  ),

  CatalogModel(
    id: 'qwen25-7b-gguf',
    name: 'Qwen 2.5 7B Instruct',
    maker: 'Alibaba',
    description: 'Kualitas tinggi untuk Bahasa Asia. Sangat bagus untuk terjemahan dan pemahaman konteks.',
    sizeStr: '~4.4GB', sizeMb: 4400,
    ramStr: '8GB+', ramGb: 8,
    format: 'GGUF',
    downloadUrl: 'https://huggingface.co/bartowski/Qwen2.5-7B-Instruct-GGUF/resolve/main/Qwen2.5-7B-Instruct-Q4_K_M.gguf',
    huggingFaceUrl: 'https://huggingface.co/bartowski/Qwen2.5-7B-Instruct-GGUF',
    variants: [ModelVariant.standard, ModelVariant.multilingual],
    sizeCategory: ModelSize.large,
    license: ModelLicense.apache2,
    languages: [ModelLang.indonesian, ModelLang.chinese, ModelLang.japanese, ModelLang.multilingual],
    popularityScore: 88,
    emoji: '🌐',
    tags: ['indonesian', 'multilingual', 'powerful'],
  ),

  CatalogModel(
    id: 'qwen25-coder-1b-gguf',
    name: 'Qwen 2.5 Coder 1.5B',
    maker: 'Alibaba',
    description: 'Dioptimalkan untuk coding. Mengerti 80+ bahasa pemrograman, bagus untuk debug & review code.',
    sizeStr: '~1GB', sizeMb: 1000,
    ramStr: '3GB+', ramGb: 3,
    format: 'GGUF',
    downloadUrl: 'https://huggingface.co/bartowski/Qwen2.5-Coder-1.5B-Instruct-GGUF/resolve/main/Qwen2.5-Coder-1.5B-Instruct-Q4_K_M.gguf',
    huggingFaceUrl: 'https://huggingface.co/bartowski/Qwen2.5-Coder-1.5B-Instruct-GGUF',
    variants: [ModelVariant.coding],
    sizeCategory: ModelSize.small,
    license: ModelLicense.apache2,
    languages: [ModelLang.english, ModelLang.multilingual],
    popularityScore: 84,
    emoji: '💻',
    tags: ['coding', 'programming', 'developer'],
  ),

  // ══════════════════════════════════════════════════════════════════════════
  // DEEPSEEK — REASONING (GGUF)
  // ══════════════════════════════════════════════════════════════════════════

  CatalogModel(
    id: 'deepseek-r1-15b-gguf',
    name: 'DeepSeek R1 1.5B',
    maker: 'DeepSeek',
    description: 'Model reasoning terbaik untuk ukurannya. Bagus untuk soal matematika, logika, dan analisis.',
    sizeStr: '~1.1GB', sizeMb: 1100,
    ramStr: '3GB+', ramGb: 3,
    format: 'GGUF',
    downloadUrl: 'https://huggingface.co/bartowski/DeepSeek-R1-Distill-Qwen-1.5B-GGUF/resolve/main/DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf',
    huggingFaceUrl: 'https://huggingface.co/bartowski/DeepSeek-R1-Distill-Qwen-1.5B-GGUF',
    variants: [ModelVariant.reasoning],
    sizeCategory: ModelSize.small,
    license: ModelLicense.mit,
    languages: [ModelLang.english, ModelLang.multilingual],
    popularityScore: 86,
    emoji: '🧠',
    isRecommended: true,
    tags: ['reasoning', 'math', 'logic', 'deepseek'],
  ),

  CatalogModel(
    id: 'deepseek-r1-7b-gguf',
    name: 'DeepSeek R1 7B',
    maker: 'DeepSeek',
    description: 'Versi lebih besar DeepSeek R1. Reasoning sangat kuat, setara GPT-4 untuk soal teknis.',
    sizeStr: '~4.5GB', sizeMb: 4500,
    ramStr: '8GB+', ramGb: 8,
    format: 'GGUF',
    downloadUrl: 'https://huggingface.co/bartowski/DeepSeek-R1-Distill-Qwen-7B-GGUF/resolve/main/DeepSeek-R1-Distill-Qwen-7B-Q4_K_M.gguf',
    huggingFaceUrl: 'https://huggingface.co/bartowski/DeepSeek-R1-Distill-Qwen-7B-GGUF',
    variants: [ModelVariant.reasoning],
    sizeCategory: ModelSize.large,
    license: ModelLicense.mit,
    languages: [ModelLang.english, ModelLang.multilingual],
    popularityScore: 90,
    emoji: '🧠',
    tags: ['reasoning', 'math', 'logic', 'powerful'],
  ),

  // ══════════════════════════════════════════════════════════════════════════
  // MISTRAL (GGUF)
  // ══════════════════════════════════════════════════════════════════════════

  CatalogModel(
    id: 'mistral-7b-gguf',
    name: 'Mistral 7B Instruct v0.3',
    maker: 'Mistral AI',
    description: 'Salah satu model 7B terbaik. Cepat, akurat, dan efisien untuk berbagai tugas.',
    sizeStr: '~4.4GB', sizeMb: 4400,
    ramStr: '8GB+', ramGb: 8,
    format: 'GGUF',
    downloadUrl: 'https://huggingface.co/bartowski/Mistral-7B-Instruct-v0.3-GGUF/resolve/main/Mistral-7B-Instruct-v0.3-Q4_K_M.gguf',
    huggingFaceUrl: 'https://huggingface.co/bartowski/Mistral-7B-Instruct-v0.3-GGUF',
    variants: [ModelVariant.standard],
    sizeCategory: ModelSize.large,
    license: ModelLicense.apache2,
    languages: [ModelLang.english, ModelLang.multilingual],
    popularityScore: 87,
    emoji: '💨',
    tags: ['chat', 'mistral', 'fast'],
  ),

  CatalogModel(
    id: 'openhermes-mistral-7b-gguf',
    name: 'OpenHermes 2.5 Mistral 7B',
    maker: 'NousResearch',
    description: 'Fine-tune Mistral yang sangat bagus. Tidak ada safety filter, sangat responsif dan cerdas.',
    sizeStr: '~4.4GB', sizeMb: 4400,
    ramStr: '8GB+', ramGb: 8,
    format: 'GGUF',
    downloadUrl: 'https://huggingface.co/TheBloke/OpenHermes-2.5-Mistral-7B-GGUF/resolve/main/openhermes-2.5-mistral-7b.Q4_K_M.gguf',
    huggingFaceUrl: 'https://huggingface.co/TheBloke/OpenHermes-2.5-Mistral-7B-GGUF',
    variants: [ModelVariant.uncensored],
    sizeCategory: ModelSize.large,
    license: ModelLicense.apache2,
    languages: [ModelLang.english, ModelLang.multilingual],
    popularityScore: 83,
    emoji: '💨',
    tags: ['uncensored', 'chat', 'mistral'],
  ),

  CatalogModel(
    id: 'dolphin-mistral-7b-gguf',
    name: 'Dolphin 2.6 Mistral 7B',
    maker: 'Cognitive Computations',
    description: 'Dolphin berbasis Mistral. Uncensored, sangat baik untuk developer dan penggunaan bebas.',
    sizeStr: '~4.4GB', sizeMb: 4400,
    ramStr: '8GB+', ramGb: 8,
    format: 'GGUF',
    downloadUrl: 'https://huggingface.co/TheBloke/dolphin-2.6-mistral-7B-GGUF/resolve/main/dolphin-2.6-mistral-7b.Q4_K_M.gguf',
    huggingFaceUrl: 'https://huggingface.co/TheBloke/dolphin-2.6-mistral-7B-GGUF',
    variants: [ModelVariant.uncensored],
    sizeCategory: ModelSize.large,
    license: ModelLicense.apache2,
    languages: [ModelLang.english, ModelLang.multilingual],
    popularityScore: 81,
    emoji: '🐬',
    tags: ['uncensored', 'mistral', 'no-filter'],
  ),

  // ══════════════════════════════════════════════════════════════════════════
  // CODING SPECIALIST
  // ══════════════════════════════════════════════════════════════════════════

  CatalogModel(
    id: 'codellama-7b-gguf',
    name: 'CodeLlama 7B Instruct',
    maker: 'Meta',
    description: 'Dikhususkan Meta untuk coding. Mengerti Python, JS, Java, C++, dan 10+ bahasa lainnya.',
    sizeStr: '~4.4GB', sizeMb: 4400,
    ramStr: '8GB+', ramGb: 8,
    format: 'GGUF',
    downloadUrl: 'https://huggingface.co/TheBloke/CodeLlama-7B-Instruct-GGUF/resolve/main/codellama-7b-instruct.Q4_K_M.gguf',
    huggingFaceUrl: 'https://huggingface.co/TheBloke/CodeLlama-7B-Instruct-GGUF',
    variants: [ModelVariant.coding],
    sizeCategory: ModelSize.large,
    license: ModelLicense.llama,
    languages: [ModelLang.english],
    popularityScore: 82,
    emoji: '💻',
    tags: ['coding', 'programming', 'meta'],
  ),

  CatalogModel(
    id: 'starcoder2-3b-gguf',
    name: 'StarCoder2 3B',
    maker: 'Hugging Face / ServiceNow',
    description: 'Dilatih pada 600+ bahasa pemrograman. Ringan dan sangat bagus untuk code completion.',
    sizeStr: '~1.9GB', sizeMb: 1900,
    ramStr: '4GB+', ramGb: 4,
    format: 'GGUF',
    downloadUrl: 'https://huggingface.co/bartowski/starcoder2-3b-GGUF/resolve/main/starcoder2-3b-Q4_K_M.gguf',
    huggingFaceUrl: 'https://huggingface.co/bartowski/starcoder2-3b-GGUF',
    variants: [ModelVariant.coding],
    sizeCategory: ModelSize.medium,
    license: ModelLicense.apache2,
    languages: [ModelLang.english],
    popularityScore: 75,
    emoji: '⭐',
    tags: ['coding', 'programming', 'completion'],
  ),

  // ══════════════════════════════════════════════════════════════════════════
  // ULTRA RINGAN (< 500MB) — untuk HP low-end
  // ══════════════════════════════════════════════════════════════════════════

  CatalogModel(
    id: 'smollm2-360m-gguf',
    name: 'SmolLM2 360M',
    maker: 'Hugging Face',
    description: 'Ultra ringan hanya 360MB. Bisa jalan di HP RAM 1GB. Kualitas terbatas tapi tetap berfungsi.',
    sizeStr: '~220MB', sizeMb: 220,
    ramStr: '1GB+', ramGb: 1,
    format: 'GGUF',
    downloadUrl: 'https://huggingface.co/bartowski/SmolLM2-360M-Instruct-GGUF/resolve/main/SmolLM2-360M-Instruct-Q4_K_M.gguf',
    huggingFaceUrl: 'https://huggingface.co/bartowski/SmolLM2-360M-Instruct-GGUF',
    variants: [ModelVariant.tiny, ModelVariant.standard],
    sizeCategory: ModelSize.tiny,
    license: ModelLicense.apache2,
    languages: [ModelLang.english],
    popularityScore: 70,
    emoji: '🪶',
    tags: ['tiny', 'lightweight', 'low-end'],
  ),

  CatalogModel(
    id: 'smollm2-1b-gguf',
    name: 'SmolLM2 1.7B',
    maker: 'Hugging Face',
    description: 'Versi lebih besar SmolLM2. Balance antara ukuran dan kualitas untuk HP entry-level.',
    sizeStr: '~1GB', sizeMb: 1000,
    ramStr: '2GB+', ramGb: 2,
    format: 'GGUF',
    downloadUrl: 'https://huggingface.co/bartowski/SmolLM2-1.7B-Instruct-GGUF/resolve/main/SmolLM2-1.7B-Instruct-Q4_K_M.gguf',
    huggingFaceUrl: 'https://huggingface.co/bartowski/SmolLM2-1.7B-Instruct-GGUF',
    variants: [ModelVariant.tiny],
    sizeCategory: ModelSize.small,
    license: ModelLicense.apache2,
    languages: [ModelLang.english, ModelLang.multilingual],
    popularityScore: 72,
    emoji: '🪶',
    tags: ['tiny', 'lightweight'],
  ),

  // ══════════════════════════════════════════════════════════════════════════
  // MULTIMODAL / VISION (support gambar)
  // ══════════════════════════════════════════════════════════════════════════

  CatalogModel(
    id: 'moondream2-gguf',
    name: 'Moondream 2',
    maker: 'Vikhyatk',
    description: 'Model kecil yang bisa melihat gambar. Cocok untuk HP, bisa analisis foto secara offline.',
    sizeStr: '~1.7GB', sizeMb: 1700,
    ramStr: '3GB+', ramGb: 3,
    format: 'GGUF',
    downloadUrl: 'https://huggingface.co/vikhyatk/moondream2/resolve/main/moondream2-int8.mf',
    huggingFaceUrl: 'https://huggingface.co/vikhyatk/moondream2',
    variants: [ModelVariant.vision],
    sizeCategory: ModelSize.medium,
    license: ModelLicense.apache2,
    languages: [ModelLang.english],
    popularityScore: 76,
    emoji: '👁️',
    tags: ['vision', 'image', 'multimodal'],
  ),
];

// ── Helper: filter catalog ────────────────────────────────────────────────────
List<CatalogModel> filterCatalog({
  String? search,
  Set<ModelVariant>? variants,
  Set<String>? formats,
  ModelSize? maxSize,
  int? maxRamGb,
  Set<ModelLang>? languages,
  Set<ModelLicense>? licenses,
  String sortBy = 'popularity', // 'popularity', 'size_asc', 'size_desc', 'name'
}) {
  var result = kAiCatalog.toList();

  if (search != null && search.isNotEmpty) {
    final q = search.toLowerCase();
    result = result.where((m) =>
      m.name.toLowerCase().contains(q) ||
      m.maker.toLowerCase().contains(q) ||
      m.description.toLowerCase().contains(q) ||
      m.tags.any((t) => t.contains(q))
    ).toList();
  }

  if (variants != null && variants.isNotEmpty) {
    result = result.where((m) =>
      m.variants.any((v) => variants.contains(v))
    ).toList();
  }

  if (formats != null && formats.isNotEmpty) {
    result = result.where((m) =>
      formats.any((f) => m.format.toLowerCase().contains(f.toLowerCase()))
    ).toList();
  }

  if (maxSize != null) {
    result = result.where((m) =>
      m.sizeCategory.index <= maxSize.index
    ).toList();
  }

  if (maxRamGb != null) {
    result = result.where((m) => m.ramGb <= maxRamGb).toList();
  }

  if (languages != null && languages.isNotEmpty) {
    result = result.where((m) =>
      m.languages.any((l) => languages.contains(l))
    ).toList();
  }

  if (licenses != null && licenses.isNotEmpty) {
    result = result.where((m) => licenses.contains(m.license)).toList();
  }

  switch (sortBy) {
    case 'size_asc':
      result.sort((a, b) => a.sizeMb.compareTo(b.sizeMb));
    case 'size_desc':
      result.sort((a, b) => b.sizeMb.compareTo(a.sizeMb));
    case 'name':
      result.sort((a, b) => a.name.compareTo(b.name));
    default:
      result.sort((a, b) => b.popularityScore.compareTo(a.popularityScore));
  }

  return result;
}
