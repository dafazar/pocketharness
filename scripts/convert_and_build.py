#!/usr/bin/env python3
"""
convert_and_build.py — Pocket Harness v3 Database Builder
Mengkonversi format JSON asli KF ke format database kanmongo v3
dan membangun km_content.db yang lengkap dengan semua data.

Jalankan dari root project:
  python3 scripts/convert_and_build.py
"""
import os, json, sqlite3, re

BASE  = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ORI   = os.path.join(BASE, 'assets', 'data_ori')   # data asli di-copy ke sini
DB    = os.path.join(BASE, 'assets', 'database', 'km_content.db')
os.makedirs(os.path.join(BASE, 'assets', 'database'), exist_ok=True)

def load(path):
    if not os.path.exists(path): return []
    try:
        return json.load(open(path, encoding='utf-8'))
    except: return []

# ── Buat DB ────────────────────────────────────────────────────────────────────
if os.path.exists(DB): os.remove(DB)
conn = sqlite3.connect(DB)
c = conn.cursor()

# ── Schema ─────────────────────────────────────────────────────────────────────
c.executescript("""
CREATE TABLE kanji (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  character TEXT NOT NULL,
  onyomi TEXT, kunyomi TEXT,
  onyomi_hiragana TEXT, onyomi_romaji TEXT, kunyomi_romaji TEXT,
  meaning_id TEXT, meaning_onyomi TEXT, meaning_kunyomi TEXT,
  stroke_count INTEGER DEFAULT 0,
  examples TEXT, example_ja TEXT, example_id TEXT, example_romaji TEXT,
  story TEXT, level TEXT NOT NULL
);
CREATE INDEX idx_kanji_level ON kanji(level);
CREATE INDEX idx_kanji_char  ON kanji(character);

CREATE TABLE kosakata (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  word TEXT NOT NULL, kana TEXT, reading TEXT, romaji TEXT,
  meaning_id TEXT, word_type TEXT, tag TEXT, level TEXT NOT NULL,
  example_ja TEXT, example_id TEXT, example_romaji TEXT, example_kana TEXT
);
CREATE INDEX idx_vocab_level ON kosakata(level);
CREATE INDEX idx_vocab_word  ON kosakata(word);

CREATE TABLE bunpou (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT, pattern TEXT, formula TEXT,
  explanation_id TEXT, level TEXT NOT NULL,
  examples TEXT
);
CREATE INDEX idx_bunpou_level ON bunpou(level);

CREATE TABLE partikel (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  particle TEXT NOT NULL, char_display TEXT,
  usage_label TEXT, meaning_id TEXT,
  explanation_id TEXT, level TEXT NOT NULL,
  examples TEXT
);

CREATE TABLE soal (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  level TEXT NOT NULL, type TEXT NOT NULL, section TEXT,
  question TEXT NOT NULL, kana TEXT, romaji TEXT,
  options TEXT NOT NULL, correct_index INTEGER NOT NULL,
  explanation TEXT, passage TEXT
);
CREATE INDEX idx_soal_level_type ON soal(level, type);

CREATE TABLE kana (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  kana_type TEXT NOT NULL,
  character TEXT NOT NULL,
  romaji TEXT, hiragana TEXT,
  group_name TEXT, row_index INTEGER, col_index INTEGER
);

CREATE TABLE writing_kvg (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  character TEXT NOT NULL,
  strokes_json TEXT,
  stroke_count INTEGER DEFAULT 0
);
""")

print("🗄  Schema dibuat.")

# ══════════════════════════════════════════════════════════════════════
# 1. KANA
# ══════════════════════════════════════════════════════════════════════
print("\n📝 Memproses KANA...")
for ktype in ['hiragana', 'katakana']:
    path = os.path.join(ORI, 'kana', ktype, f'{ktype}.json')
    data = load(path)
    for i, item in enumerate(data):
        c.execute("""INSERT INTO kana(kana_type,character,romaji,hiragana,group_name,row_index,col_index)
                     VALUES(?,?,?,?,?,?,?)""", (
            ktype,
            item.get('character') or item.get('kana',''),
            item.get('romaji',''),
            item.get('hiragana',''),
            item.get('group',''),
            item.get('row', i // 5),
            item.get('col', i % 5),
        ))
    print(f"  ✅ {ktype}: {len(data)} karakter")

# ══════════════════════════════════════════════════════════════════════
# 2. KANJI
# ══════════════════════════════════════════════════════════════════════
print("\n📝 Memproses KANJI...")
kanji_id = 1
for lvl in ['n5','n4','n3','n2','n1']:
    path = os.path.join(ORI, 'kanji', f'kanjin{lvl[1]}', f'kanjin{lvl[1]}_1.json')
    data = load(path)
    for item in data:
        on  = item.get('onyomi', {})
        kun = item.get('kunyomi', {})
        ex  = item.get('example_sentence', {})
        vocab_list = item.get('vocabulary', [])
        examples_str = '\n'.join(
            f"{v.get('word','')} ({v.get('reading','')}) — {v.get('meaning','')}"
            for v in vocab_list[:5]
        )
        c.execute("""INSERT INTO kanji(id,character,onyomi,kunyomi,onyomi_hiragana,onyomi_romaji,
                     kunyomi_romaji,meaning_id,meaning_onyomi,meaning_kunyomi,
                     examples,example_ja,example_id,example_romaji,story,level)
                     VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""", (
            kanji_id,
            item.get('kanji',''),
            on.get('katakana',''),
            kun.get('hiragana',''),
            on.get('hiragana',''),
            on.get('romaji',''),
            kun.get('romaji',''),
            (on.get('meaning','') + ('; ' + kun.get('meaning','') if kun.get('meaning') else '')).strip('; '),
            on.get('meaning',''),
            kun.get('meaning',''),
            examples_str,
            ex.get('japanese',''),
            ex.get('indonesian',''),
            ex.get('romaji',''),
            item.get('story',''),
            lvl.upper(),
        ))
        kanji_id += 1
    print(f"  ✅ Kanji {lvl.upper()}: {len(data)} item")

# ══════════════════════════════════════════════════════════════════════
# 3. KOSAKATA
# ══════════════════════════════════════════════════════════════════════
print("\n📝 Memproses KOSAKATA...")
vocab_id = 1
for lvl in ['n5','n4','n3','n2','n1']:
    path = os.path.join(ORI, 'kosakata', f'vocab_{lvl}', f'vocab_{lvl}.json')
    data = load(path)
    for item in data:
        ex_list = item.get('examples', [])
        ex = ex_list[0] if ex_list else {}
        c.execute("""INSERT INTO kosakata(id,word,kana,reading,romaji,meaning_id,word_type,tag,level,
                     example_ja,example_id,example_romaji,example_kana)
                     VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)""", (
            vocab_id,
            item.get('word',''),
            item.get('kana',''),
            item.get('kana',''),
            ex.get('romaji',''),
            item.get('meaning',''),
            item.get('category',''),
            item.get('tag',''),
            item.get('level', lvl).upper(),
            ex.get('japanese',''),
            ex.get('meaning',''),
            ex.get('romaji',''),
            ex.get('hiragana',''),
        ))
        vocab_id += 1
    print(f"  ✅ Kosakata {lvl.upper()}: {len(data)} item")

# ══════════════════════════════════════════════════════════════════════
# 4. BUNPOU (GRAMMAR)
# ══════════════════════════════════════════════════════════════════════
print("\n📝 Memproses BUNPOU...")
bunpou_id = 1
for lvl in ['n5','n4','n3','n2','n1']:
    path = os.path.join(ORI, 'grammer', f'grammer_{lvl}', f'grammer_{lvl}.json')
    data = load(path)
    for item in data:
        ex_list = item.get('examples', [])
        examples_str = '\n'.join(
            f"{e.get('japanese','')}|{e.get('meaning','')}|{e.get('romaji','')}"
            for e in ex_list[:5]
        )
        c.execute("""INSERT INTO bunpou(id,title,pattern,formula,explanation_id,level,examples)
                     VALUES(?,?,?,?,?,?,?)""", (
            bunpou_id,
            item.get('title',''),
            item.get('title',''),  # pakai title sbg pattern
            item.get('formula',''),
            item.get('explanation',''),
            item.get('level', lvl).upper(),
            examples_str,
        ))
        bunpou_id += 1
    print(f"  ✅ Bunpou {lvl.upper()}: {len(data)} item")

# ══════════════════════════════════════════════════════════════════════
# 5. PARTIKEL
# ══════════════════════════════════════════════════════════════════════
print("\n📝 Memproses PARTIKEL...")
part_id = 1
for lvl in ['n5','n4','n3','n2','n1']:
    path = os.path.join(ORI, 'partikel', f'partikeln{lvl[1]}', f'particles_{lvl}.json')
    data = load(path)
    for item in data:
        ex_list = item.get('examples', [])
        examples_str = '\n'.join(
            f"{e.get('japanese','')} — {e.get('meaning','')}"
            for e in ex_list[:8]
        )
        # char_display: "は (Wa)" → ambil karakter Jepang saja
        char_display = item.get('char', '')
        match = re.search(r'([\u3040-\u30FF\u4E00-\u9FFF]+)', char_display)
        particle_char = match.group(1) if match else char_display
        c.execute("""INSERT INTO partikel(id,particle,char_display,usage_label,meaning_id,
                     explanation_id,level,examples)
                     VALUES(?,?,?,?,?,?,?,?)""", (
            part_id,
            particle_char,
            char_display,
            item.get('usage',''),
            item.get('usage',''),
            item.get('explanation',''),
            lvl.upper(),
            examples_str,
        ))
        part_id += 1
    print(f"  ✅ Partikel {lvl.upper()}: {len(data)} item")

# ══════════════════════════════════════════════════════════════════════
# 6. SOAL — JLPT
# ══════════════════════════════════════════════════════════════════════
print("\n📝 Memproses SOAL JLPT...")
soal_id = 1
for lvl in ['n5','n4','n3','n2','n1']:
    path = os.path.join(ORI, 'soal', 'jlpt', f'jlpt{lvl}', f'jlpt{lvl}_1.json')
    data = load(path)
    for item in data:
        opts = item.get('options', [])
        c.execute("""INSERT INTO soal(id,level,type,section,question,kana,romaji,
                     options,correct_index,explanation,passage)
                     VALUES(?,?,?,?,?,?,?,?,?,?,?)""", (
            soal_id,
            lvl.upper(),
            item.get('type','jlpt'),
            item.get('section',''),
            item.get('question',''),
            item.get('kana',''),
            item.get('romaji',''),
            json.dumps(opts, ensure_ascii=False),
            item.get('answer', 0),
            item.get('explanation',''),
            item.get('passage',''),
        ))
        soal_id += 1
    print(f"  ✅ Soal JLPT {lvl.upper()}: {len(data)} item")

# ── SOAL KANJI ─────────────────────────────────────────────────────────
print("\n📝 Memproses SOAL KANJI...")
for lvl in ['n5','n4','n3','n2','n1']:
    path = os.path.join(ORI, 'soal', 'soalkanji', lvl, f'soal_kanji_{lvl}.json')
    data = load(path)
    for item in data:
        opts = item.get('options', [])
        c.execute("""INSERT INTO soal(id,level,type,section,question,kana,romaji,
                     options,correct_index,explanation,passage)
                     VALUES(?,?,?,?,?,?,?,?,?,?,?)""", (
            soal_id, lvl.upper(), 'kanji',
            item.get('section','kanji'),
            item.get('question',''),
            item.get('kana',''), item.get('romaji',''),
            json.dumps(opts, ensure_ascii=False),
            item.get('answer', item.get('correct_index', 0)),
            item.get('explanation',''), None,
        ))
        soal_id += 1
    print(f"  ✅ Soal Kanji {lvl.upper()}: {len(data)} item")

# ── SOAL KOSAKATA ──────────────────────────────────────────────────────
print("\n📝 Memproses SOAL KOSAKATA...")
for lvl in ['n5','n4','n3','n2','n1']:
    path = os.path.join(ORI, 'soal', 'soalkosakata', lvl, f'soal_kosakata_{lvl}.json')
    data = load(path)
    for item in data:
        opts = item.get('options', [])
        c.execute("""INSERT INTO soal(id,level,type,section,question,kana,romaji,
                     options,correct_index,explanation,passage)
                     VALUES(?,?,?,?,?,?,?,?,?,?,?)""", (
            soal_id, lvl.upper(), 'kosakata',
            item.get('section','vocab'),
            item.get('question',''),
            item.get('kana',''), item.get('romaji',''),
            json.dumps(opts, ensure_ascii=False),
            item.get('answer', item.get('correct_index', 0)),
            item.get('explanation',''), None,
        ))
        soal_id += 1
    print(f"  ✅ Soal Kosakata {lvl.upper()}: {len(data)} item")

# ── SOAL TATA BAHASA ───────────────────────────────────────────────────
print("\n📝 Memproses SOAL TATA BAHASA...")
for lvl in ['n5','n4','n3','n2','n1']:
    path = os.path.join(ORI, 'soal', 'soaltatabahasa', lvl, f'soal_tatabahasa_{lvl}.json')
    data = load(path)
    for item in data:
        opts = item.get('options', [])
        c.execute("""INSERT INTO soal(id,level,type,section,question,kana,romaji,
                     options,correct_index,explanation,passage)
                     VALUES(?,?,?,?,?,?,?,?,?,?,?)""", (
            soal_id, lvl.upper(), 'tatabahasa',
            item.get('section','grammar'),
            item.get('question',''),
            item.get('kana',''), item.get('romaji',''),
            json.dumps(opts, ensure_ascii=False),
            item.get('answer', item.get('correct_index', 0)),
            item.get('explanation',''), None,
        ))
        soal_id += 1
    print(f"  ✅ Soal Tata Bahasa {lvl.upper()}: {len(data)} item")

# ── SOAL PARTIKEL ──────────────────────────────────────────────────────
print("\n📝 Memproses SOAL PARTIKEL...")
for lvl in ['n5','n4','n3','n2','n1']:
    path = os.path.join(ORI, 'soal', 'soalpartikel', lvl, f'soal_partikel_{lvl}.json')
    data = load(path)
    for item in data:
        opts = item.get('options', [])
        c.execute("""INSERT INTO soal(id,level,type,section,question,kana,romaji,
                     options,correct_index,explanation,passage)
                     VALUES(?,?,?,?,?,?,?,?,?,?,?)""", (
            soal_id, lvl.upper(), 'partikel',
            'partikel',
            item.get('question',''),
            item.get('kana',''), item.get('romaji',''),
            json.dumps(opts, ensure_ascii=False),
            item.get('answer', item.get('correct_index', 0)),
            item.get('explanation',''), None,
        ))
        soal_id += 1
    print(f"  ✅ Soal Partikel {lvl.upper()}: {len(data)} item")

# ── SOAL KALIMAT ───────────────────────────────────────────────────────
print("\n📝 Memproses SOAL KALIMAT...")
for lvl in ['n1','n2','n3','n4','n5']:
    path = os.path.join(ORI, 'soal', 'soal kalimat', lvl, f'soal_kalimat_{lvl}.json')
    data = load(path)
    for item in data:
        opts = item.get('options', [])
        c.execute("""INSERT INTO soal(id,level,type,section,question,kana,romaji,
                     options,correct_index,explanation,passage)
                     VALUES(?,?,?,?,?,?,?,?,?,?,?)""", (
            soal_id, lvl.upper(), 'kalimat',
            'kalimat',
            item.get('question',''),
            item.get('kana',''), item.get('romaji',''),
            json.dumps(opts, ensure_ascii=False),
            item.get('answer', item.get('correct_index', 0)),
            item.get('explanation',''),
            item.get('passage',''),
        ))
        soal_id += 1
    if data: print(f"  ✅ Soal Kalimat {lvl.upper()}: {len(data)} item")

# ── SOAL JFT ───────────────────────────────────────────────────────────
print("\n📝 Memproses SOAL JFT...")
for jft_lvl in ['jft_basic','jft_intermediate','jft_advanced']:
    path = os.path.join(ORI, 'soal', 'jft', jft_lvl, f'{jft_lvl}_1.json')
    data = load(path)
    for item in data:
        opts = item.get('options', [])
        c.execute("""INSERT INTO soal(id,level,type,section,question,kana,romaji,
                     options,correct_index,explanation,passage)
                     VALUES(?,?,?,?,?,?,?,?,?,?,?)""", (
            soal_id, jft_lvl.upper(), 'jft',
            item.get('section','jft'),
            item.get('question',''),
            item.get('kana',''), item.get('romaji',''),
            json.dumps(opts, ensure_ascii=False),
            item.get('answer', 0),
            item.get('explanation',''),
            item.get('passage',''),
        ))
        soal_id += 1
    print(f"  ✅ Soal JFT {jft_lvl}: {len(data)} item")

# ── WRITING KVG ────────────────────────────────────────────────────────
print("\n📝 Memproses WRITING KVG...")
kvg_path = os.path.join(ORI, 'writing', 'kanji', 'kvg.json')
kvg_data = load(kvg_path)
kvg_count = 0
# KVG format bisa berupa dict {char: {s:[paths], n:[points]}} atau list
if isinstance(kvg_data, dict):
    items_iter = list(kvg_data.items())[:5000]
    for char, val in items_iter:
        strokes = val.get('s', []) if isinstance(val, dict) else []
        c.execute("INSERT INTO writing_kvg(character,strokes_json,stroke_count) VALUES(?,?,?)", (
            char,
            json.dumps(strokes, ensure_ascii=False),
            len(strokes),
        ))
        kvg_count += 1
else:
    for item in kvg_data[:5000]:
        char = item.get('character','') or item.get('kanji','')
        strokes = item.get('strokes') or item.get('paths') or item.get('s') or []
        if char:
            c.execute("INSERT INTO writing_kvg(character,strokes_json,stroke_count) VALUES(?,?,?)", (
                char,
                json.dumps(strokes, ensure_ascii=False),
                len(strokes),
            ))
            kvg_count += 1
print(f"  ✅ KVG: {kvg_count} karakter")

# ── Commit ──────────────────────────────────────────────────────────────
conn.commit()

# ── Hitung total ────────────────────────────────────────────────────────
counts = {}
for tbl in ['kanji','kosakata','bunpou','partikel','soal','kana','writing_kvg']:
    counts[tbl] = c.execute(f"SELECT COUNT(*) FROM {tbl}").fetchone()[0]
conn.close()

sz_mb = os.path.getsize(DB) / (1024*1024)
print(f"""
{'='*60}
✨ DATABASE SELESAI: {DB}
   Ukuran  : {sz_mb:.1f} MB
   Kanji   : {counts['kanji']:,}
   Kosakata: {counts['kosakata']:,}
   Bunpou  : {counts['bunpou']:,}
   Partikel: {counts['partikel']:,}
   Soal    : {counts['soal']:,}
   Kana    : {counts['kana']:,}
   KVG     : {counts['writing_kvg']:,}
   TOTAL   : {sum(counts.values()):,} rows
{'='*60}
""")
