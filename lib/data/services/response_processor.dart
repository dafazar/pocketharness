// lib/data/services/response_processor.dart
// KanMon GO — Response Post-Processor
// Extracts code blocks, artifacts, formats output for UI
// =============================================================================

import 'package:uuid/uuid.dart';

import '../models/ai_request_model.dart';

const _codeBlockPattern = r'```(\w+)?\n([\s\S]*?)\n```';

/// Post-processes AI responses to extract code, artifacts, format output
class ResponseProcessor {
  final Uuid _uuid = const Uuid();

  /// Main processing function
  Future<AiResponse> processResponse(AiResponse response) async {
    final codeBlocks = _extractCodeBlocks(response.content);
    final artifacts  = _detectArtifacts(response.content, codeBlocks);
    final formatted  = _formatContentForDisplay(response.content);

    return response.copyWith(
      content:            formatted,
      codeBlocks:         codeBlocks.map((c) => c.code).toList(),
      detectedArtifacts:  artifacts,
    );
  }

  // ── Code block extraction ─────────────────────────────────────────────────

  List<AiCodeBlock> _extractCodeBlocks(String content) {
    final blocks = <AiCodeBlock>[];
    final regex  = RegExp(_codeBlockPattern, multiLine: true);

    for (final match in regex.allMatches(content)) {
      final language = match.group(1)?.toLowerCase() ?? 'text';
      final code     = match.group(2)?.trim() ?? '';
      if (code.isNotEmpty) {
        blocks.add(AiCodeBlock(
          id:       _uuid.v4(),
          language: language,
          code:     code,
        ));
      }
    }
    return blocks;
  }

  // ── Artifact detection ────────────────────────────────────────────────────

  List<AiCodeBlock> _detectArtifacts(
    String content,
    List<AiCodeBlock> codeBlocks,
  ) {
    final artifacts = <AiCodeBlock>[];

    // File mentions → associate with adjacent code block
    final fileRegex = RegExp(
      r'(?:filename|file|path)[:\s]+[`"]?([^\s`"]+\.[a-zA-Z0-9]{1,6})[`"]?',
    );
    for (final match in fileRegex.allMatches(content)) {
      final filename = match.group(1);
      if (filename != null && filename.isNotEmpty) {
        for (final block in codeBlocks) {
          if (block.filename == null) {
            artifacts.add(_copyBlockWithFilename(block, filename));
            break;
          }
        }
      }
    }

    // Unified diff detection
    final diffRegex = RegExp(r'---\n.*?\n\+\+\+\n.*?\n@@', multiLine: true);
    if (diffRegex.hasMatch(content)) {
      artifacts.add(AiCodeBlock(
        id:          _uuid.v4(),
        language:    'diff',
        code:        content,
        description: 'Diff/Patch',
        filename:    'diff.patch',
      ));
    }

    return artifacts;
  }

  // ── Display formatting ────────────────────────────────────────────────────

  String _formatContentForDisplay(String content) {
    final codeBlockRegex = RegExp(_codeBlockPattern, multiLine: true);
    final savedBlocks    = <String>[];
    var processed        = content;

    // Stash code blocks
    int index = 0;
    for (final match in codeBlockRegex.allMatches(content)) {
      savedBlocks.add(match.group(0)!);
      processed = processed.replaceFirst(
        match.group(0)!,
        '<<<CODEBLOCK_${index}>>>',
      );
      index++;
    }

    // Strip basic markdown from prose
    processed = processed
        .replaceAll(RegExp(r'\*\*(.+?)\*\*'), r'$1')
        .replaceAll(RegExp(r'\*(.+?)\*'),     r'$1')
        .replaceAll(RegExp(r'_(.+?)_'),        r'$1')
        .replaceAll(RegExp(r'~~(.+?)~~'),      r'$1');

    // Restore code blocks
    for (int i = 0; i < savedBlocks.length; i++) {
      processed = processed.replaceAll(
        '<<<CODEBLOCK_${i}>>>',
        savedBlocks[i],
      );
    }

    return _cleanText(processed);
  }

  String _cleanText(String text) {
    return text
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .replaceAll(RegExp(r'[ ]{2,}'), ' ')
        .trim();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  AiCodeBlock _copyBlockWithFilename(AiCodeBlock block, String filename) =>
      AiCodeBlock(
        id:          block.id,
        language:    block.language,
        code:        block.code,
        description: block.description,
        filename:    filename,
      );
}
