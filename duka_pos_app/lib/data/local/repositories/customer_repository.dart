import 'package:sqflite/sqflite.dart';

import '../../../db/database_helper.dart';
import '../../../models/credit.dart';

/// Repository for customers and credit ledger.
///
/// Delegates to [DatabaseHelper] for now. Transaction-aware variants accept an
/// open [Transaction] so a credit sale and its ledger entry commit together.
class CustomerRepository {
  CustomerRepository._();
  static final CustomerRepository instance = CustomerRepository._();

  /// Creates (or verifies) the `customers` and `credit_ledger` tables.
  ///
  /// Mirrors `_createCreditTables` so fresh installs and upgraded tills match.
  static Future<void> createTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        phone TEXT,
        tin TEXT,
        notes TEXT,
        credit_limit_minor INTEGER,
        balance_minor INTEGER NOT NULL DEFAULT 0,
        active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_customers_name ON customers (name)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_customers_phone ON customers (phone)');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS credit_ledger (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        customer_id INTEGER NOT NULL,
        entry_type TEXT NOT NULL,
        amount_minor INTEGER NOT NULL,
        sale_id INTEGER,
        return_id INTEGER,
        payment_method TEXT,
        reference TEXT,
        shift_id INTEGER,
        staff_id INTEGER,
        staff_name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (customer_id) REFERENCES customers (id)
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_credit_ledger_customer ON credit_ledger (customer_id, created_at)');

    await db.execute('''CREATE TABLE IF NOT EXISTS sale_returns (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sale_id INTEGER NOT NULL,
      kind TEXT NOT NULL DEFAULT 'refund',
      reason TEXT NOT NULL,
      total INTEGER NOT NULL DEFAULT 0,
      vat_total INTEGER NOT NULL DEFAULT 0,
      profit INTEGER NOT NULL DEFAULT 0,
      refund_method TEXT NOT NULL DEFAULT 'cash',
      payment_reference TEXT,
      shift_id INTEGER,
      staff_id INTEGER,
      staff_name TEXT NOT NULL,
      created_at TEXT NOT NULL,
      synced_to_backend INTEGER NOT NULL DEFAULT 0
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sale_returns_sale ON sale_returns (sale_id)');

    await db.execute('''CREATE TABLE IF NOT EXISTS sale_return_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      return_id INTEGER NOT NULL,
      sale_item_id INTEGER NOT NULL,
      product_id INTEGER NOT NULL,
      product_name TEXT NOT NULL,
      qty REAL NOT NULL,
      unit_price INTEGER NOT NULL,
      unit_cost INTEGER NOT NULL,
      refund_minor INTEGER NOT NULL DEFAULT 0,
      vat_minor INTEGER NOT NULL DEFAULT 0,
      portion TEXT NOT NULL DEFAULT 'full',
      portion_ml INTEGER NOT NULL DEFAULT 0,
      restock INTEGER NOT NULL DEFAULT 1,
      restock_reason TEXT,
      FOREIGN KEY (return_id) REFERENCES sale_returns (id) ON DELETE CASCADE
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sale_return_items_return ON sale_return_items (return_id)');

    await db.execute('''CREATE TABLE IF NOT EXISTS sale_return_refunds (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      return_id INTEGER NOT NULL,
      sale_payment_id INTEGER,
      method TEXT NOT NULL,
      amount_minor INTEGER NOT NULL,
      reference TEXT,
      FOREIGN KEY (return_id) REFERENCES sale_returns (id) ON DELETE CASCADE,
      FOREIGN KEY (sale_payment_id) REFERENCES sale_payments (id) ON DELETE SET NULL
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sale_return_refunds_return ON sale_return_refunds (return_id)');

    await db.execute('''CREATE TABLE IF NOT EXISTS receive_drafts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      staff_id INTEGER UNIQUE,
      payload TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )''');

    await db.execute('''CREATE TABLE IF NOT EXISTS laybys (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      customer_id INTEGER NOT NULL,
      status TEXT NOT NULL DEFAULT 'open',
      total_minor INTEGER NOT NULL,
      paid_minor INTEGER NOT NULL DEFAULT 0,
      due_at TEXT NOT NULL,
      created_at TEXT NOT NULL,
      staff_id INTEGER,
      staff_name TEXT NOT NULL,
      sale_id INTEGER,
      completed_at TEXT,
      cancelled_at TEXT,
      synced_to_backend INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (customer_id) REFERENCES customers (id),
      FOREIGN KEY (sale_id) REFERENCES sales (id)
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_laybys_status_due ON laybys (status, due_at)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_laybys_customer ON laybys (customer_id, created_at)');

    await db.execute('''CREATE TABLE IF NOT EXISTS layby_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      layby_id INTEGER NOT NULL,
      product_id INTEGER NOT NULL,
      variant_id INTEGER,
      product_name TEXT NOT NULL,
      variant_name TEXT NOT NULL DEFAULT '',
      qty REAL NOT NULL,
      unit_price_minor INTEGER NOT NULL,
      unit_cost_minor INTEGER NOT NULL,
      discount_minor INTEGER NOT NULL DEFAULT 0,
      total_minor INTEGER NOT NULL,
      FOREIGN KEY (layby_id) REFERENCES laybys (id) ON DELETE CASCADE
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_layby_items_layby ON layby_items (layby_id)');

    await db.execute('''CREATE TABLE IF NOT EXISTS layby_payments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      layby_id INTEGER NOT NULL,
      method TEXT NOT NULL,
      amount_minor INTEGER NOT NULL,
      direction TEXT NOT NULL DEFAULT 'in',
      reference TEXT,
      created_at TEXT NOT NULL,
      staff_id INTEGER,
      staff_name TEXT NOT NULL,
      FOREIGN KEY (layby_id) REFERENCES laybys (id) ON DELETE CASCADE
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_layby_payments_layby ON layby_payments (layby_id, created_at)');

    await db.execute('''CREATE TABLE IF NOT EXISTS exchanges (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      original_sale_id INTEGER NOT NULL,
      return_id INTEGER,
      replacement_sale_id INTEGER,
      status TEXT NOT NULL DEFAULT 'completed',
      returned_total_minor INTEGER NOT NULL,
      replacement_total_minor INTEGER NOT NULL,
      difference_minor INTEGER NOT NULL DEFAULT 0,
      difference_direction TEXT NOT NULL DEFAULT 'even',
      reason TEXT NOT NULL,
      staff_id INTEGER,
      staff_name TEXT NOT NULL,
      created_at TEXT NOT NULL,
      synced_to_backend INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (original_sale_id) REFERENCES sales (id),
      FOREIGN KEY (return_id) REFERENCES sale_returns (id),
      FOREIGN KEY (replacement_sale_id) REFERENCES sales (id)
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_exchanges_original_sale '
        'ON exchanges (original_sale_id, created_at)');
  }

  // ── Transaction-aware variants ─────────────────────────────────────

  Future<int> upsertCustomerInTransaction(Transaction txn, Customer customer) {
    return DatabaseHelper.instance.upsertCustomer(customer);
  }

  // ── Public methods ─────────────────────────────────────────────────

  Future<int> upsertCustomer(Customer customer) async {
    return DatabaseHelper.instance.upsertCustomer(customer);
  }

  Future<Customer?> getCustomer(int id) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'customers',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Customer.fromMap(rows.first);
  }

  Future<List<Map<String, dynamic>>> getCustomers({bool activeOnly = true}) async {
    final db = await DatabaseHelper.instance.database;
    return db.query(
      'customers',
      where: activeOnly ? 'active = 1' : null,
      orderBy: 'name',
    );
  }
}
