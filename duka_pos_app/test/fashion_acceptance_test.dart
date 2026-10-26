import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/models/credit.dart';
import 'package:duka_pos/models/layby.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/utils/money.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late DatabaseHelper db;
  late int shirtId;
  late int darkVariantId;
  late int redVariantId;
  late int customerId;

  setUp(() async {
    DatabaseHelper.resetForTests();
    db = await DatabaseHelper.openInMemoryForTests();
    shirtId = await db.upsertProduct(Product(
      name: 'Linen shirt',
      category: 'Fashion',
      costPrice: Money.fromMinor(700),
      sellPrice: Money.fromMinor(1800),
      stockQty: 5,
      reorderLevel: 0,
      trackVariants: true,
      updatedAt: DateTime.now().toIso8601String(),
    ));
    darkVariantId = await db.upsertVariant(ProductVariant(
      productId: shirtId,
      name: 'Dark / M',
      sellPrice: Money.fromMinor(1800),
      costPrice: Money.fromMinor(700),
      stockQty: 5,
    ));
    final redProductId = await db.upsertProduct(Product(
      name: 'Red linen shirt',
      category: 'Fashion',
      costPrice: Money.fromMinor(900),
      sellPrice: Money.fromMinor(2200),
      stockQty: 1,
      reorderLevel: 0,
      trackVariants: true,
      updatedAt: DateTime.now().toIso8601String(),
    ));
    redVariantId = await db.upsertVariant(ProductVariant(
      productId: redProductId,
      name: 'Red / M',
      sellPrice: Money.fromMinor(2200),
      costPrice: Money.fromMinor(900),
      stockQty: 1,
    ));
    customerId = await db.upsertCustomer(Customer(
      uuid: 'fashion-acceptance-customer',
      name: 'Njeri',
      createdAt: DateTime.now().toIso8601String(),
    ));
  });

  tearDown(() => DatabaseHelper.resetForTests());

  SaleItem item({
    required int productId,
    required int variantId,
    required String name,
    required Money price,
    required Money cost,
    Money discount = Money.zero,
  }) =>
      SaleItem(
        saleId: 0,
        productId: productId,
        variantId: variantId,
        productName: name,
        variantName: name,
        qty: 1,
        unitPrice: price,
        unitCost: cost,
        discount: discount,
        priceOverridden: !discount.isZero,
      );

  test('Fashion acceptance: variant markdown, lay-by lifecycle and exchange',
      () async {
    await db.setSetting(DatabaseHelper.settingDiscountsEnabled, '1');

    // Variant sale with a recorded markdown.
    final markdownSaleId = await db.recordSale(
      staffName: 'Amina',
      items: [
        item(
          productId: shirtId,
          variantId: darkVariantId,
          name: 'Linen shirt · Dark / M',
          price: Money.fromMinor(1800),
          cost: Money.fromMinor(700),
          discount: Money.fromMinor(200),
        ),
      ],
    );
    final markdownSale = await db.getSaleById(markdownSaleId);
    expect(markdownSale!.items.single.variantId, darkVariantId);
    expect(markdownSale.items.single.discount, Money.fromMinor(200));

    SaleItem laybyItem = item(
      productId: shirtId,
      variantId: darkVariantId,
      name: 'Linen shirt · Dark / M',
      price: Money.fromMinor(1800),
      cost: Money.fromMinor(700),
    );
    final completingLayby = await db.createLayby(
      customerId: customerId,
      items: [laybyItem],
      deposit: Money.fromMinor(900),
      depositMethod: 'cash',
      dueAt: DateTime.now().add(const Duration(days: 7)),
      staffName: 'Amina',
    );
    await db.addLaybyPayment(
      laybyId: completingLayby,
      amount: Money.fromMinor(900),
      method: 'cash',
      staffName: 'Amina',
    );
    final completedSaleId =
        await db.completeLayby(completingLayby, staffName: 'Amina');
    expect((await db.getLayby(completingLayby))!.status, LaybyStatus.completed);
    expect(completedSaleId, greaterThan(0));

    final cancelledLayby = await db.createLayby(
      customerId: customerId,
      items: [laybyItem],
      deposit: Money.fromMinor(900),
      depositMethod: 'cash',
      dueAt: DateTime.now().add(const Duration(days: 7)),
      staffName: 'Amina',
    );
    await db.cancelLayby(laybyId: cancelledLayby, staffName: 'Amina');
    final cancelled = await db.getLayby(cancelledLayby);
    expect(cancelled!.status, LaybyStatus.cancelled);
    expect(cancelled.payments.last.isRefund, isTrue);

    // Exchange the markdown sale for a higher-priced variant and reconcile
    // the credit note with the replacement sale and cash difference.
    final replacementProduct = (await db.getProducts())
        .firstWhere((product) => product.name == 'Red linen shirt');
    final exchangeSaleId = await db.recordExchange(
      originalSale: markdownSale,
      returnedLines: [
        ReturnLineDraft(
          saleItemId: markdownSale.items.single.id!,
          qty: 1,
          restock: true,
        ),
      ],
      replacementItems: [
        item(
          productId: replacementProduct.id!,
          variantId: redVariantId,
          name: 'Red linen shirt · Red / M',
          price: Money.fromMinor(2200),
          cost: Money.fromMinor(900),
        ),
      ],
      reason: 'Customer changed colour',
      staffName: 'Amina',
      paymentMethod: 'cash',
    );
    final database = await db.database;
    final exchange = (await database.query('exchanges')).single;
    final returnRow = (await database.query('sale_returns')).single;
    final allocation = (await database.query('sale_return_refunds')).single;
    expect(exchange['status'], 'completed');
    expect(exchange['replacement_sale_id'], exchangeSaleId);
    expect(exchange['difference_direction'], 'customer_pays');
    expect(exchange['difference_minor'], 600);
    expect(returnRow['kind'], 'exchange');
    expect(allocation['method'], 'exchange_credit');
    expect(allocation['amount_minor'], 1600);
  });
}
