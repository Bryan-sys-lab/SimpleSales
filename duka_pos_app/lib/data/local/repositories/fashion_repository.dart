import 'package:sqflite/sqflite.dart';

import '../../../db/database_helper.dart';

/// Repository for Fashion profile operations.
///
/// Delegates to [DatabaseHelper] for now. Product variants and product packs
/// are created here to mirror `_onCreate` exactly so fresh installs and
/// upgraded tills cannot diverge. Cross-table columns (`track_variants`,
/// `ml_per_kg` on `products`; `pack_id`, `pack_qty` on `sale_items`) are added
/// only when missing, matching the migration helpers they came from.
class FashionRepository {
  FashionRepository._();
  static final FashionRepository instance = FashionRepository._();

  /// Creates (or verifies) the fashion tables: `product_variants` and
  /// `product_packs`, plus the cross-table columns they introduce.
  ///
  /// Mirrors `_createVariantsAndImportTables` (variants + product columns) and
  /// `_migratePackHeldLines` (pack columns on sale_items).
  static Future<void> createTable(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS product_variants (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      product_id INTEGER NOT NULL,
      name TEXT NOT NULL,
      sku TEXT NOT NULL DEFAULT '',
      unit TEXT NOT NULL DEFAULT 'each',
      size_ml INTEGER NOT NULL DEFAULT 0,
      sell_price INTEGER NOT NULL DEFAULT 0,
      cost_price INTEGER NOT NULL DEFAULT 0,
      stock_qty REAL NOT NULL DEFAULT 0,
      reserved_qty REAL NOT NULL DEFAULT 0,
      reorder_level INTEGER NOT NULL DEFAULT 0,
      position INTEGER NOT NULL DEFAULT 0,
      active INTEGER NOT NULL DEFAULT 1,
      remote_id TEXT,
      FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_product_variants_product ON product_variants (product_id, position)');

    await _addColumnIfMissing(db, 'products', 'track_variants',
        'INTEGER NOT NULL DEFAULT 0');
    await _addColumnIfMissing(
        db, 'products', 'ml_per_kg', 'REAL NOT NULL DEFAULT 0');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS product_packs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        product_id INTEGER NOT NULL,
        variant_id INTEGER,
        name TEXT NOT NULL,
        barcode TEXT NOT NULL UNIQUE,
        units_per_pack REAL NOT NULL,
        unit_cost_minor INTEGER NOT NULL DEFAULT 0,
        sell_price_minor INTEGER,
        active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_product_packs_product ON product_packs (product_id, active)');

    await _addColumnIfMissing(db, 'sale_items', 'pack_id', 'INTEGER');
    await _addColumnIfMissing(db, 'sale_items', 'pack_qty', 'REAL');
  }

  static Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    final exists = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name = ?",
        [table]);
    if (exists.isEmpty) return;
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final names = columns.map((r) => r['name'] as String?).toSet();
    if (names.contains(column)) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }
}
