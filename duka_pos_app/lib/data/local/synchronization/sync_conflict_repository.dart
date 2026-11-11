import 'package:sqflite/sqflite.dart';

import '../../../db/database_helper.dart';

/// Manages sync conflicts detected during synchronization.
///
/// A conflict occurs when the same aggregate was modified on two devices.
/// Conflicts are written to `sync_conflicts` and remain visible until the
/// owner resolves them.
class SyncConflictRepository {
  SyncConflictRepository._();
  static final SyncConflictRepository instance = SyncConflictRepository._();

  static Future<void> createTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_conflicts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        kind TEXT NOT NULL,
        local_id INTEGER,
        device_id TEXT,
        reason TEXT NOT NULL,
        payload_json TEXT,
        created_at TEXT NOT NULL,
        resolved_at TEXT,
        resolution TEXT
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sync_conflicts_open '
        'ON sync_conflicts (resolved_at, created_at DESC)');
  }

  /// Records a conflict within [txn].
  Future<void> recordConflictInTransaction(
    Transaction txn, {
    required String uuid,
    required String kind,
    int? localId,
    String? deviceId,
    required String reason,
    String? payloadJson,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await txn.insert('sync_conflicts', {
      'uuid': uuid,
      'kind': kind,
      'local_id': localId,
      'device_id': deviceId,
      'reason': reason,
      'payload_json': payloadJson,
      'created_at': now,
      'resolved_at': null,
      'resolution': null,
    });
  }

  /// Reads unresolved conflicts.
  Future<List<Map<String, dynamic>>> getUnresolvedConflicts() async {
    final db = await DatabaseHelper.instance.database;
    return db.query(
      'sync_conflicts',
      where: 'resolved_at IS NULL',
      orderBy: 'created_at DESC',
    );
  }

  /// Marks a conflict as resolved.
  Future<void> resolveConflict(String uuid, String resolution) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'sync_conflicts',
      {
        'resolved_at': DateTime.now().toUtc().toIso8601String(),
        'resolution': resolution,
      },
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }
}
