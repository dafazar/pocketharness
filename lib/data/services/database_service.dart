// lib/data/services/database_service.dart
// Pocket Harness — Database Service (AI App Edition)
// Hanya menyimpan data user: AI history, notes, riwayat
// =============================================================================

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:pocketharness/core/security/secure_db_key_service.dart';

class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  Database? _userDb;

  Future<void> init() async {
    await _ensureUserDb();
  }

  Future<void> _ensureUserDb() async {
    if (_userDb != null) return;
    final dir    = await getApplicationDocumentsDirectory();
    final dbPath = join(dir.path, 'kanmongo_user.db');
    final keyService = SecureDbKeyService.instance;
    final password   = keyService.hasKeys ? keyService.userKey : null;

    _userDb = await openDatabase(
      dbPath,
      password: password,
      version: 1,
      onCreate: _createDb,
    );
  }

  Future<void> _createDb(Database db, int version) async {
    // AI chat history
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_history (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id  TEXT NOT NULL,
        role        TEXT NOT NULL,
        content     TEXT NOT NULL,
        created_at  INTEGER NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_ai_session ON ai_history(session_id)');
  }

  // ── AI Chat History ───────────────────────────────────────────────────────
  Future<void> saveAiMessage({
    required String sessionId,
    required String role,
    required String content,
  }) async {
    await _ensureUserDb();
    await _userDb!.insert('ai_history', {
      'session_id': sessionId,
      'role':       role,
      'content':    content,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<Map<String, dynamic>>> getAiHistory(String sessionId) async {
    await _ensureUserDb();
    return _userDb!.query(
      'ai_history',
      where:   'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'created_at ASC',
    );
  }

  Future<void> clearAiHistory(String sessionId) async {
    await _ensureUserDb();
    await _userDb!.delete(
      'ai_history',
      where: 'session_id = ?', whereArgs: [sessionId],
    );
  }

  Future<void> closeAll() async {
    await _userDb?.close();
    _userDb = null;
  }
}
