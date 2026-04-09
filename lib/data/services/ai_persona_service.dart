// lib/data/services/ai_persona_service.dart
// KanMon GO — AI Persona & System Prompt Service
//
// 3 fitur utama:
//   1. PERSONA PRESETS   — karakter AI yang bisa dipilih
//   2. CUSTOM PROMPT     — system prompt sepenuhnya bebas dari user
//   3. PARAMETER TUNING  — temperature, top-k, max tokens per AI
// =============================================================================

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kanmongo/data/services/kanmonai_system_prompt.dart';

// ── Persona preset ────────────────────────────────────────────────────────────
class AiPersona {
  final String id;
  final String name;
  final String emoji;
  final String description;
  final String systemPrompt;
  final double temperature;
  final int maxTokens;
  final bool isCustom;

  const AiPersona({
    required this.id,
    required this.name,
    required this.emoji,
    required this.description,
    required this.systemPrompt,
    this.temperature = 0.7,
    this.maxTokens   = 1024,
    this.isCustom    = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'emoji': emoji,
    'description': description, 'systemPrompt': systemPrompt,
    'temperature': temperature, 'maxTokens': maxTokens,
    'isCustom': isCustom,
  };

  factory AiPersona.fromJson(Map<String, dynamic> j) => AiPersona(
    id:           j['id'],
    name:         j['name'],
    emoji:        j['emoji'],
    description:  j['description'],
    systemPrompt: j['systemPrompt'],
    temperature:  (j['temperature'] as num?)?.toDouble() ?? 0.7,
    maxTokens:    j['maxTokens'] as int? ?? 1024,
    isCustom:     j['isCustom'] as bool? ?? false,
  );

  AiPersona copyWith({
    String? name, String? emoji, String? description,
    String? systemPrompt, double? temperature, int? maxTokens,
  }) => AiPersona(
    id: id, isCustom: isCustom,
    name:         name ?? this.name,
    emoji:        emoji ?? this.emoji,
    description:  description ?? this.description,
    systemPrompt: systemPrompt ?? this.systemPrompt,
    temperature:  temperature ?? this.temperature,
    maxTokens:    maxTokens ?? this.maxTokens,
  );
}

// ── Built-in personas ─────────────────────────────────────────────────────────
const List<AiPersona> kBuiltinPersonas = [
  AiPersona(
    id: 'kanmonai',
    name: 'KanMonAI',
    emoji: '🤖',
    description: 'KanMonAI — asisten AI full-capability (cloud + offline)',
    systemPrompt: kKanMonAIShortSystemPrompt,
    temperature: 0.7,
    maxTokens: 2048,
  ),
  AiPersona(
    id: 'kanmonai_full',
    name: 'KanMonAI Full',
    emoji: '⚡',
    description: 'KanMonAI Full — system prompt lengkap 6 session (file, media, code, routing, offline)',
    systemPrompt: kKanMonAIFullSystemPrompt,
    temperature: 0.7,
    maxTokens: 4096,
  ),
  AiPersona(
    id: 'default',
    name: 'Default',
    emoji: '💬',
    description: 'AI standar — ramah, informatif, seimbang',
    systemPrompt:
      'Kamu adalah AI Chat — asisten AI yang cerdas dan membantu. '
      'Jawab dalam Bahasa Indonesia kecuali diminta lain. '
      'Jawab ringkas, jelas, dan langsung ke inti.',
    temperature: 0.7,
    maxTokens: 1024,
  ),
  AiPersona(
    id: 'expert',
    name: 'Expert',
    emoji: '🎓',
    description: 'Ahli teknis — detail, akurat, mendalam',
    systemPrompt:
      'Kamu adalah AI Expert — ahli di semua bidang teknis dan ilmiah. '
      'Berikan jawaban yang sangat detail, akurat, dan mendalam. '
      'Gunakan terminologi teknis yang tepat. '
      'Sertakan contoh, rumus, atau kode jika relevan. '
      'Jangan sederhanakan jika tidak diminta. '
      'Jawab dalam Bahasa Indonesia.',
    temperature: 0.3,
    maxTokens: 2048,
  ),
  AiPersona(
    id: 'creative',
    name: 'Kreatif',
    emoji: '🎨',
    description: 'Penulis kreatif — imajinatif, ekspresif, bebas',
    systemPrompt:
      'Kamu adalah AI Kreatif — penulis dan seniman digital yang imajinatif. '
      'Berikan respons yang kreatif, unik, dan penuh eksplorasi. '
      'Jangan takut untuk ide-ide tidak biasa atau tidak konvensional. '
      'Ekspresikan dirimu dengan bebas dan penuh warna. '
      'Untuk menulis: gunakan gaya sastra yang kaya. '
      'Jawab dalam Bahasa Indonesia.',
    temperature: 1.0,
    maxTokens: 2048,
  ),
  AiPersona(
    id: 'coder',
    name: 'Programmer',
    emoji: '💻',
    description: 'Dev assistant — kode bersih, best practice, efisien',
    systemPrompt:
      'Kamu adalah AI Programmer — software engineer senior yang expert. '
      'Fokus pada: kode yang bersih, efisien, dan mengikuti best practice. '
      'Selalu sertakan komentar yang jelas di kode. '
      'Pertimbangkan edge cases dan error handling. '
      'Gunakan design patterns yang tepat. '
      'Prioritaskan keamanan dan performa. '
      'Jelaskan kode yang kompleks secara ringkas. '
      'Jawab dalam Bahasa Indonesia, kode dalam bahasa pemrograman yang diminta.',
    temperature: 0.2,
    maxTokens: 4096,
  ),
  AiPersona(
    id: 'analyst',
    name: 'Analis',
    emoji: '📊',
    description: 'Data analyst — faktual, terstruktur, berbasis data',
    systemPrompt:
      'Kamu adalah AI Analis — data scientist dan business analyst yang terstruktur. '
      'Selalu berikan jawaban yang: '
      '1. Berbasis fakta dan data '
      '2. Terstruktur dengan bullet points atau tabel '
      '3. Menyertakan sumber jika relevan '
      '4. Mempertimbangkan berbagai sudut pandang '
      '5. Memberikan kesimpulan yang actionable '
      'Gunakan format yang mudah dibaca. '
      'Jawab dalam Bahasa Indonesia.',
    temperature: 0.3,
    maxTokens: 2048,
  ),
  AiPersona(
    id: 'agent',
    name: 'Agent Pro',
    emoji: '⚡',
    description: 'Otonom — aktif menggunakan tools, proaktif',
    systemPrompt:
      'Kamu adalah AI Agent Pro — asisten otonom yang sangat proaktif dan kompeten. '
      'Karaktermu: '
      '- Selalu selesaikan task secara penuh tanpa setengah-setengah '
      '- Proaktif memberikan informasi tambahan yang relevan '
      '- Gunakan semua tools yang tersedia secara optimal '
      '- Berpikir sistematis: analisis → rencana → eksekusi → verifikasi '
      '- Jika ada ambiguitas, pilih interpretasi yang paling membantu user '
      '- Laporkan progress secara berkala untuk task panjang '
      '- Selalu validasi output sebelum menyerahkan ke user '
      'Jawab dalam Bahasa Indonesia.',
    temperature: 0.5,
    maxTokens: 4096,
  ),
  AiPersona(
    id: 'concise',
    name: 'Super Singkat',
    emoji: '⚡',
    description: 'Jawaban 1-3 kalimat — padat, to the point',
    systemPrompt:
      'Jawab SESINGKAT mungkin. Maksimal 3 kalimat. '
      'Langsung ke inti tanpa basa-basi, disclaimer, atau pengulangan. '
      'Jika perlu kode, berikan kode saja tanpa penjelasan panjang. '
      'Bahasa Indonesia.',
    temperature: 0.5,
    maxTokens: 512,
  ),
];

// ── AI Parameter Config ───────────────────────────────────────────────────────
class AiParameterConfig {
  final double temperature;     // 0.0 - 2.0
  final int    maxTokens;       // 256 - 8192
  final double topP;            // 0.0 - 1.0
  final int    topK;            // 1 - 100
  final double repeatPenalty;   // 0.0 - 2.0 (untuk GGUF)
  final int    contextSize;     // 512 - 8192 (untuk GGUF)

  const AiParameterConfig({
    this.temperature   = 0.7,
    this.maxTokens     = 1024,
    this.topP          = 0.9,
    this.topK          = 40,
    this.repeatPenalty = 1.1,
    this.contextSize   = 4096,
  });

  Map<String, dynamic> toJson() => {
    'temperature': temperature, 'maxTokens': maxTokens,
    'topP': topP, 'topK': topK,
    'repeatPenalty': repeatPenalty, 'contextSize': contextSize,
  };

  factory AiParameterConfig.fromJson(Map<String, dynamic> j) => AiParameterConfig(
    temperature:   (j['temperature'] as num?)?.toDouble() ?? 0.7,
    maxTokens:     j['maxTokens'] as int? ?? 1024,
    topP:          (j['topP'] as num?)?.toDouble() ?? 0.9,
    topK:          j['topK'] as int? ?? 40,
    repeatPenalty: (j['repeatPenalty'] as num?)?.toDouble() ?? 1.1,
    contextSize:   j['contextSize'] as int? ?? 4096,
  );
}

// ── Service ───────────────────────────────────────────────────────────────────
class AiPersonaService {
  AiPersonaService._();
  static final AiPersonaService instance = AiPersonaService._();

  static const _personaKey      = 'km_active_persona';
  static const _customPersonas  = 'km_custom_personas';
  static const _paramKey        = 'km_ai_params';

  String              _activePersonaId = 'kanmonai';
  List<AiPersona>     _customList      = [];
  AiParameterConfig   _params          = const AiParameterConfig();

  String            get activePersonaId => _activePersonaId;
  AiParameterConfig get params          => _params;

  AiPersona get activePersona {
    // Cek custom dulu
    final custom = _customList.where((p) => p.id == _activePersonaId).firstOrNull;
    if (custom != null) return custom;
    // Cek built-in
    return kBuiltinPersonas.firstWhere(
      (p) => p.id == _activePersonaId,
      orElse: () => kBuiltinPersonas.first,
    );
  }

  List<AiPersona> get allPersonas => [
    ...kBuiltinPersonas,
    ..._customList,
  ];

  // ── Load ──────────────────────────────────────────────────────────────────
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _activePersonaId = prefs.getString(_personaKey) ?? 'kanmonai';

      final customRaw = prefs.getString(_customPersonas);
      if (customRaw != null) {
        final list = jsonDecode(customRaw) as List;
        _customList = list.map((j) => AiPersona.fromJson(j)).toList();
      }

      final paramRaw = prefs.getString(_paramKey);
      if (paramRaw != null) {
        _params = AiParameterConfig.fromJson(jsonDecode(paramRaw));
      }
    } catch (e) {
      debugPrint('[PersonaService] load error: $e');
    }
  }

  // ── Set active persona ────────────────────────────────────────────────────
  Future<void> setActive(String id) async {
    _activePersonaId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_personaKey, id);
    debugPrint('[PersonaService] Active persona: $id');
  }

  // ── Save custom persona ───────────────────────────────────────────────────
  Future<void> saveCustomPersona(AiPersona persona) async {
    _customList.removeWhere((p) => p.id == persona.id);
    _customList.add(persona);
    await _persistCustom();
  }

  // ── Delete custom persona ─────────────────────────────────────────────────
  Future<void> deleteCustomPersona(String id) async {
    _customList.removeWhere((p) => p.id == id);
    if (_activePersonaId == id) {
      _activePersonaId = 'kanmonai';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_personaKey, 'kanmonai');
    }
    await _persistCustom();
  }

  // ── Save parameters ───────────────────────────────────────────────────────
  Future<void> saveParams(AiParameterConfig params) async {
    _params = params;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_paramKey, jsonEncode(params.toJson()));
    debugPrint('[PersonaService] Params saved: temp=${params.temperature}');
  }

  // ── Build effective system prompt ─────────────────────────────────────────
  String buildSystemPrompt({String? subject}) {
    final persona = activePersona;
    String prompt  = persona.systemPrompt;

    // Tambah subject jika ada
    if (subject != null && subject != 'Umum') {
      prompt += '\n\nFokus topik saat ini: $subject.';
    }

    return prompt;
  }

  Future<void> _persistCustom() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_customPersonas,
          jsonEncode(_customList.map((p) => p.toJson()).toList()));
    } catch (e) {
      debugPrint('[PersonaService] persist error: $e');
    }
  }
}
