// lib/features/chat/widgets/message_bubble.dart
// KanMonAI — Public MessageBubble Widget (Sesi 6A-i-3)
//
// Widget bubble percakapan untuk ChatMessage dari chat_models.dart.
// Mengintegrasikan WaveDotLoading untuk state streaming awal (konten kosong)
// dan menampilkan teks streaming saat konten mulai mengalir.
//
// Logika konten asisten:
//   isStreaming=true  & content="" → WaveDotLoading()      (menunggu token pertama)
//   isStreaming=true  & content≠"" → Teks streaming + cursor (token sedang mengalir)
//   isStreaming=false              → MarkdownContent normal (selesai)
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import 'package:kanmongo/core/theme/km_colors.dart';
import 'package:kanmongo/data/models/chat_models.dart';
import 'package:kanmongo/features/chat/widgets/attachment_preview.dart';
import 'package:kanmongo/features/chat/widgets/code_block_widget.dart';
import 'package:kanmongo/features/chat/widgets/file_edit_response_widget.dart';
import 'package:kanmongo/features/chat/widgets/wave_dot_loading.dart';
import 'package:kanmongo/features/chat/widgets/web_research_sources_card.dart';
import 'package:kanmongo/shared/utils/top_snack.dart';

// =============================================================================
// PUBLIC WIDGET: MessageBubble
// =============================================================================

class MessageBubble extends StatelessWidget {
  final ChatMessage message;

  /// Tampilkan konten sebagai teks mentah (tanpa render Markdown).
  final bool showRawText;

  /// Apakah ini pesan user terakhir (untuk opsi "Kirim Ulang" di sheet).
  final bool isLastUser;

  /// Apakah ini pesan asisten terakhir (untuk opsi "Regenerate" di sheet).
  final bool isLastAssistant;

  /// Lampiran yang terkait dengan pesan ini.
  final List<ChatAttachment> attachments;

  /// Sumber web research yang terkait (opsional).
  final List<ResearchSource>? webSources;

  /// Query yang digunakan untuk web research (dipakai di header card).
  final String webResearchQuery;

  /// Callback saat pesan dihapus.
  final VoidCallback onDelete;

  /// Callback saat pesan user dikirim ulang.
  final VoidCallback onResend;

  /// Callback saat respons asisten di-regenerate.
  final VoidCallback onRegenerate;

  /// Callback toggle tampilan markdown / teks mentah.
  final VoidCallback onToggleRaw;

  const MessageBubble({
    super.key,
    required this.message,
    this.showRawText = false,
    this.isLastUser = false,
    this.isLastAssistant = false,
    this.attachments = const [],
    this.webSources,
    this.webResearchQuery = '',
    required this.onDelete,
    required this.onResend,
    required this.onRegenerate,
    required this.onToggleRaw,
  });

  @override
  Widget build(BuildContext context) {
    final kfc    = KmColors.of(context);
    final isUser = message.isUser; // role == 'user'

    return GestureDetector(
      onLongPress: () => _showMessageSheet(context, kfc),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment:
              isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // ── Avatar AI (kiri, hanya untuk asisten) ────────────────────
            if (!isUser)
              Container(
                width: 30,
                height: 30,
                margin: const EdgeInsets.only(right: 8, bottom: 4),
                decoration: BoxDecoration(
                  color: kfc.accentSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.smart_toy_rounded,
                    size: 16, color: kfc.accent),
              ),

            // ── Konten bubble ─────────────────────────────────────────────
            Flexible(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.78,
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isUser ? kfc.accent : kfc.card,
                  borderRadius: BorderRadius.only(
                    topLeft:     const Radius.circular(16),
                    topRight:    const Radius.circular(16),
                    bottomLeft:  Radius.circular(isUser ? 16 : 4),
                    bottomRight: Radius.circular(isUser ? 4 : 16),
                  ),
                  border: isUser
                      ? null
                      : Border.all(color: kfc.borderSoft),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Lampiran (attachment previews) ──────────────────
                    if (attachments.isNotEmpty) ...[
                      ...attachments.map((att) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: AttachmentPreview(
                          attachment: att,
                          isUserBubble: isUser,
                        ),
                      )),
                      const Divider(height: 1, thickness: 1),
                      const SizedBox(height: 6),
                    ],

                    // ── Web Research Sources Card ────────────────────────
                    if (webSources != null && webSources!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: WebResearchSourcesCard(
                          sources: webSources!,
                          query: webResearchQuery,
                        ),
                      ),

                    // ── Konten utama pesan ──────────────────────────────
                    _buildContent(context, kfc, isUser),

                    // ── FileEditResponseWidget (diff/replace pattern) ───
                    if (!isUser && message.content.isNotEmpty &&
                        !message.isStreaming)
                      FileEditResponseWidget(aiResponse: message.content),

                    const SizedBox(height: 4),

                    // ── AI Mode Badge (kiri) + Timestamp (kanan) ─────────
                    _buildFooter(context, kfc, isUser),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // _buildContent — logika inti streaming vs normal
  // ---------------------------------------------------------------------------

  Widget _buildContent(
      BuildContext context, KmColors kfc, bool isUser) {
    // ── Error ──────────────────────────────────────────────────────────────
    if (message.error != null && message.error!.isNotEmpty) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_rounded, color: Colors.red, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              message.error!,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          ),
        ],
      );
    }

    // ── Pesan user → selalu teks biasa ──────────────────────────────────
    if (isUser) {
      return Text(
        message.content,
        style: TextStyle(
          color: Colors.white,
          fontSize: 14,
          height: 1.45,
        ),
      );
    }

    // ── Pesan asisten — tiga cabang streaming ────────────────────────────

    // Cabang 1: streaming=true, konten KOSONG → animasi loading
    if (message.isStreaming && message.content.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: WaveDotLoading(),
      );
    }

    // Cabang 2: streaming=true, konten ADA → tampilkan progres + cursor
    if (message.isStreaming && message.content.isNotEmpty) {
      return _StreamingText(content: message.content, kfc: kfc);
    }

    // Cabang 3: streaming=false → render Markdown normal
    if (showRawText) {
      return Text(
        message.content,
        style: TextStyle(
          color: kfc.text,
          fontSize: 14,
          height: 1.45,
        ),
      );
    }

    return _MarkdownContent(text: message.content, kfc: kfc);
  }

  // ---------------------------------------------------------------------------
  // _buildFooter — AI Mode Badge (kiri) + Timestamp (kanan) untuk assistant,
  //                hanya Timestamp untuk user
  // ---------------------------------------------------------------------------

  Widget _buildFooter(BuildContext context, KmColors kfc, bool isUser) {
    final timestamp = Text(
      DateFormat('HH:mm').format(message.createdAt),
      style: TextStyle(
        color: isUser ? Colors.white70 : kfc.textSub,
        fontSize: 10,
      ),
    );

    // Bubble user: hanya timestamp di kanan
    if (isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: timestamp,
      );
    }

    // Bubble assistant: Badge (kiri) + Timestamp (kanan)
    final modeIcon = _modeIcon(message.aiMode);
    final modeLabel = _modeLabel(message.aiMode);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // ── AI Mode Badge ──────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: kfc.surface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: kfc.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(modeIcon, style: const TextStyle(fontSize: 10)),
              const SizedBox(width: 3),
              Text(
                modeLabel,
                style: TextStyle(fontSize: 10, color: kfc.textSub),
              ),
            ],
          ),
        ),
        // ── Timestamp ──────────────────────────────────────────────────────
        timestamp,
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Helper: ikon & label untuk AI Mode Badge
  // ---------------------------------------------------------------------------

  String _modeIcon(AiMode? mode) {
    switch (mode) {
      case AiMode.offline:
        return '💾';
      case AiMode.online:
        return '🌐';
      case AiMode.bulkApi:
        return '⚡';
      default:
        return '🤖';
    }
  }

  String _modeLabel(AiMode? mode) {
    if (mode == null) return 'AI';
    final raw = mode.name; // e.g. "offline", "online", "bulkApi"
    return raw.length > 12 ? '${raw.substring(0, 12)}...' : raw;
  }

  // ---------------------------------------------------------------------------
  // _showMessageSheet — long-press bottom sheet
  // ---------------------------------------------------------------------------

  void _showMessageSheet(BuildContext context, KmColors kfc) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: false,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: kfc.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 8),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: kfc.borderSoft,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Salin
              ListTile(
                leading: Icon(Icons.copy_rounded, color: kfc.accent),
                title:
                    Text('Salin pesan', style: TextStyle(color: kfc.text)),
                onTap: () {
                  Navigator.pop(context);
                  Clipboard.setData(
                      ClipboardData(text: message.content));
                  showTopSnack(context, 'Pesan disalin.');
                },
              ),
              // Hapus
              ListTile(
                leading: const Icon(Icons.delete_rounded,
                    color: Colors.red),
                title:
                    Text('Hapus pesan', style: TextStyle(color: kfc.text)),
                onTap: () {
                  Navigator.pop(context);
                  onDelete();
                },
              ),
              // Kirim ulang (hanya pesan user terakhir)
              if (isLastUser)
                ListTile(
                  leading: Icon(Icons.refresh_rounded,
                      color: kfc.textSub),
                  title: Text('Kirim ulang',
                      style: TextStyle(color: kfc.text)),
                  onTap: () {
                    Navigator.pop(context);
                    onResend();
                  },
                ),
              // Regenerate (hanya pesan asisten terakhir)
              if (isLastAssistant)
                ListTile(
                  leading:
                      Icon(Icons.replay_rounded, color: kfc.textSub),
                  title: Text('Regenerate',
                      style: TextStyle(color: kfc.text)),
                  onTap: () {
                    Navigator.pop(context);
                    onRegenerate();
                  },
                ),
              // Bagikan
              ListTile(
                leading: Icon(Icons.share_rounded, color: kfc.textSub),
                title: Text('Bagikan',
                    style: TextStyle(color: kfc.text)),
                onTap: () {
                  Navigator.pop(context);
                  Share.share(message.content);
                },
              ),
              // Toggle raw/markdown
              ListTile(
                leading: Icon(Icons.code_rounded, color: kfc.textSub),
                title: Text('Lihat teks mentah',
                    style: TextStyle(color: kfc.text)),
                onTap: () {
                  Navigator.pop(context);
                  onToggleRaw();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// PRIVATE: _StreamingText — teks yang sedang di-stream dengan cursor berkedip
// =============================================================================

class _StreamingText extends StatefulWidget {
  final String   content;
  final KmColors kfc;
  const _StreamingText({required this.content, required this.kfc});

  @override
  State<_StreamingText> createState() => _StreamingTextState();
}

class _StreamingTextState extends State<_StreamingText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _cursorCtrl;
  late final Animation<double>   _cursorAnim;

  @override
  void initState() {
    super.initState();
    _cursorCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 530),
    )..repeat(reverse: true);
    _cursorAnim = Tween<double>(begin: 0, end: 1).animate(_cursorCtrl);
  }

  @override
  void dispose() {
    _cursorCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kfc = widget.kfc;
    return AnimatedBuilder(
      animation: _cursorAnim,
      builder: (_, __) {
        final showCursor = _cursorAnim.value > 0.5;
        return Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: widget.content,
                style: TextStyle(
                  color: kfc.text,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
              // Cursor berkedip
              TextSpan(
                text: showCursor ? '▍' : ' ',
                style: TextStyle(
                  color: kfc.accent,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// =============================================================================
// PRIVATE: _MarkdownContent — renderer markdown sederhana
// =============================================================================

class _MarkdownContent extends StatelessWidget {
  final String   text;
  final KmColors kfc;
  const _MarkdownContent({required this.text, required this.kfc});

  @override
  Widget build(BuildContext context) {
    final blocks = _parseMarkdown(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks.map((b) => _buildBlock(context, b)).toList(),
    );
  }

  List<_MdBlock> _parseMarkdown(String src) {
    final lines  = src.split('\n');
    final blocks = <_MdBlock>[];
    final buf    = StringBuffer();
    bool inCode  = false;
    String codeLang = '';

    for (final line in lines) {
      if (line.startsWith('```')) {
        if (!inCode) {
          if (buf.isNotEmpty) {
            blocks.add(_MdBlock.text(buf.toString().trimRight()));
            buf.clear();
          }
          inCode   = true;
          codeLang = line.substring(3).trim();
        } else {
          blocks.add(_MdBlock.code(buf.toString(), codeLang));
          buf.clear();
          inCode   = false;
          codeLang = '';
        }
        continue;
      }
      buf.writeln(line);
    }

    if (buf.isNotEmpty) {
      if (inCode) {
        blocks.add(_MdBlock.code(buf.toString(), codeLang));
      } else {
        blocks.add(_MdBlock.text(buf.toString().trimRight()));
      }
    }
    return blocks;
  }

  Widget _buildBlock(BuildContext context, _MdBlock block) {
    if (block.isCode) {
      return CodeBlockWidget(code: block.content, language: block.lang);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: _InlineMarkdown(text: block.content, kfc: kfc),
    );
  }
}

// ── Model blok markdown ───────────────────────────────────────────────────────

class _MdBlock {
  final bool   isCode;
  final String content;
  final String lang;
  const _MdBlock._({
    required this.isCode,
    required this.content,
    required this.lang,
  });
  factory _MdBlock.text(String t) =>
      _MdBlock._(isCode: false, content: t, lang: '');
  factory _MdBlock.code(String c, String l) =>
      _MdBlock._(isCode: true, content: c, lang: l);
}

// =============================================================================
// PRIVATE: _InlineMarkdown — render satu blok teks dengan heading/bold/italic
// =============================================================================

class _InlineMarkdown extends StatelessWidget {
  final String   text;
  final KmColors kfc;
  const _InlineMarkdown({required this.text, required this.kfc});

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.map((l) => _buildLine(context, l)).toList(),
    );
  }

  Widget _buildLine(BuildContext context, String line) {
    // ── Heading H3
    if (line.startsWith('### ')) {
      return Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 2),
        child: Text(
          line.substring(4),
          style: TextStyle(
            color: kfc.text,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    // ── Heading H2
    if (line.startsWith('## ')) {
      return Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 2),
        child: Text(
          line.substring(3),
          style: TextStyle(
            color: kfc.text,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }
    // ── Heading H1
    if (line.startsWith('# ')) {
      return Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4),
        child: Text(
          line.substring(2),
          style: TextStyle(
            color: kfc.text,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
    }
    // ── List item (- atau *)
    if (line.startsWith('- ') || line.startsWith('* ')) {
      return Padding(
        padding: const EdgeInsets.only(left: 8, top: 1),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('• ',
                style: TextStyle(color: kfc.accent, fontSize: 14)),
            Flexible(
              child: _buildInlineSpans(line.substring(2), context),
            ),
          ],
        ),
      );
    }
    // ── Numbered list (1. 2. dst)
    final numMatch = RegExp(r'^(\d+)\. (.+)').firstMatch(line);
    if (numMatch != null) {
      return Padding(
        padding: const EdgeInsets.only(left: 8, top: 1),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${numMatch.group(1)}. ',
                style: TextStyle(color: kfc.accent, fontSize: 14)),
            Flexible(
              child:
                  _buildInlineSpans(numMatch.group(2) ?? '', context),
            ),
          ],
        ),
      );
    }
    // ── Blockquote
    if (line.startsWith('> ')) {
      return Container(
        margin: const EdgeInsets.only(top: 4, bottom: 4),
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          border: Border(
              left: BorderSide(color: kfc.accent, width: 3)),
          color: kfc.accentSoft,
          borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(4)),
        ),
        child: _buildInlineSpans(line.substring(2), context),
      );
    }
    // ── Garis pemisah
    if (line == '---' || line == '***' || line == '___') {
      return Divider(
          color: kfc.divider, height: 16, thickness: 1);
    }
    // ── Baris kosong
    if (line.trim().isEmpty) {
      return const SizedBox(height: 4);
    }
    // ── Teks biasa dengan inline formatting
    return _buildInlineSpans(line, context);
  }

  Widget _buildInlineSpans(String text, BuildContext context) {
    return Text.rich(
      _parseInline(text),
      style: TextStyle(color: kfc.text, fontSize: 14, height: 1.45),
    );
  }

  TextSpan _parseInline(String src) {
    final spans  = <InlineSpan>[];
    final buffer = StringBuffer();
    int i        = 0;

    void flush() {
      if (buffer.isNotEmpty) {
        spans.add(TextSpan(text: buffer.toString()));
        buffer.clear();
      }
    }

    while (i < src.length) {
      // Bold + italic ***text***
      if (i + 2 < src.length &&
          src[i] == '*' && src[i + 1] == '*' && src[i + 2] == '*') {
        final end = src.indexOf('***', i + 3);
        if (end != -1) {
          flush();
          spans.add(TextSpan(
            text: src.substring(i + 3, end),
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontStyle: FontStyle.italic),
          ));
          i = end + 3;
          continue;
        }
      }
      // Bold **text**
      if (i + 1 < src.length &&
          src[i] == '*' && src[i + 1] == '*') {
        final end = src.indexOf('**', i + 2);
        if (end != -1) {
          flush();
          spans.add(TextSpan(
            text: src.substring(i + 2, end),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ));
          i = end + 2;
          continue;
        }
      }
      // Italic *text*
      if (src[i] == '*') {
        final end = src.indexOf('*', i + 1);
        if (end != -1) {
          flush();
          spans.add(TextSpan(
            text: src.substring(i + 1, end),
            style: const TextStyle(fontStyle: FontStyle.italic),
          ));
          i = end + 1;
          continue;
        }
      }
      // Inline code `text`
      if (src[i] == '`') {
        final end = src.indexOf('`', i + 1);
        if (end != -1) {
          flush();
          spans.add(TextSpan(
            text: src.substring(i + 1, end),
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: kfc.accent,
              backgroundColor: kfc.accentSoft,
            ),
          ));
          i = end + 1;
          continue;
        }
      }
      buffer.write(src[i]);
      i++;
    }
    flush();
    return TextSpan(children: spans);
  }
}
