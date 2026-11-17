import 'package:sqflite/sqflite.dart';

/// Schema for shared till operations.
///
/// Shift and reconciliation data is used by all profiles and must not be
/// kept independent from profile-specific commerce features.
class OperationsRepository {
  OperationsRepository._();
  static final OperationsRepository instance = OperationsRepository._();

  static Future<void> createTable(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS shifts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      staff_id INTEGER NOT NULL,
      staff_name TEXT NOT NULL,
      start_time TEXT NOT NULL,
      end_time TEXT,
      start_float INTEGER NOT NULL,
      end_float INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'open',
      synced_to_backend INTEGER NOT NULL DEFAULT 0
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_shifts_staff ON shifts (staff_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_shifts_status_time ON shifts (status, start_time)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_shifts_start_staff ON shifts (start_time, staff_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_shifts_end_staff ON shifts (end_time, staff_id)');

    await db.execute('''CREATE TABLE IF NOT EXISTS till_counts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      shift_id INTEGER NOT NULL,
      denomination TEXT NOT NULL,
      count INTEGER NOT NULL DEFAULT 0,
      value INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      FOREIGN KEY (shift_id) REFERENCES shifts (id) ON DELETE CASCADE
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_till_counts_shift ON till_counts (shift_id)');

    await db.execute('''CREATE TABLE IF NOT EXISTS reconciliations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      shift_id INTEGER NOT NULL,
      counted_cash INTEGER NOT NULL DEFAULT 0,
      expected_cash INTEGER NOT NULL DEFAULT 0,
      variance INTEGER NOT NULL DEFAULT 0,
      recorded_at TEXT NOT NULL,
      FOREIGN KEY (shift_id) REFERENCES shifts (id) ON DELETE CASCADE
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_reconciliations_shift_id ON reconciliations (shift_id, id DESC)');

    await db.execute('''CREATE TABLE IF NOT EXISTS shift_reports (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      report_number INTEGER NOT NULL UNIQUE,
      shift_id INTEGER NOT NULL UNIQUE,
      report_type TEXT NOT NULL DEFAULT 'z',
      snapshot_json TEXT NOT NULL,
      created_at TEXT NOT NULL,
      staff_id INTEGER,
      staff_name TEXT NOT NULL
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_shift_reports_created ON shift_reports (created_at DESC)');

    await db.execute('''CREATE TABLE IF NOT EXISTS remote_operational_records (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      remote_id TEXT NOT NULL UNIQUE,
      kind TEXT NOT NULL,
      device_id TEXT,
      local_id INTEGER,
      payload_json TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_remote_operational_kind ON remote_operational_records (kind, updated_at DESC)');
  }
}
