// lib/data/services/ai/web_scraper_service.dart
// KanMon GO — Web Scraper Service
// Ambil & parse konten dari internet untuk AI Agent
// =============================================================================

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

class WebContent {
  final String url;
  final String title;
  final String text;
  final String rawHtml;
  final int statusCode;
  final Map<String, String> headers;
  final List<String> links;
  final List<String> images;
  final DateTime fetchedAt;
  final String? error;

  const WebContent({
    required this.url,
    required this.title,
    required this.text,
    required this.rawHtml,
    required this.statusCode,
    required this.headers,
    required this.links,
    required this.images,
    required this.fetchedAt,
    this.error,
  });

  bool get isSuccess => error == null && statusCode >= 200 && statusCode < 400;

  String get preview => text.length > 500 ? '${text.substring(0, 500)}...' : text;

  String toAiContext({int maxChars = 8000}) {
    final sb = StringBuffer();
    sb.writeln('=== WEB PAGE ===');
    sb.writeln('URL: $url');
    sb.writeln('Title: $title');
    sb.writeln('Fetched: ${fetchedAt.toLocal()}');
    sb.writeln('');
    sb.writeln('=== CONTENT ===');
    final trimText = text.length > maxChars
        ? '${text.substring(0, maxChars)}\n... [TERPOTONG]'
        : text;
    sb.write(trimText);
    if (links.isNotEmpty) {
      sb.writeln('\n\n=== LINKS ===');
      for (final l in links.take(20)) sb.writeln(l);
    }
    return sb.toString();
  }
}

class SearchResult {
  final String title;
  final String url;
  final String snippet;
  const SearchResult({required this.title, required this.url, required this.snippet});
}

class WebScraperService {
  WebScraperService._();
  static final WebScraperService instance = WebScraperService._();

  static const _timeout = Duration(seconds: 20);

  // Headers yang mirip browser untuk menghindari bot detection
  static const _headers = {
    'User-Agent': 'Mozilla/5.0 (Linux; Android 12; Mobile) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/120.0.0.0 Mobile Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'id-ID,id;q=0.9,en-US;q=0.8,en;q=0.7',
    'Accept-Encoding': 'gzip, deflate',
    'DNT': '1',
    'Connection': 'keep-alive',
    'Upgrade-Insecure-Requests': '1',
  };

  final Map<String, WebContent> _cache = {};
  late http.Client _client;
  bool _clientInit = false;

  http.Client get _httpClient {
    if (!_clientInit) {
      _client = http.Client();
      _clientInit = true;
    }
    return _client;
  }

  // ── Fetch halaman web ─────────────────────────────────────────────────────
  Future<WebContent> fetch(String url, {bool useCache = true}) async {
    final normalUrl = _normalizeUrl(url);

    if (useCache && _cache.containsKey(normalUrl)) {
      debugPrint('[WebScraper] Cache hit: $normalUrl');
      return _cache[normalUrl]!;
    }

    try {
      final response = await _httpClient
          .get(Uri.parse(normalUrl), headers: _headers)
          .timeout(_timeout);

      String rawHtml;
      try {
        rawHtml = utf8.decode(response.bodyBytes);
      } catch (_) {
        rawHtml = latin1.decode(response.bodyBytes);
      }

      final doc   = html_parser.parse(rawHtml);
      final title = doc.querySelector('title')?.text.trim() ?? '';

      // Hapus elemen tidak penting
      doc.querySelectorAll(
          'script, style, noscript, svg, canvas, iframe, '
          'header, footer, nav, aside, '
          '.ad, .ads, .advertisement, .sidebar, .cookie-notice, '
          '[role="banner"], [role="navigation"], [aria-hidden="true"]')
          .forEach((e) => e.remove());

      final text = _extractText(rawHtml);

      final links = doc.querySelectorAll('a[href]')
          .map((a) => _resolveUrl(normalUrl, a.attributes['href'] ?? ''))
          .where((l) => l.startsWith('http'))
          .toSet()
          .toList();

      final images = doc.querySelectorAll('img[src]')
          .map((img) => _resolveUrl(normalUrl, img.attributes['src'] ?? ''))
          .where((s) => s.startsWith('http'))
          .toList();

      final headers = <String, String>{};
      response.headers.forEach((k, v) => headers[k] = v);

      final result = WebContent(
        url: normalUrl,
        title: title,
        text: text,
        rawHtml: rawHtml,
        statusCode: response.statusCode,
        headers: headers,
        links: links,
        images: images,
        fetchedAt: DateTime.now(),
      );

      _cache[normalUrl] = result;
      debugPrint('[WebScraper] Fetched: $normalUrl (${text.length} chars, status: ${response.statusCode})');
      return result;

    } catch (e) {
      debugPrint('[WebScraper] Error fetching $normalUrl: $e');
      return WebContent(
        url: normalUrl, title: '', text: '', rawHtml: '',
        statusCode: 0, headers: {}, links: [], images: [],
        fetchedAt: DateTime.now(), error: e.toString(),
      );
    }
  }

  // ── Search DuckDuckGo via Lite endpoint (lebih reliabel, anti-bot minimal) ─
  Future<List<SearchResult>> searchDDG(String query, {int maxResults = 10}) async {
    debugPrint('[WebScraper] DDG search: "$query"');

    // Coba DDG lite dulu (HTML paling sederhana)
    final results = await _searchDDGLite(query, maxResults: maxResults);
    if (results.isNotEmpty) {
      debugPrint('[WebScraper] DDG Lite → ${results.length} results');
      return results;
    }

    // Fallback: DDG HTML biasa
    final fallback = await _searchDDGHtml(query, maxResults: maxResults);
    debugPrint('[WebScraper] DDG HTML fallback → ${fallback.length} results');
    return fallback;
  }

  Future<List<SearchResult>> _searchDDGLite(String query, {int maxResults = 10}) async {
    try {
      final url = Uri.parse(
          'https://lite.duckduckgo.com/lite/?q=${Uri.encodeComponent(query)}');

      final response = await _httpClient.get(url, headers: {
        ..._headers,
        'Referer': 'https://lite.duckduckgo.com/',
      }).timeout(_timeout);

      if (response.statusCode != 200) return [];

      final doc     = html_parser.parse(utf8.decode(response.bodyBytes));
      final results = <SearchResult>[];

      // DDG lite: hasil ada di <a class="result-link"> dan <td class="result-snippet">
      final rows = doc.querySelectorAll('tr');
      String? currentTitle;
      String? currentUrl;

      for (final row in rows) {
        final linkEl = row.querySelector('a.result-link');
        if (linkEl != null) {
          currentTitle = linkEl.text.trim();
          final href = linkEl.attributes['href'] ?? '';
          // DDG lite mengembalikan URL redirect, extract yang asli
          currentUrl = _extractDDGUrl(href);
          continue;
        }

        final snippetEl = row.querySelector('td.result-snippet');
        if (snippetEl != null && currentTitle != null && currentUrl != null) {
          final snippet = snippetEl.text.trim();
          if (currentUrl.startsWith('http') && currentTitle.isNotEmpty) {
            results.add(SearchResult(
              title: currentTitle,
              url: currentUrl,
              snippet: snippet,
            ));
          }
          currentTitle = null;
          currentUrl   = null;
        }

        if (results.length >= maxResults) break;
      }

      return results;
    } catch (e) {
      debugPrint('[WebScraper] DDG Lite error: $e');
      return [];
    }
  }

  Future<List<SearchResult>> _searchDDGHtml(String query, {int maxResults = 10}) async {
    try {
      final url = Uri.parse(
          'https://html.duckduckgo.com/html/?q=${Uri.encodeComponent(query)}');

      final response = await _httpClient.get(url, headers: {
        ..._headers,
        'Referer': 'https://duckduckgo.com/',
      }).timeout(_timeout);

      if (response.statusCode != 200) return [];

      final doc     = html_parser.parse(utf8.decode(response.bodyBytes));
      final results = <SearchResult>[];

      for (final el in doc.querySelectorAll('.result, .web-result')) {
        final titleEl   = el.querySelector('.result__title a, .result__a');
        final snippetEl = el.querySelector('.result__snippet');
        if (titleEl == null) continue;

        final href = titleEl.attributes['href'] ?? '';
        final url2 = _extractDDGUrl(href);
        if (!url2.startsWith('http')) continue;

        results.add(SearchResult(
          title:   titleEl.text.trim(),
          url:     url2,
          snippet: snippetEl?.text.trim() ?? '',
        ));
        if (results.length >= maxResults) break;
      }

      return results;
    } catch (e) {
      debugPrint('[WebScraper] DDG HTML error: $e');
      return [];
    }
  }

  // Extract URL asli dari DDG redirect
  String _extractDDGUrl(String href) {
    if (href.startsWith('http') && !href.contains('duckduckgo.com')) return href;

    // Format: //duckduckgo.com/l/?uddg=<encoded_url>&...
    try {
      if (href.contains('uddg=')) {
        final raw = href.split('uddg=')[1].split('&').first;
        return Uri.decodeComponent(raw);
      }
      // Format: /l/?kh=-1&uddg=...
      if (href.startsWith('/l/?') || href.startsWith('//duckduckgo.com/l/?')) {
        final uri = Uri.parse(href.startsWith('//') ? 'https:$href' : 'https://duckduckgo.com$href');
        final uddg = uri.queryParameters['uddg'] ?? '';
        if (uddg.isNotEmpty) return Uri.decodeComponent(uddg);
      }
    } catch (_) {}
    return href;
  }

  // ── Search Google via scraping ────────────────────────────────────────────
  Future<List<SearchResult>> searchGoogle(String query, {int maxResults = 10}) async {
    try {
      final url = Uri.parse(
          'https://www.google.com/search?q=${Uri.encodeComponent(query)}'
          '&num=$maxResults&hl=id&gl=id');

      final response = await _httpClient.get(url, headers: {
        ..._headers,
        'Referer': 'https://www.google.com/',
      }).timeout(_timeout);

      if (response.statusCode != 200) {
        debugPrint('[WebScraper] Google returned ${response.statusCode}, fallback to DDG');
        return searchDDG(query, maxResults: maxResults);
      }

      final doc     = html_parser.parse(utf8.decode(response.bodyBytes));
      final results = <SearchResult>[];

      // Coba berbagai selector Google (berubah-ubah)
      for (final sel in ['div.g', 'div[data-hveid]', '[data-sokoban-container]', 'div.tF2Cxc']) {
        for (final el in doc.querySelectorAll(sel)) {
          final titleEl   = el.querySelector('h3');
          final linkEl    = el.querySelector('a[href]');
          final snippetEl = el.querySelector('.VwiC3b, [data-snf], span.aCOpRe, div.IsZvec');

          if (titleEl == null || linkEl == null) continue;

          final href = linkEl.attributes['href'] ?? '';
          final url2 = href.startsWith('/url?q=')
              ? Uri.decodeComponent(href.substring(7).split('&').first)
              : href;

          if (!url2.startsWith('http')) continue;

          results.add(SearchResult(
            title:   titleEl.text.trim(),
            url:     url2,
            snippet: snippetEl?.text.trim() ?? '',
          ));
          if (results.length >= maxResults) break;
        }
        if (results.isNotEmpty) break;
      }

      if (results.isEmpty) {
        debugPrint('[WebScraper] Google parse gagal, fallback ke DDG');
        return searchDDG(query, maxResults: maxResults);
      }

      debugPrint('[WebScraper] Google → ${results.length} results');
      return results;
    } catch (e) {
      debugPrint('[WebScraper] Google error: $e, fallback ke DDG');
      return searchDDG(query, maxResults: maxResults);
    }
  }

  // ── Fetch JSON API ────────────────────────────────────────────────────────
  Future<dynamic> fetchJson(String url, {
    Map<String, String>? headers,
    String method = 'GET',
    String? body,
  }) async {
    try {
      final uri = Uri.parse(url);
      final reqHeaders = {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        ...?headers,
      };

      final response = method.toUpperCase() == 'POST'
          ? await _httpClient.post(uri,
              headers: reqHeaders,
              body: body,
            ).timeout(_timeout)
          : method.toUpperCase() == 'DELETE'
          ? await _httpClient.delete(uri, headers: reqHeaders).timeout(_timeout)
          : method.toUpperCase() == 'PUT'
          ? await _httpClient.put(uri,
              headers: reqHeaders,
              body: body,
            ).timeout(_timeout)
          : await _httpClient.get(uri, headers: reqHeaders).timeout(_timeout);

      final text = utf8.decode(response.bodyBytes);

      // Return raw response info jika bukan JSON valid
      try {
        return jsonDecode(text);
      } catch (_) {
        return {
          'status': response.statusCode,
          'body': text.length > 2000 ? '${text.substring(0, 2000)}...' : text,
          'headers': response.headers,
        };
      }
    } catch (e) {
      debugPrint('[WebScraper] fetchJson error: $e');
      return {'error': e.toString(), 'url': url};
    }
  }

  // ── Ekstrak teks bersih dari HTML ─────────────────────────────────────────
  String _extractText(String rawHtml) {
    final doc = html_parser.parse(rawHtml);
    doc.querySelectorAll(
        'script, style, noscript, svg, canvas, '
        'header, footer, nav, aside, .ad, .advertisement, '
        '[aria-hidden="true"]').forEach((e) => e.remove());

    // Prioritas: ambil main content dulu
    final main = doc.querySelector('main, article, [role="main"], #content, .content');
    final text = (main ?? doc.body)?.text ?? doc.body?.text ?? '';

    return text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .join('\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  String _normalizeUrl(String url) {
    if (!url.startsWith('http')) return 'https://$url';
    return url;
  }

  String _resolveUrl(String base, String href) {
    if (href.startsWith('http')) return href;
    if (href.startsWith('//')) return 'https:$href';
    if (href.startsWith('/')) {
      final uri = Uri.parse(base);
      return '${uri.scheme}://${uri.host}$href';
    }
    return href;
  }

  void clearCache() => _cache.clear();

  void dispose() {
    if (_clientInit) {
      _client.close();
      _clientInit = false;
    }
  }
}
