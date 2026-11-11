import 'package:sqflite/sqflite.dart';

import '../../../db/database_helper.dart';
import '../../../utils/money.dart';

/// Repository for finance: expenses, payments, ledger.
///
/// Manages persistence of expense records, expense payments, and financial
/// events. Operations that touch multiple tables (e.g. recording an expense
/// and appending its financial event together) use transaction-aware variants
/// so the operation is atomic.
class FinanceRepository {
  FinanceRepository._();
  static final FinanceRepository instance = FinanceRepository._();

  /// Creates (or verifies) the finance tables: `expense_categories`, `expenses`,
  /// `till_movements` and `expense_payments`.
  ///
  /// Mirrors `_createExpenseTables`/`_createExpensePaymentsTable` so fresh
  /// installs and upgraded tills match. Default expense categories are seeded
  /// on first creation.
  static Future<void> createTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS expense_categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        active INTEGER NOT NULL DEFAULT 1,
        system INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        shift_id INTEGER,
        category_id INTEGER NOT NULL,
        amount_minor INTEGER NOT NULL,
        paid_from TEXT NOT NULL DEFAULT 'till_cash',
        note TEXT,
        photo_path TEXT,
        staff_id INTEGER,
        approved_by INTEGER,
        staff_name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'posted',
        synced_to_backend INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_expenses_shift ON expenses (shift_id, created_at)');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS till_movements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        shift_id INTEGER NOT NULL,
        movement_type TEXT NOT NULL,
        amount_minor INTEGER NOT NULL,
        note TEXT,
        staff_id INTEGER,
        staff_name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'posted',
        synced_to_backend INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_till_movements_shift ON till_movements (shift_id, created_at)');
    await db.execute('''CREATE TABLE IF NOT EXISTS expense_payments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      expense_id INTEGER NOT NULL,
      amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
      payment_method TEXT NOT NULL,
      reference TEXT,
      shift_id INTEGER,
      created_at TEXT NOT NULL,
      FOREIGN KEY (expense_id) REFERENCES expenses (id)
    )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_expense_payments_expense '
        'ON expense_payments (expense_id, created_at)');

    final existing = await db.query('expense_categories', limit: 1);
    if (existing.isEmpty) {
      const categories = <String>[
        'Rent',
        'Electricity and water',
        'Transport',
        'Wages',
        'Supplies',
        'Airtime and data',
        'Licences and fees',
        'Bad debts',
        'Other',
      ];
      for (final name in categories) {
        await db.insert(
          'expense_categories',
          {'name': name, 'active': 1, 'system': 1},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }

    await db.execute('''CREATE TABLE IF NOT EXISTS financial_events (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      event_type TEXT NOT NULL,
      source_type TEXT NOT NULL,
      source_id INTEGER,
      occurred_at_utc TEXT NOT NULL,
      revenue_minor INTEGER NOT NULL DEFAULT 0,
      cash_in_minor INTEGER NOT NULL DEFAULT 0,
      cash_out_minor INTEGER NOT NULL DEFAULT 0,
      cogs_minor INTEGER NOT NULL DEFAULT 0,
      operating_expense_minor INTEGER NOT NULL DEFAULT 0,
      tax_collected_minor INTEGER NOT NULL DEFAULT 0,
      receivable_delta_minor INTEGER NOT NULL DEFAULT 0,
      payable_delta_minor INTEGER NOT NULL DEFAULT 0,
      customer_deposit_delta_minor INTEGER NOT NULL DEFAULT 0,
      inventory_delta_milliunits INTEGER NOT NULL DEFAULT 0,
      metadata_json TEXT NOT NULL DEFAULT '{}',
      previous_hash TEXT,
      integrity_hash TEXT NOT NULL,
      synced_to_backend INTEGER NOT NULL DEFAULT 0
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_financial_events_occurred '
        'ON financial_events (occurred_at_utc, id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_financial_events_source '
        'ON financial_events (source_type, source_id)');

    await db.execute('''CREATE TABLE IF NOT EXISTS owner_transactions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      transaction_type TEXT NOT NULL,
      amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
      shift_id INTEGER,
      staff_id INTEGER,
      staff_name TEXT NOT NULL,
      note TEXT,
      created_at TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'posted',
      synced_to_backend INTEGER NOT NULL DEFAULT 0
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_owner_transactions_date '
        'ON owner_transactions (created_at, id)');

    await db.execute('''CREATE TABLE IF NOT EXISTS cost_pools (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      name TEXT NOT NULL,
      pool_type TEXT NOT NULL CHECK (pool_type IN ('lot', 'rolling_stock')),
      invested_minor INTEGER NOT NULL DEFAULT 0,
      recovered_minor INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'open',
      note TEXT,
      created_at TEXT NOT NULL,
      closed_at TEXT
    )''');

    await db.execute('''CREATE TABLE IF NOT EXISTS cost_pool_entries (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      pool_id INTEGER NOT NULL,
      entry_type TEXT NOT NULL,
      amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
      paid_from TEXT NOT NULL DEFAULT 'other',
      description TEXT,
      created_at TEXT NOT NULL,
      FOREIGN KEY (pool_id) REFERENCES cost_pools (id)
    )''');

    await db.execute('''CREATE TABLE IF NOT EXISTS sale_pool_allocations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      pool_id INTEGER NOT NULL,
      sale_id INTEGER NOT NULL,
      amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
      created_at TEXT NOT NULL,
      UNIQUE (pool_id, sale_id),
      FOREIGN KEY (pool_id) REFERENCES cost_pools (id)
    )''');

    await db.execute('''CREATE TABLE IF NOT EXISTS drawer_events (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      shift_id INTEGER,
      event_type TEXT NOT NULL,
      reason TEXT,
      staff_id INTEGER,
      staff_name TEXT NOT NULL,
      sale_id INTEGER,
      approved_by TEXT,
      created_at TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'recorded',
      success INTEGER NOT NULL DEFAULT 0,
      synced_to_backend INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (shift_id) REFERENCES shifts (id) ON DELETE SET NULL
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_drawer_events_created '
        'ON drawer_events (created_at DESC)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_drawer_events_shift '
        'ON drawer_events (shift_id, created_at DESC)');

    await db.execute('''CREATE TABLE IF NOT EXISTS backup_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      kind TEXT NOT NULL,
      path TEXT,
      created_at TEXT NOT NULL,
      clear_bytes INTEGER NOT NULL DEFAULT 0,
      manifest_json TEXT,
      status TEXT NOT NULL DEFAULT 'written'
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_backup_log_created '
        'ON backup_log (created_at DESC)');

    await db.execute('''CREATE TABLE IF NOT EXISTS incoming_payments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      remote_id TEXT NOT NULL UNIQUE,
      trans_id TEXT NOT NULL,
      amount_minor INTEGER NOT NULL,
      payer_masked TEXT NOT NULL DEFAULT '',
      received_at TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'unclaimed',
      claimed_at TEXT,
      claimed_by TEXT,
      updated_at TEXT NOT NULL
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_incoming_payments_status '
        'ON incoming_payments (status, received_at DESC)');

    await db.execute('''CREATE TABLE IF NOT EXISTS incoming_payment_claims (
      remote_id TEXT PRIMARY KEY,
      sale_id INTEGER NOT NULL,
      sale_uuid TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending',
      reason TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_incoming_payment_claims_status '
        'ON incoming_payment_claims (status, updated_at)');

    await db.execute('''CREATE TABLE IF NOT EXISTS discount_reasons (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_discount_reasons_name ON discount_reasons (name)');

    await db.execute('''CREATE TABLE IF NOT EXISTS label_print_jobs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      product_id INTEGER NOT NULL,
      product_name TEXT NOT NULL,
      barcode TEXT NOT NULL,
      price_minor INTEGER NOT NULL,
      quantity INTEGER NOT NULL,
      printed_quantity INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'pending',
      paper_width INTEGER NOT NULL,
      error TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_label_print_jobs_status ON label_print_jobs (status, updated_at DESC)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchase_orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        order_number TEXT NOT NULL UNIQUE,
        supplier_id INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'draft',
        ordered_at TEXT,
        expected_at TEXT,
        note TEXT,
        created_at TEXT NOT NULL,
        staff_id INTEGER,
        staff_name TEXT NOT NULL,
        synced_to_backend INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchase_order_lines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        purchase_order_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        product_name TEXT NOT NULL,
        qty REAL NOT NULL,
        unit_cost_minor INTEGER NOT NULL DEFAULT 0,
        received_qty REAL NOT NULL DEFAULT 0,
        FOREIGN KEY (purchase_order_id) REFERENCES purchase_orders (id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE
      )
    ''');

    const discountReasons = <String>[
      'Staff discount',
      'Loyalty',
      'Damaged packaging',
      'Promotion',
      'Other',
    ];
    for (final name in discountReasons) {
      await db.insert(
        'discount_reasons',
        {'name': name},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  // ── Public methods ─────────────────────────────────────────────────

  Future<int> recordExpense({
    required String uuid,
    required int categoryId,
    required Money amount,
    required String paidFrom,
    required String staffName,
    int? staffId,
    String? note,
    String? photoPath,
    int? approvedBy,
  }) async {
    return DatabaseHelper.instance.recordExpense(
      uuid: uuid,
      categoryId: categoryId,
      amount: amount,
      paidFrom: paidFrom,
      staffName: staffName,
      staffId: staffId,
      note: note,
      photoPath: photoPath,
      approvedBy: approvedBy,
    );
  }

  Future<int> recordExpensePayment({
    required String uuid,
    required int expenseId,
    required Money amount,
    required String paymentMethod,
    String? reference,
    int? shiftId,
  }) async {
    return DatabaseHelper.instance.recordExpensePayment(
      uuid: uuid,
      expenseId: expenseId,
      amount: amount,
      paymentMethod: paymentMethod,
      reference: reference,
      shiftId: shiftId,
    );
  }

  Future<void> voidExpense(int expenseId) async {
    return DatabaseHelper.instance.voidExpense(expenseId);
  }

  Future<List<Map<String, dynamic>>> getExpenses({int? shiftId}) async {
    final db = await DatabaseHelper.instance.database;
    if (shiftId != null) {
      return db.query('expenses',
          where: 'shift_id = ?', whereArgs: [shiftId],
          orderBy: 'created_at DESC');
    }
    return db.query('expenses', orderBy: 'created_at DESC');
  }
}
