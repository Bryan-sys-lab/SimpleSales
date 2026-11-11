import 'package:sqflite/sqflite.dart';

import '../../../db/database_helper.dart';
import '../../../utils/money.dart';

/// Repository for Open-profile jobs and cost pools.
///
/// Delegates to [DatabaseHelper] for now. Job completion and cost-pool
/// allocation are transactional and exposed via transaction-aware variants so
/// they can be composed inside a single business-operation transaction.
class JobRepository {
  JobRepository._();
  static final JobRepository instance = JobRepository._();

  /// Creates (or verifies) the `jobs` and `job_payments` tables.
  ///
  /// Mirrors `_createOpenFinanceTables` so fresh installs and upgraded tills
  /// match. Note the column names match `_onCreate` exactly: `customer_name`
  /// (not `customer_id`), `title` (not `description`), plus `quote_minor` and
  /// `due_at`.
  static Future<void> createTable(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS jobs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      customer_name TEXT,
      title TEXT NOT NULL,
      quote_minor INTEGER,
      final_price_minor INTEGER,
      due_at TEXT,
      status TEXT NOT NULL DEFAULT 'open',
      cost_pool_id INTEGER,
      created_at TEXT NOT NULL,
      closed_at TEXT
    )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_jobs_status ON jobs (status)');

    await db.execute('''CREATE TABLE IF NOT EXISTS job_payments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      job_id INTEGER NOT NULL,
      amount_minor INTEGER NOT NULL,
      method TEXT NOT NULL,
      reference TEXT,
      status TEXT NOT NULL DEFAULT 'pending',
      created_at TEXT NOT NULL,
      staff_id INTEGER,
      staff_name TEXT NOT NULL,
      FOREIGN KEY (job_id) REFERENCES jobs (id)
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_job_payments_job ON job_payments (job_id)');

    await db.execute('''CREATE TABLE IF NOT EXISTS job_costs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      job_id INTEGER NOT NULL,
      cost_type TEXT NOT NULL,
      amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
      paid_from TEXT NOT NULL DEFAULT 'other',
      description TEXT,
      created_at TEXT NOT NULL,
      FOREIGN KEY (job_id) REFERENCES jobs (id)
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_job_costs_job ON job_costs (job_id)');

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
        'CREATE INDEX IF NOT EXISTS idx_shift_reports_created '
        'ON shift_reports (created_at DESC)');

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
        'CREATE INDEX IF NOT EXISTS idx_remote_operational_kind '
        'ON remote_operational_records (kind, updated_at DESC)');
  }

  // ── Transaction-aware variants ─────────────────────────────────────

  Future<int> recordJobSaleInTransaction(Transaction txn, {
    required int jobId,
    required Money amount,
    required String paymentMethod,
    String? paymentReference,
    String? staffName,
    int? staffId,
  }) async {
    return DatabaseHelper.instance.recordJobSale(
      jobId: jobId,
      amount: amount,
      paymentMethod: paymentMethod,
      paymentReference: paymentReference,
      staffName: staffName,
      staffId: staffId,
    );
  }

  // ── Public methods ─────────────────────────────────────────────────

  Future<int> recordJobSale({
    required int jobId,
    required Money amount,
    required String paymentMethod,
    String? paymentReference,
    String? staffName,
    int? staffId,
  }) async {
    return DatabaseHelper.instance.recordJobSale(
      jobId: jobId,
      amount: amount,
      paymentMethod: paymentMethod,
      paymentReference: paymentReference,
      staffName: staffName,
      staffId: staffId,
    );
  }

  Future<void> completeJob({
    required int jobId,
    required Money finalPrice,
  }) async {
    return DatabaseHelper.instance.completeJob(
      jobId: jobId,
      finalPrice: finalPrice,
    );
  }

  Future<Map<String, dynamic>?> getJob(int id) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'jobs',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }
}
