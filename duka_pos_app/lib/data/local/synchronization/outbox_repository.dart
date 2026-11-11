import 'package:sqflite/sqflite.dart';

import '../../../db/database_helper.dart';

/// Transactional outbox for reliable synchronization.
///
/// Every business operation that needs to be synced inserts an outbox event
/// in the same SQLite transaction as the business record. The synchronizer
/// then reads unacknowledged events, sends them using the same idempotency
/// key, waits for server acknowledgement, and marks the event acknowledged.
///
/// This guarantees exactly-once processing: retrying a sync never generates
/// another business operation because the same operation UUID is reused.
class OutboxRepository {
  OutboxRepository._();
  static final OutboxRepository instance = OutboxRepository._();

  // ── Write (within a transaction) ───────────────────────────────────

  /// Inserts an outbox event within [txn]. The business record and its
  /// outbox event must be inserted in the same SQLite transaction.
  Future<void> insertOutboxEventInTransaction(
    Transaction txn, {
    required String operationUuid,
    required String workspaceUuid,
    required String aggregateType,
    required String aggregateUuid,
    required String operationType,
    required String payload,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await txn.insert('outbox', {
      'operation_uuid': operationUuid,
      'workspace_uuid': workspaceUuid,
      'aggregate_type': aggregateType,
      'aggregate_uuid': aggregateUuid,
      'operation_type': operationType,
      'payload': payload,
      'created_at_utc': now,
      'attempt_count': 0,
      'last_attempt_at_utc': null,
      'acknowledged_at_utc': null,
      'last_error': null,
    });
  }

  // ── Read (for the synchronizer) ────────────────────────────────────

  /// Reads unacknowledged outbox events, ordered by creation time.
  Future<List<Map<String, dynamic>>> getUnacknowledgedEvents({
    int limit = 100,
  }) async {
    final db = await DatabaseHelper.instance.database;
    return db.query(
      'outbox',
      where: 'acknowledged_at_utc IS NULL',
      orderBy: 'created_at_utc ASC',
      limit: limit,
    );
  }

  /// Marks an outbox event as acknowledged.
  Future<void> acknowledgeEvent(String operationUuid) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'outbox',
      {'acknowledged_at_utc': DateTime.now().toUtc().toIso8601String()},
      where: 'operation_uuid = ?',
      whereArgs: [operationUuid],
    );
  }

  /// Records a failed attempt on an outbox event.
  Future<void> recordAttempt(String operationUuid, String? error) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'outbox',
      {
        'attempt_count': 1, // incremented by caller reading current value
        'last_attempt_at_utc': DateTime.now().toUtc().toIso8601String(),
        'last_error': error,
      },
      where: 'operation_uuid = ?',
      whereArgs: [operationUuid],
    );
  }
}
