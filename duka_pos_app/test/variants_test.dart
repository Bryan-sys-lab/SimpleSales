// Product variants at the database boundary.
//
// The variants UI is exercised by its own widget tests; this pins the data
// behaviour that makes it possible at all — a variant owning its own price,
// stock and barcode, and being resolvable as a distinct thing at the till.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/utils/money.dart';
import 'package:duka_pos/utils/units.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late DatabaseHelper db;
  late int productId;

  setUp(() async {
    DatabaseHelper.resetForTests();
    db = await DatabaseHelper.openInMemoryForTests();
    productId = await db.upsertProduct(Product(
      name: 'Kenyana Beer',
      category: 'Beer',
      costPrice: Money.fromMajor(70),
      sellPrice: Money.fromMajor(120),
      stockQty: 24,
      reorderLevel: 5,
      unit: ProductUnit.cup,
      trackVariants: true,
      updatedAt: DateTime.now().toIso8601String(),
    ));
  });

  tearDown(() => DatabaseHelper.resetForTests());

  ProductVariant variant({
    int? id,
    required String name,
    String sku = '',
    int sizeMl = 500,
    int sell = 150,
    int stock = 20,
  }) =>
      ProductVariant(
        id: id,
        productId: productId,
        name: name,
        sku: sku,
        unit: ProductUnit.cup,
        sizeMl: sizeMl,
        sellPrice: Money.fromMinor(sell),
        costPrice: Money.fromMinor(90),
        stockQty: stock.toDouble(),
        reorderLevel: 5,
      );

  test('a variant keeps its own price and stock', () async {
    final id = await db.upsertVariant(variant(name: 'Dark'));
    final read = await db.getVariantById(id);
    expect(read!.name, 'Dark');
    expect(read.sellPrice, Money.fromMinor(150));
    expect(read.stockQty, 20);
    expect(read.sizeMl, 500);
  });

  test('two variants hold independent stock', () async {
    await db.upsertVariant(variant(name: 'Dark', stock: 20));
    await db.upsertVariant(variant(name: 'Regular', stock: 8));
    final all = await db.getVariants(productId);
    expect(all.map((v) => v.name), containsAll(['Dark', 'Regular']));
    expect(all.firstWhere((v) => v.name == 'Dark').stockQty, 20);
    expect(all.firstWhere((v) => v.name == 'Regular').stockQty, 8);
  });

  test('a variant barcode resolves to the variant, not just the product',
      () async {
    // A code on the parent answers for the parent.
    await db.addBarcode(
        productId: productId, barcode: '6001234567899', kind: BarcodeKind.own);
    expect((await db.getScanTarget('6001234567899'))!.variant, isNull);

    // A code on the variant resolves to it, so scanning Dark does not sell
    // Regular. Without this the variant is unscannable and the whole feature
    // is cosmetic.
    final id = await db.upsertVariant(variant(name: 'Dark'));
    expect(
      await db.addBarcode(
          productId: productId,
          barcode: 'DARK500',
          kind: BarcodeKind.own,
          variantId: id),
      isTrue,
    );
    final target = await db.getScanTarget('DARK500');
    expect(target!.variant, isNotNull);
    expect(target.variant!.name, 'Dark');
    expect(target.product.name, 'Kenyana Beer',
        reason: 'the parent is still what the cart row belongs to');
  });

  test('a product-level barcode scan returns the parent product', () async {
    await db.addBarcode(productId: productId, barcode: '6001234567899');
    final target = await db.getScanTarget('6001234567899');
    expect(target, isNotNull);
    expect(target!.product.name, 'Kenyana Beer');
    expect(target.variant, isNull);
  });

  test('an unknown barcode resolves to nothing rather than a guess', () async {
    expect(await db.getScanTarget('6000000000000'), isNull);
  });

  test('deleting a variant frees its barcode', () async {
    final id = await db.upsertVariant(variant(name: 'Dark'));
    // Attached to the *variant*, which is the code that has to be freed. A
    // product-level code is not touched by deleting a variant and must not be.
    expect(
      await db.addBarcode(
          productId: productId, barcode: 'DARK500', variantId: id),
      isTrue,
    );
    await db.deleteVariant(id);
    // The code must be free again, or the variant can never be re-added under
    // the same barcode — which is the bug the explicit delete exists to avoid.
    final again = await db.addBarcode(productId: productId, barcode: 'DARK500');
    expect(again, isTrue);
  });

  test('a product keeps its variants in the order the owner arranged',
      () async {
    await db.upsertVariant(variant(name: 'Regular'));
    await db.upsertVariant(variant(name: 'Dark'));
    expect((await db.getVariants(productId)).map((v) => v.name),
        ['Regular', 'Dark']);
  });

  test('a variant shows its volume in its label', () {
    expect(variant(name: 'Big cup', sizeMl: 500).label, 'Big cup 500 ml');
    expect(variant(name: 'Can', sizeMl: 0).label, 'Can',
        reason: 'a countable variant has no volume to show');
  });

  test('a variant is low when at or below its reorder level', () {
    expect(variant(name: 'Dark', stock: 5).isLow, isTrue);
    expect(variant(name: 'Dark', stock: 6).isLow, isFalse);
  });

  test('the product row records that it tracks variants', () async {
    final product = (await db.getProducts(activeOnly: false)).single;
    expect(product.trackVariants, isTrue);
    expect(product.unit, ProductUnit.cup);
  });
}
