// lib/data/services/history_service.dart
// Pocket Harness — History Service
// v3 (Sesi 1): Tambah kolom ai_mode, model_name, attachments_json, web_sources_json
//              ke chat_messages. Tambah 5 method baru untuk ChatSession (chat_models).
//   - saveChatSession / loadAllChatSessions / loadChatSession
//   - deleteChatSession / updateSessionTitle
//   - AiHistoryEntry lama tetap dipertahankan (backward compat)
// =============================================================================

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:pocketharness/core/security/secure_db_key_service.dart';
import 'package:pocketharness/data/models/chat_models.dart';

// ── Models ────────────────────────────────────────────────────────────────────

class AiHistoryEntry {
  final int    id;
  final String sessionId;
  final String feature;
  final String summary;
  final int    createdAt;

  const AiHistoryEntry({
    required this.id,
    required this.sessionId,
    required this.feature,
    required this.summary,
    required this.createdAt,
  });

  DateTime get date => DateTime.fromMillisecondsSinceEpoch(createdAt);

  String get featureLabel {
    switch (feature) {
      case 'chat':   return 'AI Chat';
      case 'ocr':    return 'OCR Scan';
      case 'reader': return 'Reader';
      default:       return feature;
    }
  }

  Map<String, dynamic> toMap() => {
    'session_id': sessionId,
    'feature':    feature,
    'summary':    summary,
    'created_at': createdAt,
  };

  factory AiHistoryEntry.fromMap(Map<String, dynamic> m) => AiHistoryEntry(
    id:         m['id'] as int,
    sessionId:  m['session_id'] as String? ?? '',
    feature:    m['feature'] as String? ?? '',
    summary:    m['summary'] as String? ?? '',
    createdAt:  m['created_at'] as int? ?? 0,
  );
}

// Model untuk persistent chat session
class PersistedChatSession {
  final String id;
  final String title;
  final int    createdAt;
  final int    updatedAt;
  final List<PersistedChatMessage> messages;

  PersistedChatSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.messages = const [],
  });

  Map<String, dynamic> toMap() => {
    'id':         id,
    'title':      title,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  factory PersistedChatSession.fromMap(
      Map<String, dynamic> m, List<PersistedChatMessage> msgs) =>
      PersistedChatSession(
        id:        m['id'] as String? ?? '',
        title:     m['title'] as String? ?? 'Chat Baru',
        createdAt: m['created_at'] as int? ?? 0,
        updatedAt: m['updated_at'] as int? ?? 0,
        messages:  msgs,
      );
}

// Model untuk persistent chat message
class PersistedChatMessage {
  final int    id;
  final String sessionId;
  final String role;     // 'user' atau 'assistant'
  final String content;
  final int    createdAt;

  PersistedChatMessage({
    this.id = 0,
    required this.sessionId,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'session_id': sessionId,
    'role':       role,
    'content':    content,
    'created_at': createdAt,
  };

  factory PersistedChatMessage.fromMap(Map<String, dynamic> m) =>
      PersistedChatMessage(
        id:        m['id'] as int? ?? 0,
        sessionId: m['session_id'] as String? ?? '',
        role:      m['role'] as String? ?? 'user',
        content:   m['content'] as String? ?? '',
        createdAt: m['created_at'] as int? ?? 0,
      );
}

// ── Service ───────────────────────────────────────────────────────────────────
class HistoryService {
  HistoryService._();
  static final HistoryService instance = HistoryService._();

  Database? _db;

  Future<void> _ensureDb() async {
    if (_db != null) return;
    final dir    = await getApplicationDocumentsDirectory();
    final dbPath = join(dir.path, 'km_history.db');
    final keyService = SecureDbKeyService.instance;
    final password   = keyService.hasKeys ? keyService.userKey : null;

    _db = await openDatabase(
      dbPath,
      password: password,
      version: 3, // v3 Sesi 1: tambah kolom extended di chat_messages
      onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS ai_history (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id  TEXT NOT NULL,
            feature     TEXT NOT NULL DEFAULT 'chat',
            summary     TEXT NOT NULL DEFAULT '',
            created_at  INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS chat_sessions (
            id               TEXT PRIMARY KEY,
            title            TEXT NOT NULL DEFAULT 'Chat Baru',
            created_at       INTEGER NOT NULL,
            updated_at       INTEGER NOT NULL,
            last_ai_mode     TEXT,
            last_model_name  TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS chat_messages (
            id                INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id        TEXT NOT NULL,
            role              TEXT NOT NULL,
            content           TEXT NOT NULL,
            created_at        INTEGER NOT NULL,
            ai_mode           TEXT,
            model_name        TEXT,
            attachments_json  TEXT,
            web_sources_json  TEXT,
            error             TEXT,
            FOREIGN KEY (session_id) REFERENCES chat_sessions(id) ON DELETE CASCADE
          )
        ''');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_chat_messages_session ON chat_messages(session_id)');
      },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS chat_sessions (
              id               TEXT PRIMARY KEY,
              title            TEXT NOT NULL DEFAULT 'Chat Baru',
              created_at       INTEGER NOT NULL,
              updated_at       INTEGER NOT NULL,
              last_ai_mode     TEXT,
              last_model_name  TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS chat_messages (
              id                INTEGER PRIMARY KEY AUTOINCREMENT,
              session_id        TEXT NOT NULL,
              role              TEXT NOT NULL,
              content           TEXT NOT NULL,
              created_at        INTEGER NOT NULL,
              ai_mode           TEXT,
              model_name        TEXT,
              attachments_json  TEXT,
              web_sources_json  TEXT,
              error             TEXT,
              FOREIGN KEY (session_id) REFERENCES chat_sessions(id) ON DELETE CASCADE
            )
          ''');
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_chat_messages_session ON chat_messages(session_id)');
        }
        if (oldV < 3) {
          for (final sql in [
            'ALTER TABLE chat_messages ADD COLUMN ai_mode TEXT',
            'ALTER TABLE chat_messages ADD COLUMN model_name TEXT',
            'ALTER TABLE chat_messages ADD COLUMN attachments_json TEXT',
            'ALTER TABLE chat_messages ADD COLUMN web_sources_json TEXT',
            'ALTER TABLE chat_messages ADD COLUMN error TEXT',
          ]) {
            try { await db.execute(sql); } catch (_) {}
          }
          for (final sql in [
            'ALTER TABLE chat_sessions ADD COLUMN last_ai_mode TEXT',
            'ALTER TABLE chat_sessions ADD COLUMN last_model_name TEXT',
          ]) {
            try { await db.execute(sql); } catch (_) {}
          }
        }
      },
    );
  }

  // ── AiHistoryEntry methods (backward compat) ──────────────────────────────

  Future<void> saveEntry(AiHistoryEntry entry) async {
    await _ensureDb();
    try {
      await _db!.insert('ai_history', entry.toMap());
    } catch (e) {
      debugPrint('[HistoryService] save error: $e');
    }
  }

  Future<List<AiHistoryEntry>> getAll({int limit = 50}) async {
    await _ensureDb();
    try {
      final rows = await _db!.query(
        'ai_history',
        orderBy: 'created_at DESC',
        limit: limit,
      );
      return rows.map(AiHistoryEntry.fromMap).toList();
    } catch (e) {
      debugPrint('[HistoryService] getAll error: $e');
      return [];
    }
  }

  Future<void> deleteEntry(int id) async {
    await _ensureDb();
    await _db!.delete('ai_history', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearAll() async {
    await _ensureDb();
    await _db!.delete('ai_history');
  }

  // ── PersistedChatSession methods (FIX: new persistent chat) ──────────────

  /// Simpan atau update sesi chat beserta semua pesan-nya (upsert)
  Future<void> saveSession(PersistedChatSession session) async {
    await _ensureDb();
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _db!.transaction((txn) async {
        // Upsert session metadata
        await txn.insert(
          'chat_sessions',
          {
            'id':         session.id,
            'title':      session.title,
            'created_at': session.createdAt,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        // Hapus messages lama lalu insert ulang
        await txn.delete('chat_messages',
            where: 'session_id = ?', whereArgs: [session.id]);
        for (final msg in session.messages) {
          await txn.insert('chat_messages', {
            'session_id': session.id,
            'role':       msg.role,
            'content':    msg.content,
            'created_at': msg.createdAt,
          });
        }
      });
    } catch (e) {
      debugPrint('[HistoryService] saveSession error: $e');
    }
  }

  /// Load semua sessions dengan messages, diurutkan terbaru dulu
  Future<List<PersistedChatSession>> loadAllSessions({int limit = 30}) async {
    await _ensureDb();
    try {
      final sessionRows = await _db!.query(
        'chat_sessions',
        orderBy: 'updated_at DESC',
        limit: limit,
      );
      final List<PersistedChatSession> result = [];
      for (final row in sessionRows) {
        final sid = row['id'] as String;
        final msgRows = await _db!.query(
          'chat_messages',
          where: 'session_id = ?',
          whereArgs: [sid],
          orderBy: 'created_at ASC',
        );
        final msgs = msgRows.map(PersistedChatMessage.fromMap).toList();
        result.add(PersistedChatSession.fromMap(row, msgs));
      }
      return result;
    } catch (e) {
      debugPrint('[HistoryService] loadAllSessions error: $e');
      return [];
    }
  }

  /// Hapus sesi + semua pesannya
  Future<void> deleteSession(String sessionId) async {
    await _ensureDb();
    try {
      await _db!.transaction((txn) async {
        await txn.delete('chat_messages',
            where: 'session_id = ?', whereArgs: [sessionId]);
        await txn.delete('chat_sessions',
            where: 'id = ?', whereArgs: [sessionId]);
      });
    } catch (e) {
      debugPrint('[HistoryService] deleteSession error: $e');
    }
  }


  // ── ChatSession methods v3 (Sesi 1) — pakai ChatMessage dari chat_models ──

  /// Simpan atau update ChatSession (upsert) beserta semua ChatMessage-nya
  Future<void> saveChatSession(ChatSession session) async {
    await _ensureDb();
    try {
      await _db!.transaction((txn) async {
        await txn.insert(
          'chat_sessions',
          {
            'id': session.id,
            'title': session.title,
            'created_at': session.createdAt.millisecondsSinceEpoch,
            'updated_at': session.updatedAt.millisecondsSinceEpoch,
            'last_ai_mode': session.lastAiMode?.name,
            'last_model_name': session.lastModelName,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await txn.delete(
          'chat_messages',
          where: 'session_id = ?',
          whereArgs: [session.id],
        );
        for (final msg in session.messages) {
          final map = msg.toMap();
          await txn.insert('chat_messages', {
            'session_id': session.id,
            'role': map['role'],
            'content': map['content'],
            'created_at': map['created_at'],
            'ai_mode': map['ai_mode'],
            'model_name': map['model_name'],
            'attachments_json': map['attachments_json'],
            'web_sources_json': map['web_sources_json'],
            'error': map['error'],
          });
        }
      });
    } catch (e) {
      debugPrint('[HistoryService] saveChatSession error: $e');
    }
  }

  /// Load semua ChatSession + messages, diurutkan terbaru dulu
  Future<List<ChatSession>> loadAllChatSessions({int limit = 50}) async {
    await _ensureDb();
    try {
      final sessionRows = await _db!.query(
        'chat_sessions',
        orderBy: 'updated_at DESC',
        limit: limit,
      );
      final List<ChatSession> result = [];
      for (final row in sessionRows) {
        final sid = row['id'] as String;
        final msgRows = await _db!.query(
          'chat_messages',
          where: 'session_id = ?',
          whereArgs: [sid],
          orderBy: 'created_at ASC',
        );
        final messages = msgRows.map((r) {
          final m = Map<String, dynamic>.from(r);
          m['id'] = m['id']?.toString() ?? '';
          return ChatMessage.fromMap(m);
        }).toList();
        result.add(ChatSession.fromMap(row, messages));
      }
      return result;
    } catch (e) {
      debugPrint('[HistoryService] loadAllChatSessions error: $e');
      return [];
    }
  }

  /// Load satu ChatSession beserta semua messages-nya
  Future<ChatSession?> loadChatSession(String sessionId) async {
    await _ensureDb();
    try {
      final sessionRows = await _db!.query(
        'chat_sessions',
        where: 'id = ?',
        whereArgs: [sessionId],
        limit: 1,
      );
      if (sessionRows.isEmpty) return null;
      final msgRows = await _db!.query(
        'chat_messages',
        where: 'session_id = ?',
        whereArgs: [sessionId],
        orderBy: 'created_at ASC',
      );
      final messages = msgRows.map((r) {
        final m = Map<String, dynamic>.from(r);
        m['id'] = m['id']?.toString() ?? '';
        return ChatMessage.fromMap(m);
      }).toList();
      return ChatSession.fromMap(sessionRows.first, messages);
    } catch (e) {
      debugPrint('[HistoryService] loadChatSession error: $e');
      return null;
    }
  }

  /// Hapus ChatSession (messages terhapus otomatis via ON DELETE CASCADE)
  Future<void> deleteChatSession(String sessionId) async {
    await _ensureDb();
    try {
      await _db!.delete(
        'chat_sessions',
        where: 'id = ?',
        whereArgs: [sessionId],
      );
    } catch (e) {
      debugPrint('[HistoryService] deleteChatSession error: $e');
    }
  }

  /// Update judul sesi dan updated_at timestamp
  Future<void> updateSessionTitle(String sessionId, String title) async {
    await _ensureDb();
    try {
      await _db!.update(
        'chat_sessions',
        {
          'title': title,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [sessionId],
      );
    } catch (e) {
      debugPrint('[HistoryService] updateSessionTitle error: $e');
    }
  }


  // ── D-003: Pagination ─────────────────────────────────────────────────────

  static const int kPageSize = 20;

  Future<List<ChatSession>> loadChatSessionsPaged({
    required int offset,
    int limit = kPageSize,
  }) async {
    await _ensureDb();
    try {
      final sessionRows = await _db!.query(
        'chat_sessions',
        orderBy: 'updated_at DESC',
        limit: limit,
        offset: offset,
      );
      final List<ChatSession> result = [];
      for (final row in sessionRows) {
        final sid = row['id'] as String;
        final msgRows = await _db!.query(
          'chat_messages',
          where: 'session_id = ?',
          whereArgs: [sid],
          orderBy: 'created_at ASC',
        );
        final messages = msgRows.map((r) {
          final m = Map<String, dynamic>.from(r);
          m['id'] = m['id']?.toString() ?? '';
          return ChatMessage.fromMap(m);
        }).toList();
        result.add(ChatSession.fromMap(row, messages));
      }
      return result;
    } catch (e) {
      debugPrint('[HistoryService] loadChatSessionsPaged error: $e');
      return [];
    }
  }

  Future<int> countChatSessions() async {
    await _ensureDb();
    try {
      final result = await _db!.rawQuery(
        'SELECT COUNT(*) as cnt FROM chat_sessions',
      );
      return result.first['cnt'] as int? ?? 0;
    } catch (e) {
      debugPrint('[HistoryService] countChatSessions error: $e');
      return 0;
    }
  }

  // ── D-005: Delete all ─────────────────────────────────────────────────────

  Future<void> deleteAllSessions() async {
    await _ensureDb();
    try {
      await _db!.transaction((txn) async {
        await txn.delete('chat_messages');
        await txn.delete('chat_sessions');
      });
    } catch (e) {
      debugPrint('[HistoryService] deleteAllSessions error: $e');
    }
  }

  // ── E-009: Search ─────────────────────────────────────────────────────────

  Future<List<ChatSession>> searchChatSessions(
    String query, {
    int limit = kPageSize,
  }) async {
    if (query.trim().isEmpty) {
      return loadChatSessionsPaged(offset: 0, limit: limit);
    }
    await _ensureDb();
    try {
      final q = '%${query.trim()}%';
      final sessionRows = await _db!.query(
        'chat_sessions',
        where: 'title LIKE ?',
        whereArgs: [q],
        orderBy: 'updated_at DESC',
        limit: limit,
      );
      final List<ChatSession> result = [];
      for (final row in sessionRows) {
        final sid = row['id'] as String;
        final msgRows = await _db!.query(
          'chat_messages',
          where: 'session_id = ?',
          whereArgs: [sid],
          orderBy: 'created_at ASC',
        );
        final messages = msgRows.map((r) {
          final m = Map<String, dynamic>.from(r);
          m['id'] = m['id']?.toString() ?? '';
          return ChatMessage.fromMap(m);
        }).toList();
        result.add(ChatSession.fromMap(row, messages));
      }
      return result;
    } catch (e) {
      debugPrint('[HistoryService] searchChatSessions error: $e');
      return [];
    }
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
