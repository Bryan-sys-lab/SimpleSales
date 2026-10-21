// The photograph column on a product row, and the freshness that goes with it.
//
// A photograph is a PATH in the column and BYTES on the filesystem, and the
// two have to agree. This file pins the half that lives in the database:
// the path the editor writes is the path the till reads back, and the row says
// WHEN that path last changed.
//
// ## Why the row's freshness matters
//
// A photograph is REPLACED by writing a new picture OVER the file at the same
// path — `product_photos/<shop>/5.jpg` is the same string before and after.
// So the path in the column cannot tell the tile that what it is drawing is
// out of date: the till would go on showing the photograph that was there
// before, and the owner would pick the same picture twice.
//
// The row's `updated_at` is what says "the file behind this path may be a
// different photograph now", and the tile and the inventory row both pass it
// to the photo widget as its revision. A row whose timestamp has not moved is
// a row whose photograph is known to be the old one — so writing a photograph
// HAS to move the timestamp, or the replacement never reaches the screen.

import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/utils/money.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  Future<DatabaseHelper> withProduct() async {
    DatabaseHelper.resetForTests();
    final DatabaseHelper db = await DatabaseHelper.openInMemoryForTests();
    await db.upsertProduct(Product(
      id: 1,
      name: 'Kenyatta bread',
      category: 'Bakery',
      costPrice: Money.fromMajor(40),
      sellPrice: Money.fromMajor(60),
      stockQty: 12,
      reorderLevel: 3,
      updatedAt: '2026-01-01T00:00:00.000Z',
    ));
    return db;
  }

  tearDown(() {
    DatabaseHelper.resetForTests();
  });

  test('the photograph path the editor writes is the path the till reads back',
      () async {
    final DatabaseHelper db = await withProduct();

    await db.setProductImage('product_photos/legacy/5.jpg', 1);

    final Product after = (await db.getProducts(activeOnly: false)).single;
    expect(after.imagePath, 'product_photos/legacy/5.jpg');
  });

  test('a photograph REPLACED at the same path moves the row\'s freshness',
      () async {
    final DatabaseHelper db = await withProduct();

    await db.setProductImage('product_photos/legacy/5.jpg', 1);
    final Product afterFirst =
        (await db.getProducts(activeOnly: false)).single;
    expect(afterFirst.imagePath, 'product_photos/legacy/5.jpg');

    // The path is the same string — that is the whole point of a replaced
    // photograph — so only the freshness can say the file behind it changed.
    await db.setProductImage('product_photos/legacy/5.jpg', 1);
    final Product afterSecond =
        (await db.getProducts(activeOnly: false)).single;

    expect(afterSecond.imagePath, afterFirst.imagePath,
        reason: 'the path names the product, not the photograph');
    expect(afterSecond.updatedAt, isNot(afterFirst.updatedAt),
        reason: 'a replaced photograph has to reach the screen, and the path '
            'it shares with the old one cannot carry that news');
  });

  test('removing a photograph moves the freshness too', () async {
    final DatabaseHelper db = await withProduct();

    await db.setProductImage('product_photos/legacy/5.jpg', 1);
    final Product afterFirst =
        (await db.getProducts(activeOnly: false)).single;

    await db.setProductImage(null, 1);
    final Product afterSecond =
        (await db.getProducts(activeOnly: false)).single;

    expect(afterSecond.imagePath, isNull);
    expect(afterSecond.updatedAt, isNot(afterFirst.updatedAt));
  });

  test('writing a photograph touches nothing else on the row', () async {
    final DatabaseHelper db = await withProduct();
    final Product before = (await db.getProducts(activeOnly: false)).single;

    await db.setProductImage('product_photos/legacy/5.jpg', 1);

    final Product after = (await db.getProducts(activeOnly: false)).single;
    expect(after.name, before.name);
    expect(after.category, before.category);
    expect(after.stockQty, before.stockQty);
    expect(after.sellPrice, before.sellPrice);
    expect(after.costPrice, before.costPrice);
    expect(after.reorderLevel, before.reorderLevel);
    expect(after.active, before.active);
  });
}
