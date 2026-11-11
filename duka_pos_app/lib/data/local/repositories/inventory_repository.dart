import 'package:sqflite/sqflite.dart';

import '../../../db/database_helper.dart';
import '../../../models/models.dart';
import '../../../models/stock_movement.dart';

/// Repository for products and inventory.
///
/// Manages persistence of products, variants, packs, barcodes, and stock
/// movements. Operations that touch multiple tables (e.g. recording a stock
/// movement and updating the product balance together) use transaction-aware
/// variants so the operation is atomic.
class InventoryRepository {
  InventoryRepository._();
  static final InventoryRepository instance = InventoryRepository._();

  /// Creates (or verifies) the `products` table.
  ///
  /// Mirrors `_onCreate` so fresh installs and upgraded tills match.
  static Future<void> createTable(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS products (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      category TEXT,
      cost_price INTEGER NOT NULL,
      sell_price INTEGER NOT NULL,
      stock_qty REAL NOT NULL DEFAULT 0,
      reserved_qty REAL NOT NULL DEFAULT 0,
      reorder_level INTEGER NOT NULL DEFAULT 5,
      bottle_ml INTEGER NOT NULL DEFAULT 750,
      half_price INTEGER,
      quarter_price INTEGER,
      excise_stamp_batch TEXT,
      active INTEGER NOT NULL DEFAULT 1,
      updated_at TEXT,
      remote_id TEXT,
      image_path TEXT,
      unit TEXT NOT NULL DEFAULT 'each',
      track_variants INTEGER NOT NULL DEFAULT 0,
      ml_per_kg REAL NOT NULL DEFAULT 0,
      track_expiry INTEGER NOT NULL DEFAULT 0
    )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_products_active ON products (active)');

    await db.execute('''CREATE TABLE IF NOT EXISTS stock_adjustments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      product_id INTEGER NOT NULL,
      product_name TEXT NOT NULL,
      delta INTEGER NOT NULL,
      reason TEXT,
      staff_name TEXT NOT NULL,
      staff_id INTEGER,
      created_at TEXT NOT NULL
    )''');

    await db.execute('''CREATE TABLE IF NOT EXISTS stock_movements (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      created_at TEXT NOT NULL,
      product_id INTEGER NOT NULL,
      variant_id INTEGER,
      movement_type TEXT NOT NULL,
      qty_delta REAL NOT NULL,
      unit_cost_minor INTEGER,
      reference_type TEXT,
      reference_id INTEGER,
      batch_id INTEGER,
      staff_id INTEGER,
      staff_name TEXT,
      note TEXT,
      balance_after REAL NOT NULL,
      synced_to_backend INTEGER NOT NULL DEFAULT 0
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_stock_movements_product ON stock_movements (product_id, created_at)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_stock_movements_variant ON stock_movements (variant_id, created_at)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_stock_movements_reference ON stock_movements (reference_type, reference_id)');

    await db.execute('''CREATE TABLE IF NOT EXISTS suppliers (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      phone TEXT,
      contact_person TEXT,
      notes TEXT,
      active INTEGER NOT NULL DEFAULT 1,
      synced_to_backend INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      lead_time_days TEXT,
      payment_terms TEXT,
      order_channel TEXT
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_suppliers_name ON suppliers (name)');

    await db.execute('''CREATE TABLE IF NOT EXISTS stock_receipts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      supplier_id INTEGER,
      supplier_ref TEXT,
      supplier_pin TEXT,
      etims_invoice_ref TEXT,
      input_vat_minor INTEGER,
      tax_evidence_status TEXT NOT NULL DEFAULT 'needs_review',
      received_at TEXT NOT NULL,
      staff_id INTEGER,
      staff_name TEXT NOT NULL,
      total_cost_minor INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'posted',
      note TEXT,
      synced_to_backend INTEGER NOT NULL DEFAULT 0
    )''');

    await db.execute('''CREATE TABLE IF NOT EXISTS stock_receipt_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      receipt_id INTEGER NOT NULL,
      product_id INTEGER NOT NULL,
      variant_id INTEGER,
      product_name TEXT NOT NULL,
      qty REAL NOT NULL,
      unit_cost_minor INTEGER NOT NULL DEFAULT 0,
      line_cost_minor INTEGER NOT NULL DEFAULT 0,
      old_cost_minor INTEGER,
      new_cost_minor INTEGER,
      expiry_date TEXT,
      batch_code TEXT,
      FOREIGN KEY (receipt_id) REFERENCES stock_receipts (id) ON DELETE CASCADE
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_stock_receipt_items_receipt '
        'ON stock_receipt_items (receipt_id)');

    await db.execute('''CREATE TABLE IF NOT EXISTS product_cost_history (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      product_id INTEGER NOT NULL,
      variant_id INTEGER,
      effective_at TEXT NOT NULL,
      old_cost_minor INTEGER NOT NULL DEFAULT 0,
      new_cost_minor INTEGER NOT NULL DEFAULT 0,
      reason TEXT NOT NULL DEFAULT 'receipt',
      receipt_id INTEGER
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_product_cost_history_product '
        'ON product_cost_history (product_id, effective_at)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS product_barcodes (
        barcode TEXT PRIMARY KEY NOT NULL,
        product_id INTEGER NOT NULL,
        kind TEXT NOT NULL DEFAULT 'supplier',
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_product_barcodes_product '
        'ON product_barcodes (product_id)');

    await db.execute('''CREATE TABLE IF NOT EXISTS product_price_history (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      product_id INTEGER NOT NULL,
      recorded_at TEXT NOT NULL,
      cost_price INTEGER NOT NULL,
      sell_price INTEGER NOT NULL,
      reason TEXT,
      FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_product_price_history_product_time '
        'ON product_price_history (product_id, recorded_at DESC, id DESC)');

    await db.execute('''CREATE TABLE IF NOT EXISTS product_suppliers (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      product_id INTEGER NOT NULL,
      supplier_id INTEGER NOT NULL,
      supplier_sku TEXT,
      pack_id INTEGER,
      preferred INTEGER NOT NULL DEFAULT 0,
      synced_to_backend INTEGER NOT NULL DEFAULT 0,
      UNIQUE(product_id, supplier_id),
      FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE,
      FOREIGN KEY (supplier_id) REFERENCES suppliers (id) ON DELETE CASCADE
    )''');

    await db.execute('''CREATE TABLE IF NOT EXISTS stock_batches (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      product_id INTEGER NOT NULL,
      variant_id INTEGER,
      batch_code TEXT,
      receipt_id INTEGER,
      received_at TEXT NOT NULL,
      expires_at TEXT NOT NULL,
      qty_remaining REAL NOT NULL,
      unit_cost_minor INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'active',
      FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE
    )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sale_item_batches (
        sale_item_id INTEGER NOT NULL,
        batch_id INTEGER NOT NULL,
        qty REAL NOT NULL,
        PRIMARY KEY (sale_item_id, batch_id),
        FOREIGN KEY (sale_item_id) REFERENCES sale_items (id) ON DELETE CASCADE,
        FOREIGN KEY (batch_id) REFERENCES stock_batches (id) ON DELETE RESTRICT
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_stock_batches_product_expiry '
        'ON stock_batches (product_id, expires_at, id)');

    await db.execute('''CREATE TABLE IF NOT EXISTS categories (
      name TEXT PRIMARY KEY NOT NULL,
      sort_order INTEGER NOT NULL DEFAULT 0
    )''');

    await db.execute('''CREATE TABLE IF NOT EXISTS stock_counts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      started_at TEXT NOT NULL,
      name TEXT,
      scope_type TEXT NOT NULL DEFAULT 'all',
      scope_ref TEXT,
      sales_mode TEXT NOT NULL DEFAULT 'keep_selling',
      completed_at TEXT,
      applied_at TEXT,
      applied_by INTEGER,
      note TEXT,
      status TEXT NOT NULL DEFAULT 'in_progress',
      blind INTEGER NOT NULL DEFAULT 0,
      freeze INTEGER NOT NULL DEFAULT 0,
      staff_id INTEGER,
      staff_name TEXT NOT NULL
    )''');

    await db.execute('''CREATE TABLE IF NOT EXISTS stock_count_lines (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      count_id INTEGER NOT NULL,
      product_id INTEGER NOT NULL,
      variant_id INTEGER,
      product_name TEXT NOT NULL,
      expected_qty REAL NOT NULL,
      counted_qty REAL,
      counted_by INTEGER,
      recount_required INTEGER NOT NULL DEFAULT 0,
      counted_at TEXT,
      note TEXT,
      FOREIGN KEY (count_id) REFERENCES stock_counts (id) ON DELETE CASCADE
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_stock_count_lines_count ON stock_count_lines (count_id, product_id, variant_id)');
  }

  // ── Transaction-aware variants ─────────────────────────────────────

  /// Writes a stock movement within an existing transaction.
  Future<void> writeStockMovementInTransaction(
    Transaction txn, {
    required int productId,
    required int? variantId,
    required int movementType,
    required int delta,
    required String? balanceAfter,
    required String reason,
    required String staffName,
    required int? staffId,
    required String createdAt,
  }) async {
    await txn.insert('stock_movements', {
      'product_id': productId,
      'variant_id': variantId,
      'movement_type': movementType,
      'delta': delta,
      'balance_after': balanceAfter,
      'reason': reason,
      'staff_name': staffName,
      'staff_id': staffId,
      'created_at': createdAt,
    });
  }

  // ── Product queries ────────────────────────────────────────────────

  Future<List<Product>> getProducts({bool activeOnly = true}) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('products',
        where: activeOnly ? 'active = 1' : null, orderBy: 'name');
    return rows.map((r) => Product.fromMap(r)).toList();
  }

  Future<Product?> getProductById(int id) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('products',
        where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Product.fromMap(rows.first);
  }

  Future<Product?> getProductByRemoteId(String remoteId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('products',
        where: 'remote_id = ?', whereArgs: [remoteId], limit: 1);
    return rows.isEmpty ? null : Product.fromMap(rows.first);
  }

  Future<double?> openingStockQtyForProduct(int productId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'stock_movements',
      columns: ['balance_after'],
      where:
          'product_id = ? AND variant_id IS NULL AND movement_type = ?',
      whereArgs: [productId, StockMovementType.opening.wire],
      orderBy: 'id ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return (rows.first['balance_after'] as num?)?.toDouble();
  }

  Future<Map<int, double?>> openingStockQtyForProducts(
      List<int> productIds) async {
    if (productIds.isEmpty) return <int, double?>{};
    final db = await DatabaseHelper.instance.database;
    final placeholders = List.filled(productIds.length, '?').join(',');
    final rows = await db.rawQuery(
      '''SELECT product_id, balance_after
         FROM stock_movements
         WHERE product_id IN ($placeholders)
           AND variant_id IS NULL
           AND movement_type = ?
         ORDER BY id ASC''',
      [...productIds, StockMovementType.opening.wire],
    );
    final result = <int, double?>{};
    for (final id in productIds) {
      result[id] = null;
    }
    for (final row in rows) {
      final id = row['product_id'] as int;
      if (!result.containsKey(id)) continue;
      result[id] = (row['balance_after'] as num?)?.toDouble();
    }
    return result;
  }

  Future<void> deactivateProduct(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.update('products', {'active': 0},
        where: 'id = ?', whereArgs: [id]);
  }
}
