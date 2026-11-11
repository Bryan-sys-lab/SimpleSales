import 'package:sqflite/sqflite.dart';

/// Repository for audit log entries.
class AuditLogRepository {
  AuditLogRepository._();
  static final AuditLogRepository instance = AuditLogRepository._();

  static Future<void> createTable(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS audit_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        action TEXT NOT NULL,
        entity TEXT NOT NULL,
        entity_id TEXT,
        actor_id INTEGER,
        actor_name TEXT NOT NULL,
        detail TEXT,
        created_at TEXT NOT NULL
      )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_audit_action ON audit_log (action, created_at DESC)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_audit_entity ON audit_log (entity, entity_id, created_at DESC)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_audit_actor ON audit_log (actor_id, created_at DESC)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_audit_created ON audit_log (created_at DESC)');
  }
}
