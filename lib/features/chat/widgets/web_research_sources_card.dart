// lib/features/chat/widgets/web_research_sources_card.dart
// KanMonAI — Web Research Sources Card
// Sesi 5C-A: Widget kartu sumber web research
//   - Header collapsible dengan AnimatedRotation
//   - AnimatedCrossFade untuk expand/collapse daftar sumber
//   - _SourceTile: favicon Google S2, title + domain + snippet, badge "✓ Dibaca"
//   - Footer: jumlah sumber + jumlah dibaca
//   - Tap tile → launchUrl(externalApplication)
// =============================================================================

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../data/services/web_research_service.dart';

class WebResearchSourcesCard extends StatefulWidget {
  final List<ResearchSource> sources;
  final String query;

  const WebResearchSourcesCard({
    super.key,
    required this.sources,
    required this.query,
  });

  @override
  State<WebResearchSourcesCard> createState() => _WebResearchSourcesCardState();
}

class _WebResearchSourcesCardState extends State<WebResearchSourcesCard> {
  bool _isExpanded = false;

  int get _fetchedCount =>
      widget.sources.where((s) => s.isFetched && s.fetchError == null).length;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final accent = c.primary;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: accent.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(12),
        color: c.surface,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.travel_explore_rounded,
                          size: 16, color: accent),
                      const SizedBox(width: 6),
                      Text(
                        'Sumber Web',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: c.onSurface,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 4),
                      _badge('${widget.sources.length}', accent, c),
                      const Spacer(),
                      AnimatedRotation(
                        turns: _isExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(Icons.expand_more_rounded,
                            color: c.onSurface.withValues(alpha: 0.5)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.query,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.onSurface.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Expanded List ────────────────────────────────────────────────
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _isExpanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Column(
              mainAxisSize: MainAxisSize.min,
              children: widget.sources
                  .map((source) => _SourceTile(source: source, accent: accent))
                  .toList(),
            ),
            secondChild: const SizedBox.shrink(),
          ),

          // ── Footer ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Text(
                  '${widget.sources.length} sumber · $_fetchedCount dibaca',
                  style: TextStyle(
                    color: c.onSurface.withValues(alpha: 0.45),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(String text, Color accent, ColorScheme c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: accent,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// ── Tile per sumber ──────────────────────────────────────────────────────────

class _SourceTile extends StatelessWidget {
  final ResearchSource source;
  final Color accent;

  const _SourceTile({required this.source, required this.accent});

  Future<void> _open() async {
    try {
      final uri = Uri.tryParse(source.url);
      if (uri != null && await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        debugPrint('[SourceTile] Tidak bisa buka URL: ${source.url}');
      }
    } catch (e) {
      debugPrint('[SourceTile] Error membuka URL: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Divider(height: 1, thickness: 1, color: c.outline.withValues(alpha: 0.15)),
        InkWell(
          onTap: _open,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Favicon ────────────────────────────────────────────────
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Image.network(
                    'https://www.google.com/s2/favicons?domain=${source.domain}&sz=32',
                    width: 20,
                    height: 20,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.public,
                      size: 20,
                      color: c.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // ── Title + domain + snippet ────────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        source.title.isNotEmpty ? source.title : source.domain,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        source.domain,
                        style: TextStyle(
                          color: c.onSurface.withValues(alpha: 0.5),
                          fontSize: 11,
                        ),
                      ),
                      if (source.snippet.isNotEmpty)
                        Text(
                          source.snippet,
                          style: TextStyle(
                            color: c.onSurface.withValues(alpha: 0.6),
                            fontSize: 12,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),

                // ── Badge "✓ Dibaca" ────────────────────────────────────────
                if (source.isFetched && source.fetchError == null)
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      '✓ Dibaca',
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
