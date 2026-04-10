import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kanmongo/core/theme/app_theme.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:kanmongo/core/security/secure_db_key_service.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kanmongo/shared/widgets/screen_theme_banner.dart';
import 'package:kanmongo/core/theme/km_colors.dart';
import 'package:kanmongo/shared/widgets/view_toggle.dart';
import 'package:kanmongo/core/theme/theme_provider.dart';
import 'package:kanmongo/core/theme/app_theme_service.dart';
import 'package:kanmongo/shared/widgets/wallpaper_background.dart';
import 'package:kanmongo/shared/widgets/back_handler.dart';
import 'package:kanmongo/features/notes/data/note_model.dart';

// ─── Xiaomi-style note card colors ──────────────────────────────────────────
// Note: KmColors.of(context) cannot be used in top-level const lists.
// Using KmColors.dark fallback values directly instead.
const List<Color> _noteColors = [
  Color(0xFF1E293B),
  Color(0xFF111111), // KmColors.dark.card
  Color(0xFF1E1A2E),
  Color(0xFF0F2027),
  Color(0xFF1A2E1E),
  Color(0xFF2E1A1A),
  Color(0xFF2E2A1A),
  Color(0xFF1A2A2E),
];

const List<Color> _noteAccents = [
  Color(0xFFFFFFFF), // KmColors.dark.accent
  Color(0xFFFFFFFF), // KmColors.dark.accent
  Color(0xFFA78BFA),
  Color(0xFFFFFFFF), // KmColors.dark.accent
  Color(0xFFFFFFFF), // KmColors.dark.accent
  Color(0xFFFFFFFF), // KmColors.dark.accent
  Color(0xFFFFFFFF), // KmColors.dark.accent
  Color(0xFF22D3EE),
];

class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});
  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {

  Database? _db;
  List<NoteModel> _notes = [];
  String _search = '';
  bool _isGrid = false; // default list
  int _lastColorIndex = 0; // warna terakhir dipilih user

  static const _kLastColorKey = 'kmg.notes.last_color';

  @override
  void initState() {
    super.initState();
    _initDb();
    _loadLastColor();
    loadViewMode('notes', defaultValue: true).then((v) { if (mounted) setState(() => _isGrid = v); });
  }

  Future<void> _loadLastColor() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      if (mounted) setState(() {
        _lastColorIndex = (prefs.getInt(_kLastColorKey) ?? 0)
            .clamp(0, _noteColors.length - 1);
      });
    }
  }

  Future<void> _saveLastColor(int colorIndex) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLastColorKey, colorIndex);
    if (mounted) setState(() => _lastColorIndex = colorIndex);
  }

  Future<void> _initDb() async {
    final dbPath = await getDatabasesPath();
    final keyService = SecureDbKeyService.instance;
    final password   = keyService.hasKeys ? keyService.userKey : null;

    _db = await openDatabase(
      p.join(dbPath, 'notes.db'),
      password: password, // AES-256 SQLCipher enkripsi
      version: 2,
      onCreate: (db, v) => db.execute(
        'CREATE TABLE notes (id TEXT PRIMARY KEY, title TEXT, content TEXT, createdAt INTEGER, updatedAt INTEGER, tags TEXT, colorIndex INTEGER)',
      ),
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) {
          try { await db.execute('ALTER TABLE notes ADD COLUMN colorIndex INTEGER DEFAULT 0'); } catch (_) {}
        }
      },
    );
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    final maps = await _db!.query('notes', orderBy: 'updatedAt DESC');
    if (mounted) setState(() => _notes = maps.map(NoteModel.fromMap).toList());
  }

  Future<void> _saveNote(NoteModel note) async {
    await _db!.insert('notes', note.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    _loadNotes();
  }

  Future<void> _deleteNote(String id) async {
    await _db!.delete('notes', where: 'id = ?', whereArgs: [id]);
    _loadNotes();
  }

  void _openEditor({NoteModel? note}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _NoteEditorScreen(
          note: note,
          colorIndex: note != null
              ? note.colorIndex
              : _lastColorIndex, // gunakan warna terakhir dipilih, bukan random
          onSave: (title, content, colorIdx) {
            // Simpan warna yang dipilih sebagai default untuk catatan berikutnya
            _saveLastColor(colorIdx);
            final now = DateTime.now();
            _saveNote(NoteModel(
              id: note?.id ?? const Uuid().v4(),
              title: title,
              content: content,
              createdAt: note?.createdAt ?? now,
              updatedAt: now,
              colorIndex: colorIdx,
            ));
          },
          onDelete: note != null ? () => _deleteNote(note.id) : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild saat pack tema berubah
    ref.watch(themePackProvider);
    final filtered = _search.isEmpty
        ? _notes
        : _notes.where((n) =>
            n.title.toLowerCase().contains(_search) ||
            n.content.toLowerCase().contains(_search)).toList();

    return Scaffold(
      backgroundColor: wallpaperAwareBg(context, ref, KmColors.of(context).bg),
      body: NestedScrollView(
        headerSliverBuilder: (ctx, inner) => [
          SliverAppBar(
            backgroundColor: wallpaperAwareBg(context, ref, KmColors.of(context).bg),
            expandedHeight: 100,
            floating: true,
            snap: true,
            pinned: true,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_rounded, color: KmColors.of(context).text),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              ViewToggleButton(isGrid: _isGrid, onToggle: () { saveViewMode('notes', !_isGrid); setState(() => _isGrid = !_isGrid); }),
              const SizedBox(width: 4),
            ],
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 56, bottom: 16),
              title: Text(
                'ノート  Catatan',
                style: TextStyle(color: KmColors.of(context).text, fontWeight: FontWeight.bold, fontSize: 18),
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [KmColors.of(context).bg, KmColors.of(context).card],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
          ),
        ],
        body: Column(children: [
          // Banner tema dari theme_config.json
          ScreenThemeBanner(screenKey: 'notes', height: 90),
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
            child: Container(
              decoration: BoxDecoration(
                color: KmColors.of(context).card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: KmColors.of(context).border),
              ),
              child: TextField(
                style: TextStyle(color: KmColors.of(context).text),
                decoration: InputDecoration(
                  hintText: 'Cari catatan...',
                  hintStyle: TextStyle(color: KmColors.of(context).textMuted),
                  prefixIcon: Icon(Icons.search_rounded, color: KmColors.of(context).textMuted, size: 20),
                  suffixIcon: _search.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.close_rounded, color: KmColors.of(context).textMuted, size: 18),
                          onPressed: () => setState(() => _search = ''),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onChanged: (v) => setState(() => _search = v.toLowerCase()),
              ),
            ),
          ),

          // Count chip
          if (filtered.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: KmColors.of(context).accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: KmColors.of(context).accent.withValues(alpha: 0.3)),
                  ),
                  child: Text('${filtered.length} catatan',
                      style: TextStyle(color: KmColors.of(context).accent, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ),
            ),

          Expanded(
            child: filtered.isEmpty
                ? _buildEmpty()
                : _isGrid
                    ? _buildGrid(filtered)
                    : _buildList(filtered),
          ),
        ]),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        backgroundColor: KmColors.of(context).accent,
        icon: Icon(Icons.edit_outlined, color: KmColors.of(context).text),
        label: Text('Catatan Baru', style: TextStyle(color: KmColors.of(context).text, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildEmpty() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 90, height: 90,
        decoration: BoxDecoration(color: KmColors.of(context).card, borderRadius: BorderRadius.circular(24), border: Border.all(color: KmColors.of(context).border)),
        child: Icon(Icons.sticky_note_2_outlined, color: KmColors.of(context).textMuted, size: 44),
      ),
      SizedBox(height: 16),
      Text('Belum ada catatan', style: TextStyle(color: KmColors.of(context).text, fontSize: 16, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Text('Ketuk tombol di bawah untuk\nmembuat catatan baru',
          style: TextStyle(color: KmColors.of(context).textMuted, fontSize: 13, height: 1.5), textAlign: TextAlign.center),
    ]),
  );

  Widget _buildGrid(List<NoteModel> notes) => GridView.builder(
    padding: const EdgeInsets.fromLTRB(14, 8, 14, 100),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 0.85,
    ),
    itemCount: notes.length,
    itemBuilder: (ctx, i) => _NoteGridCard(
      note: notes[i],
      colorIndex: notes[i].colorIndex % _noteColors.length,
      onTap: () => _openEditor(note: notes[i]),
      onDelete: () => _deleteNote(notes[i].id),
    ),
  );

  Widget _buildList(List<NoteModel> notes) => ListView.separated(
    padding: const EdgeInsets.fromLTRB(14, 8, 14, 100),
    itemCount: notes.length,
    separatorBuilder: (_, __) => const SizedBox(height: 8),
    itemBuilder: (ctx, i) => _NoteListCard(
      note: notes[i],
      colorIndex: notes[i].colorIndex % _noteColors.length,
      onTap: () => _openEditor(note: notes[i]),
      onDelete: () => _deleteNote(notes[i].id),
    ),
  );
}

// ─── Grid Card ───────────────────────────────────────────────────────────────
class _NoteGridCard extends StatelessWidget {
  final NoteModel note;
  final int colorIndex;
  final VoidCallback onTap, onDelete;
  const _NoteGridCard({required this.note, required this.colorIndex, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final bg = _noteColors[colorIndex];
    final accent = _noteAccents[colorIndex];
    return GestureDetector(
      onTap: onTap,
      onLongPress: () => _showMenu(context),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: accent.withValues(alpha: 0.25)),
          boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.05), blurRadius: 12, spreadRadius: 1)],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 28, height: 4,
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 10),
            if (note.title.isNotEmpty) ...[
              Text(note.title, style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 14, height: 1.3),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
            ],
            Expanded(
              child: Text(note.content,
                  style: TextStyle(color: KmColors.of(context).textSub, fontSize: 12, height: 1.5),
                  overflow: TextOverflow.fade),
            ),
            const SizedBox(height: 8),
            Text(_formatDate(note.updatedAt), style: TextStyle(color: accent.withValues(alpha: 0.5), fontSize: 10)),
          ]),
        ),
      ),
    );
  }

  void _showMenu(BuildContext ctx) => showModalBottomSheet(
    context: ctx,
    backgroundColor: KmColors.of(ctx).card,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 36, height: 3, decoration: BoxDecoration(color: KmColors.of(ctx).textMuted, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        ListTile(leading: Icon(Icons.edit_outlined, color: KmColors.of(ctx).textSub), title: Text('Edit', style: TextStyle(color: KmColors.of(ctx).text)),
            onTap: () { Navigator.pop(_); onTap(); }),
        ListTile(leading: Icon(Icons.delete_outline, color: KmColors.of(ctx).accent), title: Text('Hapus', style: TextStyle(color: KmColors.of(ctx).accent)),
            onTap: () { Navigator.pop(_); onDelete(); }),
        const SizedBox(height: 8),
      ]),
    ),
  );

  String _formatDate(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m lalu';
    if (diff.inHours < 24) return '${diff.inHours}j lalu';
    if (diff.inDays < 7) return '${diff.inDays}h lalu';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

// ─── List Card ───────────────────────────────────────────────────────────────
class _NoteListCard extends StatelessWidget {
  final NoteModel note;
  final int colorIndex;
  final VoidCallback onTap, onDelete;
  const _NoteListCard({required this.note, required this.colorIndex, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final bg = _noteColors[colorIndex];
    final accent = _noteAccents[colorIndex];
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: accent.withValues(alpha: 0.25))),
        child: Row(children: [
          Container(width: 4, height: 56, decoration: BoxDecoration(color: accent.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (note.title.isNotEmpty) Text(note.title, style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 14)),
            if (note.title.isNotEmpty) SizedBox(height: 4),
            Text(note.content, style: TextStyle(color: KmColors.of(context).textSub, fontSize: 13, height: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            Text(_formatDate(note.updatedAt), style: TextStyle(color: accent.withValues(alpha: 0.5), fontSize: 11)),
          ])),
          IconButton(icon: Icon(Icons.delete_outline, color: KmColors.of(context).textMuted, size: 20), onPressed: onDelete),
        ]),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m lalu';
    if (diff.inHours < 24) return '${diff.inHours}j lalu';
    if (diff.inDays < 7) return '${diff.inDays}h lalu';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

// ─── Full-screen Note Editor (Xiaomi style) ───────────────────────────────────
class _NoteEditorScreen extends ConsumerStatefulWidget {
  final NoteModel? note;
  final int colorIndex;
  final void Function(String title, String content, int colorIdx) onSave;
  final VoidCallback? onDelete;
  const _NoteEditorScreen({this.note, required this.colorIndex, required this.onSave, this.onDelete});

  @override
  ConsumerState<_NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<_NoteEditorScreen> {

  late TextEditingController _titleCtrl;
  late TextEditingController _contentCtrl;
  late int _selectedColor;
  bool _showColorPicker = false;
  late FocusNode _contentFocus;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.note?.title ?? '');
    _contentCtrl = TextEditingController(text: widget.note?.content ?? '');
    _selectedColor = widget.colorIndex;
    _contentFocus = FocusNode();
    if (widget.note == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _contentFocus.requestFocus());
    }
    _contentCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  void _save() {
    final title = _titleCtrl.text.trim();
    final content = _contentCtrl.text.trim();
    if (title.isEmpty && content.isEmpty) { Navigator.pop(context); return; }
    widget.onSave(title.isEmpty ? 'Tanpa Judul' : title, content, _selectedColor);
    Navigator.pop(context);
  }

  void _insertText(String text, {int cursorBack = 0}) {
    final ctrl = _contentCtrl;
    final sel = ctrl.selection;
    final str = ctrl.text;
    final pos = sel.isValid ? sel.baseOffset : str.length;
    final newStr = str.substring(0, pos) + text + str.substring(pos);
    ctrl.text = newStr;
    ctrl.selection = TextSelection.collapsed(offset: pos + text.length - cursorBack);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bg = _noteColors[_selectedColor];
    final accent = _noteAccents[_selectedColor];

    // Cek apakah ada perubahan dari original
    final hasContent = _titleCtrl.text.trim().isNotEmpty || _contentCtrl.text.trim().isNotEmpty;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        // Jika ada konten → auto-save dan keluar (sama seperti tombol back di AppBar)
        _save();
      },
      child: Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: IconButton(icon: Icon(Icons.arrow_back_ios_rounded, color: KmColors.of(context).text), onPressed: _save),
        title: Text(
          widget.note == null ? 'Catatan Baru' : 'Edit Catatan',
          style: TextStyle(color: accent, fontSize: 14, fontWeight: FontWeight.w600),
        ),
        actions: [
          GestureDetector(
            onTap: () => setState(() => _showColorPicker = !_showColorPicker),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 32, height: 32,
              decoration: BoxDecoration(color: accent.withValues(alpha: 0.15), shape: BoxShape.circle, border: Border.all(color: accent.withValues(alpha: 0.5))),
              child: Icon(Icons.palette_outlined, color: accent, size: 16),
            ),
          ),
          const SizedBox(width: 4),
          if (widget.onDelete != null)
            IconButton(icon: Icon(Icons.delete_outline, color: KmColors.of(context).textMuted, size: 20),
                onPressed: () { widget.onDelete!(); Navigator.pop(context); }),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _save,
              child: Text('Simpan', style: TextStyle(color: accent, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
      body: Column(children: [
        // Color picker
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: _showColorPicker ? 52 : 0,
          child: _showColorPicker ? Container(
            color: KmColors.of(context).bg.withValues(alpha: 0.3),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _noteColors.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => GestureDetector(
                onTap: () {
                  // Terapkan warna dulu, tutup picker setelah frame berikutnya
                  if (mounted) setState(() => _selectedColor = i);
                  Future.delayed(const Duration(milliseconds: 150), () {
                    if (mounted) setState(() => _showColorPicker = false);
                  });
                },
                child: Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(
                    color: _noteColors[i], shape: BoxShape.circle,
                    border: Border.all(
                      color: _selectedColor == i ? _noteAccents[i] : _noteAccents[i].withValues(alpha: 0.3),
                      width: _selectedColor == i ? 2.5 : 1,
                    ),
                  ),
                  child: _selectedColor == i ? Icon(Icons.check, color: _noteAccents[i], size: 16) : null,
                ),
              ),
            ),
          ) : const SizedBox(),
        ),

        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Column(children: [
              // Title field
              TextField(
                controller: _titleCtrl,
                style: TextStyle(color: KmColors.of(context).text, fontSize: 22, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  hintText: 'Judul',
                  hintStyle: TextStyle(color: KmColors.of(context).text.withValues(alpha: 0.25), fontSize: 22, fontWeight: FontWeight.bold),
                  border: InputBorder.none,
                ),
                maxLines: null,
              ),
              // Divider
              Row(children: [
                Expanded(child: Container(height: 1, color: KmColors.of(context).text.withValues(alpha: 0.07))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(_formatNow(), style: TextStyle(color: KmColors.of(context).text.withValues(alpha: 0.3), fontSize: 10)),
                ),
                Expanded(child: Container(height: 1, color: KmColors.of(context).text.withValues(alpha: 0.07))),
              ]),
              const SizedBox(height: 10),
              // Content field
              Expanded(
                child: TextField(
                  controller: _contentCtrl,
                  focusNode: _contentFocus,
                  style: TextStyle(color: KmColors.of(context).textSub, fontSize: 15, height: 1.65),
                  decoration: InputDecoration(
                    hintText: 'Mulai menulis...',
                    hintStyle: TextStyle(color: KmColors.of(context).text.withValues(alpha: 0.2), fontSize: 15),
                    border: InputBorder.none,
                  ),
                  maxLines: null, expands: true,
                  textAlignVertical: TextAlignVertical.top,
                ),
              ),
            ]),
          ),
        ),

        // Toolbar (Xiaomi style)
        Container(
          decoration: BoxDecoration(
            color: KmColors.of(context).bg.withValues(alpha: 0.85),
            border: Border(top: BorderSide(color: KmColors.of(context).text.withValues(alpha: 0.05))),
          ),
          padding: EdgeInsets.only(
            left: 4, right: 12, top: 6,
            bottom: MediaQuery.of(context).viewInsets.bottom > 0 ? 6 : MediaQuery.of(context).padding.bottom + 6,
          ),
          child: Row(children: [
            IconButton(icon: Icon(Icons.format_bold, color: KmColors.of(context).textSub, size: 20), onPressed: () => _insertText('**teks tebal**', cursorBack: 13)),
            IconButton(icon: Icon(Icons.format_italic, color: KmColors.of(context).textSub, size: 20), onPressed: () => _insertText('_teks miring_', cursorBack: 12)),
            IconButton(icon: Icon(Icons.format_list_bulleted, color: KmColors.of(context).textSub, size: 20), onPressed: () => _insertText('\n• ')),
            IconButton(icon: Icon(Icons.check_box_outline_blank, color: KmColors.of(context).textSub, size: 20), onPressed: () => _insertText('\n☐ ')),
            IconButton(icon: Icon(Icons.horizontal_rule, color: KmColors.of(context).textSub, size: 20), onPressed: () => _insertText('\n─────────\n')),
            const Spacer(),
            Text('${_contentCtrl.text.length}',
                style: TextStyle(color: KmColors.of(context).text.withValues(alpha: 0.25), fontSize: 11)),
          ]),
        ),
      ]),
    ),
    );
  }

  String _formatNow() {
    final now = DateTime.now();
    const mo = ['Jan','Feb','Mar','Apr','Mei','Jun','Jul','Agu','Sep','Okt','Nov','Des'];
    return '${now.day} ${mo[now.month-1]} ${now.year}, ${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}';
  }
}
