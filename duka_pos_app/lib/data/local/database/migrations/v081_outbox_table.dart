import 'package:sqflite/sqflite.dart';

import 'migration.dart';

/// v81: creates the transactional outbox table for reliable synchronization.
///
/// Every business operation that needs to be synced inserts an outbox event
/// in the same SQLite transaction as the business record. This guarantees
/// exactly-once processing: retrying a sync never generates another business
/// operation because the same operation UUID is reused.
class Migration081 extends Migration {
  Migration081._();

  static final Migration081 _instance = Migration081._();

  factory Migration081() => _instance;

  @override
  int get toVersion => 81;

  @override
  Future<void> migrate(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS outbox (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        operation_uuid TEXT NOT NULL UNIQUE,
        workspace_uuid TEXT NOT NULL,
        aggregate_type TEXT NOT NULL,
        aggregate_uuid TEXT NOT NULL,
        operation_type TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at_utc TEXT NOT NULL,
        attempt_count INTEGER NOT NULL DEFAULT 0,
        last_attempt_at_utc TEXT,
        acknowledged_at_utc TEXT,
        last_error TEXT
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_outbox_unack ON outbox (acknowledged_at_utc, created_at_utc)');
  }
}
