// lib/data/services/ai/web_research_service.dart
// KanMonAI — Web Research Service
// Sesi 5A: Implementasi lengkap (bukan stub)
//   - ResearchSource: model + copyWith + toMap + fromMap
//   - ResearchResult: model dengan fetchedCount + isEmpty getter
//   - WebResearchService: research(), needsWebSearch(), buildOfflineContext()
//   - Cache 10 menit, fallback engine, skip domain sosmed
// =============================================================================

import 'dart:math';
import 'package:flutter/foundation.dart';
import 'web_scraper_service.dart';

// ─────────────────────────────────────────────
// MODELS
// ─────────────────────────────────────────────

class ResearchSource {
  final String title;
  final String url;
  final String snippet;
  final String? fetchedContent;
  final bool isFetched;
  final String? fetchError;

  const ResearchSource({
    required this.title,
    required this.url,
    required this.snippet,
    this.fetchedContent,
    this.isFetched = false,
    this.fetchError,
  });

  String get domain {
    try {
      return Uri.parse(url).host.replaceFirst('www.', '');
    } catch (_) {
      return url;
    }
  }

  ResearchSource copyWith({
    String? title,
    String? url,
    String? snippet,
    String? fetchedContent,
    bool? isFetched,
    String? fetchError,
  }) {
    return ResearchSource(
      title: title ?? this.title,
      url: url ?? this.url,
      snippet: snippet ?? this.snippet,
      fetchedContent: fetchedContent ?? this.fetchedContent,
      isFetched: isFetched ?? this.isFetched,
      fetchError: fetchError ?? this.fetchError,
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'url': url,
        'snippet': snippet,
        'domain': domain,
        'isFetched': isFetched,
        // fetchedContent sengaja tidak disimpan ke DB
      };

  factory ResearchSource.fromMap(Map<String, dynamic> m) => ResearchSource(
        title: m['title'] as String? ?? '',
        url: m['url'] as String? ?? '',
        snippet: m['snippet'] as String? ?? '',
        isFetched: m['isFetched'] as bool? ?? false,
      );

  @override
  String toString() => 'ResearchSource(title: $title, url: $url)';
}

class ResearchResult {
  final String query;
  final List<ResearchSource> sources;
  final String contextForAi;
  final DateTime searchedAt;
  final bool hasError;
  final String? error;

  const ResearchResult({
    required this.query,
    required this.sources,
    required this.contextForAi,
    required this.searchedAt,
    this.hasError = false,
    this.error,
  });

  int get fetchedCount =>
      sources.where((s) => s.isFetched && s.fetchError == null).length;

  bool get isEmpty => sources.isEmpty;
}

// ─────────────────────────────────────────────
// SERVICE
// ─────────────────────────────────────────────

class WebResearchService {
  WebResearchService._();
  static final instance = WebResearchService._();

  static const _maxSearchResults = 8;
  static const _maxFetchUrls = 3;
  static const _maxCharsPerPage = 4000;
  static const _maxTotalChars = 10000;
  static const _cacheExpiry = Duration(minutes: 10);

  final Map<String, (ResearchResult, DateTime)> _cache = {};

  static const _skipDomains = [
    'youtube.com',
    'youtu.be',
    'twitter.com',
    'x.com',
    'instagram.com',
    'tiktok.com',
    'facebook.com',
    'reddit.com',
    'linkedin.com',
    'pinterest.com',
  ];

  static const _skipExtensions = [
    '.pdf',
    '.mp4',
    '.mp3',
    '.zip',
    '.exe',
    '.apk',
  ];

  bool _shouldSkip(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return true;
    final host = uri.host.toLowerCase();
    if (_skipDomains.any((d) => host.contains(d))) return true;
    final path = uri.path.toLowerCase();
    if (_skipExtensions.any((ext) => path.endsWith(ext))) return true;
    return false;
  }

  /// Lakukan web research: search -> fallback -> fetch konten -> build context
  Future<ResearchResult> research(
    String query, {
    void Function(String status)? onProgress,
    String engine = 'ddg',
    bool fetchContent = true,
  }) async {
    // 1. Cache check
    final key = query.toLowerCase().trim();
    final cached = _cache[key];
    if (cached != null && DateTime.now().difference(cached.$2) < _cacheExpiry) {
      onProgress?.call('Menggunakan cache hasil sebelumnya...');
      return cached.$1;
    }

    final shortQuery =
        query.length > 40 ? '${query.substring(0, 40)}...' : query;
    onProgress?.call('Mencari "$shortQuery"...');

    // 2. Search (primary engine)
    List<SearchResult> rawResults = [];
    try {
      if (engine == 'google') {
        rawResults = await WebScraperService.instance.searchGoogle(query);
      } else {
        rawResults = await WebScraperService.instance.searchDDG(query);
      }
    } catch (e) {
      debugPrint('[WebResearch] primary search error: $e');
    }

    // 3. Fallback ke engine lain jika kosong
    if (rawResults.isEmpty) {
      try {
        onProgress?.call('Mencoba engine alternatif...');
        if (engine == 'google') {
          rawResults = await WebScraperService.instance.searchDDG(query);
        } else {
          rawResults = await WebScraperService.instance.searchGoogle(query);
        }
      } catch (e) {
        debugPrint('[WebResearch] fallback search error: $e');
      }
    }

    // 4. Masih kosong -> return error result
    if (rawResults.isEmpty) {
      return ResearchResult(
        query: query,
        sources: const [],
        contextForAi: '',
        searchedAt: DateTime.now(),
        hasError: true,
        error: 'Tidak ada hasil untuk query: $query',
      );
    }

    // 5. Konversi ke ResearchSource (max _maxSearchResults)
    final limited = rawResults.take(_maxSearchResults).toList();
    List<ResearchSource> sources = limited
        .map((r) => ResearchSource(
              title: r.title,
              url: r.url,
              snippet: r.snippet,
            ))
        .toList();

    // 6. Fetch konten halaman
    if (fetchContent) {
      final fetchable = sources
          .where((s) => !_shouldSkip(s.url))
          .take(_maxFetchUrls)
          .toList();

      int totalChars = 0;
      for (int i = 0; i < fetchable.length; i++) {
        final src = fetchable[i];
        onProgress?.call(
            'Membaca sumber ${i + 1}/${fetchable.length}: ${src.domain}...');
        try {
          final content = await WebScraperService.instance
              .fetch(src.url)
              .timeout(const Duration(seconds: 15));
          final text = content.toAiContext(maxChars: _maxCharsPerPage);
          final available = _maxTotalChars - totalChars;
          final trimmed =
              text.length > available ? text.substring(0, available) : text;
          totalChars += trimmed.length;

          final idx = sources.indexWhere((s) => s.url == src.url);
          if (idx >= 0) {
            sources[idx] = sources[idx].copyWith(
              fetchedContent: trimmed,
              isFetched: true,
            );
          }
          if (totalChars >= _maxTotalChars) break;
        } catch (e) {
          debugPrint('[WebResearch] fetch error ${src.url}: $e');
          final idx = sources.indexWhere((s) => s.url == src.url);
          if (idx >= 0) {
            sources[idx] = sources[idx].copyWith(
              fetchError: e.toString(),
              isFetched: false,
            );
          }
        }
      }
    }

    onProgress?.call('Menyiapkan konteks untuk AI...');
    final context = _buildAiContext(query, sources);
    final result = ResearchResult(
      query: query,
      sources: sources,
      contextForAi: context,
      searchedAt: DateTime.now(),
      hasError: false,
    );
    _cache[key] = (result, DateTime.now());
    return result;
  }

  String _buildAiContext(String query, List<ResearchSource> sources) {
    final buf = StringBuffer();
    buf.writeln('=== HASIL WEB RESEARCH ===');
    buf.writeln('Query: $query');
    buf.writeln('Waktu: ${DateTime.now().toIso8601String()}');
    buf.writeln(
        'Sumber: ${sources.length} ditemukan, ${sources.where((s) => s.isFetched).length} dibaca\n');

    buf.writeln('--- RINGKASAN SUMBER ---');
    for (int i = 0; i < sources.length; i++) {
      final s = sources[i];
      buf.writeln('[${i + 1}] ${s.title}');
      buf.writeln('    URL: ${s.url}');
      if (s.snippet.isNotEmpty) buf.writeln('    ${s.snippet}');
      buf.writeln();
    }

    final fetched =
        sources.where((s) => s.isFetched && s.fetchError == null).toList();
    if (fetched.isNotEmpty) {
      buf.writeln('--- KONTEN HALAMAN ---');
      for (final s in fetched) {
        buf.writeln('--- Sumber [${sources.indexOf(s) + 1}]: ${s.title} ---');
        buf.writeln('URL: ${s.url}');
        buf.writeln(s.fetchedContent ?? '');
        buf.writeln();
      }
    }

    buf.writeln('=== INSTRUKSI ===');
    buf.writeln('Gunakan informasi di atas untuk menjawab pertanyaan user.');
    buf.writeln('Cantumkan nomor sumber [1], [2] saat mengutip.');
    buf.writeln('Jika informasi tidak cukup, katakan dengan jujur.');
    return buf.toString();
  }

  /// Buat context ringkas untuk AI offline (max 5 sumber, max 1500 chars)
  String buildOfflineContext(ResearchResult research) {
    final buf = StringBuffer('Web research (ringkas):\n');
    final count = min(5, research.sources.length);
    for (int i = 0; i < count; i++) {
      final s = research.sources[i];
      final snippetLen = min(200, s.snippet.length);
      buf.writeln(
          '[${i + 1}] ${s.title}: ${s.snippet.substring(0, snippetLen)}');
    }
    final result = buf.toString();
    return result.length > 1500 ? result.substring(0, 1500) : result;
  }

  /// Deteksi apakah query butuh web search atau tidak
  bool needsWebSearch(String query) {
    final q = query.toLowerCase().trim();

    // No-search patterns (prioritas tinggi)
    final noSearch = [
      RegExp(r'^(halo|hi|hey|apa kabar|selamat|permisi)'),
      RegExp(
          r'^(tulis|buat|cerita|puisi|sajak|rangkuman|jelaskan|apa itu .{1,30}$)'),
      RegExp(
          r'(kode|code|program|debug|fix|error|compile|flutter|dart|python|javascript)'),
      RegExp(r'^(terjemah|translate|artinya|definisi)'),
    ];
    for (final re in noSearch) {
      if (re.hasMatch(q)) return false;
    }

    // Search patterns
    final search = [
      RegExp(r'(terbaru|terkini|hari ini|sekarang|2024|2025|2026)'),
      RegExp(r'(harga|kurs|cuaca|berita|jadwal|lowongan|review|spesifikasi)'),
      RegExp(r'(cara install|cara download|cara beli|cara daftar)'),
      RegExp(
          r'^(apa|berapa|siapa|kapan|dimana|bagaimana).{0,60}(sekarang|terbaru|2025|2026)'),
      RegExp(r'(cari|search|googling|temukan info)'),
      RegExp(r'\bvs\b|\bbanding\b|\bcompare\b'),
      RegExp(r'https?://'),
    ];
    for (final re in search) {
      if (re.hasMatch(q)) return true;
    }

    return false;
  }

  /// Bersihkan cache internal
  void clearCache() => _cache.clear();
}
