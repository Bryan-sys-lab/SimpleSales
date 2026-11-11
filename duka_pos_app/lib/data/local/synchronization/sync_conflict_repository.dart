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
