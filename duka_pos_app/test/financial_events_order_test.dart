import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/utils/money.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    DatabaseHelper.resetForTests();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await DatabaseHelper.openInMemoryForTests();
  });

  Future<void> sellOne(int productId) =>
      DatabaseHelper.instance.recordSale(
        staffName: 'Amina',
        staffId: 7,
        paymentMethod: 'cash',
        items: <SaleItem>[
          SaleItem(
            saleId: 0,
            productId: productId,
            productName: 'Tusker',
            qty: 1,
            unitPrice: Money.fromMajor(100),
            unitCost: Money.fromMajor(60),
          ),
        ],
      );

  test('a limited read can return the LATEST events, not only the first',
      () async {
    final int productId =
        await DatabaseHelper.instance.upsertProduct(Product(
      name: 'Tusker',
      category: 'Beer',
      costPrice: Money.fromMajor(60),
      sellPrice: Money.fromMajor(100),
      stockQty: 50,
      reorderLevel: 2,
      bottleMl: 500,
      updatedAt: DateTime.now().toIso8601String(),
    ));
    for (var i = 0; i < 4; i++) {
      await sellOne(productId);
    }

    final oldest = await DatabaseHelper.instance.getFinancialEvents(limit: 2);
    final newest = await DatabaseHelper.instance
        .getFinancialEvents(limit: 2, newestFirst: true);

    expect(oldest, hasLength(2));
    expect(newest, hasLength(2));
    expect(oldest.first.id! < newest.first.id!, isTrue);
    expect(newest.first.id! > newest.last.id!, isTrue);
    final all = await DatabaseHelper.instance.getFinancialEvents(limit: 100);
    expect(newest.first.id, all.last.id);
  });
}
