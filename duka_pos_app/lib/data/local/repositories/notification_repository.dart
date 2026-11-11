import 'package:sqflite/sqflite.dart';

/// Repository for notification preferences and log entries.
class NotificationRepository {
  NotificationRepository._();
  static final NotificationRepository instance = NotificationRepository._();

  static Future<void> createTable(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS notification_prefs (
      staff_id INTEGER NOT NULL,
      type TEXT NOT NULL,
      enabled INTEGER NOT NULL DEFAULT 1,
      quiet_start INTEGER,
      quiet_end INTEGER,
      PRIMARY KEY (staff_id, type)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS notification_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      staff_id INTEGER NOT NULL,
      type TEXT NOT NULL,
      dedupe_key TEXT NOT NULL,
      count INTEGER NOT NULL,
      fired_at TEXT NOT NULL,
      opened_at TEXT
    )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_notification_log_lookup '
        'ON notification_log (staff_id, type, dedupe_key, fired_at DESC)');
  }
}
