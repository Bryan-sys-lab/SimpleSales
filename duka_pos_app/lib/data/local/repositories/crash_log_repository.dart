import 'package:sqflite/sqflite.dart';

/// Repository for crash log entries.
class CrashLogRepository {
  CrashLogRepository._();
  static final CrashLogRepository instance = CrashLogRepository._();

  static Future<void> createTable(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS crash_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kind TEXT NOT NULL DEFAULT 'error',
        message TEXT NOT NULL,
        stack TEXT,
        route TEXT,
        actor_name TEXT,
        action TEXT,
        breadcrumbs TEXT,
        created_at TEXT NOT NULL
      )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_crash_created ON crash_log (created_at DESC)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_crash_actor ON crash_log (actor_name, created_at DESC)');
  }
}
