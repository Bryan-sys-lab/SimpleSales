import 'package:sqflite/sqflite.dart';

import '../../../db/database_helper.dart';

/// Repository for Drinks profile operations.
///
/// Delegates to [DatabaseHelper] for now. Shot cups, cup templates and product
/// cups are created here to mirror `_onCreate` exactly so fresh installs and
/// upgraded tills cannot diverge.
class DrinksRepository {
  DrinksRepository._();
  static final DrinksRepository instance = DrinksRepository._();

  /// Creates (or verifies) the drinks tables: `shot_cups`, `cup_templates`,
  /// `product_cups` and `cup_size_suggestions`.
  ///
  /// Mirrors `_createShotCupsTable`, `_createCupTemplatesTable`,
  /// `_createProductCupsTable` and `_createCupSizeSuggestionsTable`.
  static Future<void> createTable(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS shot_cups (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      product_id INTEGER NOT NULL,
      product_name TEXT NOT NULL,
      capacity REAL NOT NULL DEFAULT 30,
      unit TEXT NOT NULL DEFAULT 'ml',
      price INTEGER NOT NULL DEFAULT 0,
      label TEXT NOT NULL DEFAULT 'Shot',
      active INTEGER NOT NULL DEFAULT 1,
      updated_at TEXT NOT NULL,
      synced_to_backend INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_shot_cups_product ON shot_cups (product_id)');

    await db.execute(
        'CREATE TABLE IF NOT EXISTS cup_templates (id INTEGER PRIMARY KEY AUTOINCREMENT, label TEXT NOT NULL DEFAULT \'Shot\', capacity REAL NOT NULL DEFAULT 0, unit TEXT NOT NULL DEFAULT \'ml\', price INTEGER NOT NULL DEFAULT 0, active INTEGER NOT NULL DEFAULT 1, updated_at TEXT NOT NULL)');

    await db.execute(
        'CREATE TABLE IF NOT EXISTS product_cups (product_id INTEGER NOT NULL, template_id INTEGER NOT NULL, price INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (product_id, template_id), FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE, FOREIGN KEY (template_id) REFERENCES cup_templates (id) ON DELETE CASCADE)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_product_cups_product ON product_cups (product_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_product_cups_template ON product_cups (template_id)');

    // Same shape as the legacy schema: the only writer
    // (`upsertCupSizeSuggestion` in database_helper.dart) stores size_ml, use_count and
    // created_at and has no size_name to give.
    await db.execute('''CREATE TABLE IF NOT EXISTS cup_size_suggestions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      product_id INTEGER,
      size_ml INTEGER NOT NULL,
      use_count INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL
    )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_cup_sizes_product '
        'ON cup_size_suggestions (product_id)');
  }
}
