// lib/data/services/agent_memory_service.dart
// KanMon GO — Agent Memory Service
// Memori jangka panjang untuk AI Agent
// =============================================================================

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemoryEntry {
  final String key;
  final String content;
  final DateTime savedAt;
  final List<String> tags;
  const MemoryEntry({required this.key, required this.content,
      required this.savedAt, this.tags = const []});
  Map<String, dynamic> toJson() => {
    'key': key, 'content': content,
    'savedAt': savedAt.millisecondsSinceEpoch, 'tags': tags,
  };
  factory MemoryEntry.fromJson(Map<String, dynamic> j) => MemoryEntry(
    key: j['key'], content: j['content'],
    savedAt: DateTime.fromMillisecondsSinceEpoch(j['savedAt']),
    tags: List<String>.from(j['tags'] ?? []),
  );
}

class AgentMemoryService {
  AgentMemoryService._();
  static final AgentMemoryService instance = AgentMemoryService._();

  static const _key = 'km_agent_memory';
  List<MemoryEntry> _memories = [];

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString(_key);
      if (raw != null) {
        final list = jsonDecode(raw) as List;
        _memories  = list.map((j) => MemoryEntry.fromJson(j)).toList();
      }
    } catch (e) { debugPrint('[Memory] load error: $e'); }
  }

  Future<void> save({required String key, required String content, List<String>? tags}) async {
    _memories.removeWhere((m) => m.key == key);
    _memories.insert(0, MemoryEntry(
      key: key, content: content, savedAt: DateTime.now(), tags: tags ?? [],
    ));
    // Simpan max 200 memories
    if (_memories.length > 200) _memories = _memories.sublist(0, 200);
    await _persist();
  }

  Future<List<MemoryEntry>> search(String query) async {
    await load();
    final q = query.toLowerCase();
    return _memories.where((m) =>
        m.content.toLowerCase().contains(q) ||
        m.key.toLowerCase().contains(q) ||
        m.tags.any((t) => t.toLowerCase().contains(q))).take(5).toList();
  }

  Future<void> delete(String key) async {
    _memories.removeWhere((m) => m.key == key);
    await _persist();
  }

  Future<void> clear() async {
    _memories.clear();
    await _persist();
  }

  List<MemoryEntry> get all => List.unmodifiable(_memories);

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(_memories.map((m) => m.toJson()).toList()));
    } catch (e) { debugPrint('[Memory] persist error: $e'); }
  }
}
