import 'package:sqflite/sqflite.dart';

import 'migration.dart';

/// v82: adds `shift_id` to the `sales` table so every sale is attributed to
/// the shift that was open when it was recorded.
///
/// Sales recorded while no shift is open store `NULL`; sales recorded while a
/// shift is open store that shift's id so the shift ledger can reconcile
/// takings against the drawer.
class Migration082 extends Migration {
  Migration082._();

  static final Migration082 _instance = Migration082._();

  factory Migration082() => _instance;

  @override
  int get toVersion => 82;

  @override
  Future<void> migrate(DatabaseExecutor db) async {
    await db.execute('ALTER TABLE sales ADD COLUMN shift_id INTEGER');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sales_shift ON sales (shift_id)');
  }
}
