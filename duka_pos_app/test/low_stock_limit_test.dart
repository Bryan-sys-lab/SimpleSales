// The low-stock limit a seller sets, applied across the catalogue.
//
// A shop deciding its limit is 8, not 5, is not a decision about 214 products
// one at a time. An owner who will not tap through an editor 214 times ends up
// with a dashboard warning about nothing, which trains them to ignore it — so
// the limit is settable in one place, and the write has to actually reach every
// row it claims to, in one transaction, or the count on the dashboard and the
// catalogue disagree.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/utils/money.dart';

final String _now = DateTime.now().toIso8601String();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('setting the limit rewrites every active product, once', () async {
    DatabaseHelper.resetForTests();
    final db = await DatabaseHelper.openInMemoryForTests();
    await db.upsertProduct(Product(
        name: 'A',
        category: 'Beer',
        costPrice: Money.zero,
        sellPrice: Money.zero,
        reorderLevel: 5,
        stockQty: 0,
        updatedAt: _now));
    await db.upsertProduct(Product(
        name: 'B',
        category: 'Beer',
        costPrice: Money.zero,
        sellPrice: Money.zero,
        reorderLevel: 5,
        stockQty: 0,
        updatedAt: _now));
    await db.upsertProduct(Product(
        name: 'C',
        category: 'Beer',
        costPrice: Money.zero,
        sellPrice: Money.zero,
        reorderLevel: 12,
        stockQty: 3,
        updatedAt: _now));

    final changed = await db.setLowStockLimit(8);

    expect(changed, 3);
    for (final p in await db.getProducts(activeOnly: false)) {
      expect(p.reorderLevel, 8, reason: '${p.name} got the new limit');
      expect(p.isLow, p.stockQty <= 8,
          reason: '${p.name} low-stock follows the new limit');
    }
    expect(await db.countLowStockProducts(), 3, reason: 'all three now warn');
    DatabaseHelper.resetForTests();
  });

  test('an empty catalogue sets nothing and says so', () async {
    DatabaseHelper.resetForTests();
    final db = await DatabaseHelper.openInMemoryForTests();
    expect(await db.setLowStockLimit(8), 0);
    DatabaseHelper.resetForTests();
  });
}
