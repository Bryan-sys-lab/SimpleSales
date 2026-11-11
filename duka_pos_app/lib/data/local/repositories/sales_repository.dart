import 'package:sqflite/sqflite.dart';

import '../../../db/database_helper.dart';
import '../../../models/models.dart';
import '../../../utils/money.dart';

/// Repository for sales and sale items.
///
/// Delegates to [DatabaseHelper] for now; the SQL is owned by [DatabaseHelper]
/// until Phase 8 moves it into this repository. Transaction-aware variants
/// accept an open [Transaction] and never open their own transaction, so a
/// sale, its items, stock movement and financial event can commit atomically.
class SalesRepository {
  SalesRepository._();
  static final SalesRepository instance = SalesRepository._();

  /// Creates (or verifies) the `sales` and `sale_items` tables.
  ///
  /// The DDL mirrors `_onCreate` exactly so fresh installs and upgraded
  /// tills cannot diverge. Called by [schema] `_onCreate`.
  static Future<void> createTable(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS sales (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      staff_name TEXT NOT NULL,
      staff_id INTEGER,
      total INTEGER NOT NULL,
      profit INTEGER NOT NULL,
      payment_method TEXT NOT NULL DEFAULT 'cash',
      payment_reference TEXT,
      amount_tendered INTEGER NOT NULL DEFAULT 0,
      change_given INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      vat_rate_percent INTEGER,
      etims_status TEXT,
      etims_receipt_number TEXT,
      etims_qr_payload TEXT,
      payment_verified INTEGER NOT NULL DEFAULT 1,
      payment_confirmed_at TEXT,
      subtotal_minor INTEGER,
      order_discount_minor INTEGER NOT NULL DEFAULT 0,
      order_discount_reason_id INTEGER,
      discount_approved_by INTEGER,
      buyer_name TEXT,
      buyer_tin TEXT,
      synced_to_backend INTEGER NOT NULL DEFAULT 0
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sales_date ON sales (created_at)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sales_staff ON sales (staff_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sales_payment_verified ON sales (payment_verified, created_at DESC)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_etims_status ON sales (etims_status)');

    await db.execute('''CREATE TABLE IF NOT EXISTS sale_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sale_id INTEGER NOT NULL,
      product_id INTEGER NOT NULL,
      product_name TEXT NOT NULL,
      qty REAL NOT NULL,
      unit_price INTEGER NOT NULL,
      unit_cost INTEGER NOT NULL,
      portion TEXT NOT NULL DEFAULT 'full',
      portion_ml INTEGER NOT NULL DEFAULT 0,
      variant_id INTEGER,
      variant_name TEXT NOT NULL DEFAULT '',
      pack_id INTEGER,
      pack_qty REAL,
      list_unit_price_minor INTEGER,
      discount_minor INTEGER NOT NULL DEFAULT 0,
      discount_reason_id INTEGER,
      price_overridden INTEGER NOT NULL DEFAULT 0,
      tax_rule_id TEXT,
      tax_rule_version INTEGER,
      FOREIGN KEY (sale_id) REFERENCES sales (id)
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sale_items_product ON sale_items (product_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sale_items_sale ON sale_items (sale_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sale_items_tax_rule ON sale_items (tax_rule_id)');

    await db.execute('''CREATE TABLE IF NOT EXISTS receipt_shares (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      sale_id INTEGER NOT NULL,
      token TEXT,
      url TEXT,
      recipient_masked TEXT,
      created_at TEXT NOT NULL,
      expires_at TEXT,
      revoked_at TEXT,
      status TEXT NOT NULL DEFAULT 'active',
      FOREIGN KEY (sale_id) REFERENCES sales (id) ON DELETE CASCADE
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_receipt_shares_sale '
        'ON receipt_shares (sale_id, created_at)');

    await db.execute('''CREATE TABLE IF NOT EXISTS held_carts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      staff_id INTEGER,
      staff_name TEXT NOT NULL,
      customer_id INTEGER,
      created_at TEXT NOT NULL,
      expires_at TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'held'
    )''');

    await db.execute('''CREATE TABLE IF NOT EXISTS held_cart_lines (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      held_cart_id INTEGER NOT NULL,
      product_id INTEGER NOT NULL,
      product_name TEXT NOT NULL,
      qty REAL NOT NULL,
      portion TEXT NOT NULL,
      portion_ml INTEGER NOT NULL DEFAULT 0,
      variant_id INTEGER,
      variant_name TEXT NOT NULL DEFAULT '',
      shot_cup_id INTEGER,
      shot_label TEXT,
      shot_capacity_ml INTEGER,
      shot_price INTEGER,
      unit_price INTEGER NOT NULL,
      unit_cost INTEGER NOT NULL,
      discount_minor INTEGER NOT NULL DEFAULT 0,
      discount_reason_id INTEGER,
      pack_id INTEGER,
      pack_qty REAL,
      FOREIGN KEY (held_cart_id) REFERENCES held_carts (id) ON DELETE CASCADE
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_held_cart_lines_cart '
        'ON held_cart_lines (held_cart_id)');

    await db.execute('''CREATE TABLE IF NOT EXISTS pending_etims (
      sale_id INTEGER PRIMARY KEY,
      receipt_number TEXT NOT NULL,
      attempts INTEGER NOT NULL DEFAULT 0,
      last_error TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY (sale_id) REFERENCES sales (id) ON DELETE CASCADE
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_pending_etims_created ON pending_etims (created_at)');
  }

  /// Creates (or verifies) the `sale_payments` table.
  ///
  /// Mirrors `_createFoundationTables`. Must run after `sales` exists
  /// (`sale_payments.sale_id` references `sales.id`).
  static Future<void> createSalePaymentsTable(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS sale_payments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      sale_id INTEGER NOT NULL,
      method TEXT NOT NULL,
      amount_minor INTEGER NOT NULL,
      tendered_minor INTEGER,
      change_minor INTEGER,
      reference TEXT,
      status TEXT NOT NULL DEFAULT 'confirmed',
      pending_payment_id INTEGER,
      created_at TEXT NOT NULL,
      FOREIGN KEY (sale_id) REFERENCES sales (id) ON DELETE CASCADE
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sale_payments_sale ON sale_payments (sale_id)');
  }

  // ── Transaction-aware variants ─────────────────────────────────────

  /// Records a sale within [txn], which is already part of a larger
  /// transaction. Never opens its own transaction.
  Future<int> recordSaleInTransaction(Transaction txn, {
    required String staffName,
    required List<SaleItem> items,
    List<SaleTender>? tenders,
    bool enforceStock = true,
    String paymentMethod = 'cash',
    String? paymentReference,
    Money? amountTendered,
    int? staffId,
    bool etimsPending = false,
    bool paymentVerified = true,
    int? customerId,
    int? creditApprovedBy,
    int? discountApprovedBy,
    int? orderDiscountReasonId,
    int? laybyId,
  }) async {
    return DatabaseHelper.instance.recordSale(
      staffName: staffName,
      items: items,
      tenders: tenders,
      enforceStock: enforceStock,
      paymentMethod: paymentMethod,
      paymentReference: paymentReference,
      amountTendered: amountTendered,
      staffId: staffId,
      etimsPending: etimsPending,
      paymentVerified: paymentVerified,
      customerId: customerId,
      creditApprovedBy: creditApprovedBy,
      discountApprovedBy: discountApprovedBy,
      orderDiscountReasonId: orderDiscountReasonId,
      laybyId: laybyId,
      existingTransaction: txn,
    );
  }

  // ── Public methods ─────────────────────────────────────────────────

  Future<int> recordSale({
    required String staffName,
    required List<SaleItem> items,
    List<SaleTender>? tenders,
    bool enforceStock = true,
    String paymentMethod = 'cash',
    String? paymentReference,
    Money? amountTendered,
    int? staffId,
    bool etimsPending = false,
    bool paymentVerified = true,
    int? customerId,
    int? creditApprovedBy,
    int? discountApprovedBy,
    int? orderDiscountReasonId,
    int? laybyId,
  }) async {
    return DatabaseHelper.instance.recordSale(
      staffName: staffName,
      items: items,
      tenders: tenders,
      enforceStock: enforceStock,
      paymentMethod: paymentMethod,
      paymentReference: paymentReference,
      amountTendered: amountTendered,
      staffId: staffId,
      etimsPending: etimsPending,
      paymentVerified: paymentVerified,
      customerId: customerId,
      creditApprovedBy: creditApprovedBy,
      discountApprovedBy: discountApprovedBy,
      orderDiscountReasonId: orderDiscountReasonId,
      laybyId: laybyId,
    );
  }

  Future<List<Map<String, dynamic>>> getSales({
    int? staffId,
    String? from,
    String? to,
    int limit = 200,
  }) async {
    final db = await DatabaseHelper.instance.database;
    return db.query(
      'sales',
      where: (staffId != null ? 'staff_id = ?' : null),
      whereArgs: staffId != null ? [staffId] : null,
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }
}
