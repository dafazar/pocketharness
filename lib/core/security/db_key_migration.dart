// lib/core/security/db_key_migration.dart
// Pocket Harness — migrasi satu kali database lokal dari kunci lama
// (SHA256(salt + ":" + uid + ":user"), salt dari Firestore _server_config/db_keys)
// ke kunci acak perangkat (SecureDbKeyService).
//
// Setelah migrasi berhasil, klien tidak lagi membutuhkan salt.
// =============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

class DbKeyMigration {
  DbKeyMigration._();

  /// true jika semua database lama sudah berada di [newKey], atau memang tidak ada.
  static Future<bool> run({required String uid, required String newKey}) async {
    final paths = await _dbPaths();

    // Pulihkan cadangan yang tertinggal jika proses sebelumnya terhenti di tengah tukar file.
    for (final path in paths) {
      final bak = '$path.legacy-bak';
      if (await File(bak).exists() && !await File(path).exists()) {
        await File(bak).rename(path);
      }
    }

    final present = <String>[];
    for (final path in paths) {
      if (await File(path).exists()) present.add(path);
    }
    if (present.isEmpty) return true;

    String? legacyKey;
    var allOk = true;
    for (final path in present) {
      if (await _isReadable(path, newKey)) continue;

      legacyKey ??= await _legacyKeyFor(uid);
      if (legacyKey != null && await _isReadable(path, legacyKey)) {
        final ok = await _rewrite(path, sourcePassword: legacyKey, newKey: newKey);
        allOk = allOk && ok;
        continue;
      }

      if (await _isReadable(path, null)) {
        // Database lama yang belum terenkripsi.
        final ok = await _rewrite(path, sourcePassword: null, newKey: newKey);
        allOk = allOk && ok;
        continue;
      }

      debugPrint('[DbKeyMigration] Tidak bisa membaca $path dengan kunci mana pun.');
      allOk = false;
    }
    return allOk;
  }

  static Future<List<String>> _dbPaths() async {
    final docs = await getApplicationDocumentsDirectory();
    final dbDir = await getDatabasesPath();
    return [
      p.join(docs.path, 'kanmongo_user.db'),
      p.join(docs.path, 'km_history.db'),
      p.join(dbDir, 'notes.db'),
    ];
  }

  static Future<String?> _legacyKeyFor(String uid) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('_server_config')
          .doc('db_keys')
          .get();
      final salt = snap.data()?['salt'] as String?;
      if (salt == null || salt.length < 32) return null;
      return sha256.convert(utf8.encode('$salt:$uid:user')).toString();
    } catch (e) {
      debugPrint('[DbKeyMigration] Salt lama tidak terbaca: $e');
      return null;
    }
  }

  static Future<bool> _isReadable(String path, String? password) async {
    Database? db;
    try {
      db = await openDatabase(path, password: password);
      await db.rawQuery('SELECT count(*) FROM sqlite_master');
      return true;
    } catch (_) {
      return false;
    } finally {
      await db?.close();
    }
  }

  static Future<bool> _rewrite(
    String path, {
    required String? sourcePassword,
    required String newKey,
  }) async {
    final tmp = '$path.migrating';
    final bak = '$path.legacy-bak';
    Database? src;
    Database? dst;
    try {
      if (await File(tmp).exists()) await File(tmp).delete();

      src = await openDatabase(path, password: sourcePassword);
      final versionRow = await src.rawQuery('PRAGMA user_version');
      final userVersion = versionRow.first.values.first as int;

      final objects = await src.rawQuery(
        "SELECT type, name, sql FROM sqlite_master "
        "WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' "
        "ORDER BY CASE type WHEN 'table' THEN 0 WHEN 'index' THEN 1 ELSE 2 END",
      );

      dst = await openDatabase(tmp, password: newKey);
      for (final obj in objects) {
        await dst.execute(obj['sql'] as String);
      }
      for (final obj in objects.where((o) => o['type'] == 'table')) {
        final table = obj['name'] as String;
        final rows = await src.query(table);
        if (rows.isEmpty) continue;
        final batch = dst.batch();
        for (final row in rows) {
          batch.insert(table, row);
        }
        await batch.commit(noResult: true);
      }
      await dst.execute('PRAGMA user_version = $userVersion');
      await dst.close();
      dst = null;
      await src.close();
      src = null;

      // Tukar file: yang lama jadi cadangan, yang baru dipasang.
      await File(path).rename(bak);
      await File(tmp).rename(path);

      if (!await _isReadable(path, newKey)) {
        await File(path).delete();
        await File(bak).rename(path);
        return false;
      }
      await File(bak).delete();
      return true;
    } catch (e) {
      debugPrint('[DbKeyMigration] Gagal migrasi $path: $e');
      try { await src?.close(); } catch (_) {}
      try { await dst?.close(); } catch (_) {}
      if (await File(tmp).exists()) await File(tmp).delete();
      if (await File(bak).exists() && !await File(path).exists()) {
        await File(bak).rename(path);
      }
      return false;
    }
  }
}
