// The stock ledger, the payments and the tax snapshots.
//
// Three properties, each of which is a thing the app now claims to be true:
//
//   1. Every change to a count leaves a row that says who moved it and why.
//   2. The count a product shows is the sum of its ledger rows.
//   3. The parts of a sale's payment add up to the sale's total.
//
// A ledger that cannot be checked is a ledger nobody believes. The check
// below is the one the Diagnostics screen offers the owner, and it is the
// same code these tests use — so a green test and a green screen mean the
// same thing.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/models/stock_movement.dart';
import 'package:duka_pos/utils/money.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late DatabaseHelper db;
  late int colaId;

  setUp(() async {
    DatabaseHelper.resetForTests();
    db = await DatabaseHelper.openInMemoryForTests();
    colaId = await db.upsertProduct(Product(
      name: 'Cola',
      category: 'Drinks',
      costPrice: Money.fromMajor(60),
      sellPrice: Money.fromMajor(100),
      stockQty: 24,
      reorderLevel: 6,
      updatedAt: DateTime.now().toIso8601String(),
    ));
  });

  Future<int> sellOne({int qty = 1, int productId = 0}) async {
    final int id = productId == 0 ? colaId : productId;
    return db.recordSale(
      staffName: 'Alice',
      staffId: 7,
      items: <SaleItem>[
        SaleItem(
          saleId: 0,
          productId: id,
          productName: 'Cola',
          qty: qty.toDouble(),
          unitPrice: Money.fromMajor(100),
          unitCost: Money.fromMajor(60),
        ),
      ],
      paymentMethod: 'cash',
      amountTendered: Money.fromMajor(100 * qty),
    );
  }

  group('the ledger', () {
    test('a product arrives with an opening row', () async {
      final movements = await db.getStockMovements(colaId);
      expect(movements, hasLength(1));
      expect(movements.single.type, StockMovementType.opening);
      expect(movements.single.qtyDelta, 24);
      expect(movements.single.balanceAfter, 24);
    });

    test('a sale leaves one row that says what it took', () async {
      final int saleId = await sellOne(qty: 3);

      final movements = await db.getStockMovements(colaId);
      expect(movements, hasLength(2));
      final sale =
          movements.firstWhere((m) => m.type == StockMovementType.sale);
      expect(sale.qtyDelta, -3);
      expect(sale.balanceAfter, 21);
      expect(sale.referenceType, 'sale');
      expect(sale.referenceId, saleId);
      expect(sale.staffName, 'Alice');
      expect(sale.staffId, 7);
    });

    test('the count is the sum of the rows', () async {
      await sellOne(qty: 3);
      await sellOne(qty: 2);

      expect(await db.ledgerBalance(colaId), 19);
      final product =
          (await db.getProducts()).firstWhere((p) => p.id == colaId);
      expect(product.stockQty, 19,
          reason: 'the cached count and the ledger must agree');
    });

    test('a correction leaves a row too', () async {
      await db.adjustStock(
        StockAdjustment(
          productId: colaId,
          productName: 'Cola',
          delta: -4,
          reason: 'breakage',
          staffName: 'Alice',
          createdAt: DateTime.now().toIso8601String(),
        ),
        staffId: 7,
      );

      final movements = await db.getStockMovements(colaId);
      final correction =
          movements.firstWhere((m) => m.type == StockMovementType.adjustment);
      expect(correction.qtyDelta, -4);
      expect(correction.balanceAfter, 20);
      expect(await db.ledgerBalance(colaId), 20);
    });

    test('a count and a sale still add up after both happen', () async {
      await sellOne(qty: 3);
      await db.adjustStock(
        StockAdjustment(
          productId: colaId,
          productName: 'Cola',
          delta: 5,
          reason: 'delivery',
          staffName: 'Alice',
          createdAt: DateTime.now().toIso8601String(),
        ),
        staffId: 7,
      );
      await sellOne(qty: 1);

      expect(await db.ledgerBalance(colaId), 25);
      final product =
          (await db.getProducts()).firstWhere((p) => p.id == colaId);
      expect(product.stockQty, 25);
    });

    test('every row of every product agrees with its count', () async {
      // The property the Diagnostics check states, run over a mixed history.
      await sellOne(qty: 3);
      await sellOne(qty: 2);
      await db.adjustStock(
        StockAdjustment(
          productId: colaId,
          productName: 'Cola',
          delta: -1,
          reason: 'spill',
          staffName: 'Alice',
          createdAt: DateTime.now().toIso8601String(),
        ),
        staffId: 7,
      );

      final differences = await db.findLedgerDifferences();
      expect(differences, isEmpty,
          reason: 'a migrated or used database must report no differences');
    });

    test('a variant has its own rows, and the parent has the aggregate',
        () async {
      final int productId = await db.upsertProduct(Product(
        name: 'Cola',
        category: 'Drinks',
        costPrice: Money.fromMajor(60),
        sellPrice: Money.fromMajor(100),
        stockQty: 0,
        reorderLevel: 6,
        trackVariants: true,
        updatedAt: DateTime.now().toIso8601String(),
      ));
      final int variantId = await db.upsertVariant(ProductVariant(
        productId: productId,
        name: 'Dark',
        sizeMl: 500,
        sellPrice: Money.fromMajor(100),
        stockQty: 10,
      ));

      await db.recordSale(
        staffName: 'Alice',
        staffId: 7,
        items: <SaleItem>[
          SaleItem(
            saleId: 0,
            productId: productId,
            productName: 'Cola Dark',
            qty: 2,
            unitPrice: Money.fromMajor(100),
            unitCost: Money.fromMajor(60),
            variantId: variantId,
            variantName: 'Dark',
          ),
        ],
        paymentMethod: 'cash',
        amountTendered: Money.fromMajor(200),
      );

      expect(await db.ledgerBalance(productId, variantId: variantId), 8);
      expect(await db.ledgerBalance(productId), 8);
      expect(await db.findLedgerDifferences(), isEmpty);
    });
  });

  group('the payments', () {
    test('a sale has one payment row', () async {
      final int saleId = await sellOne(qty: 2);

      final payments = await db.getSalePayments(saleId);
      expect(payments, hasLength(1));
      expect(payments.single.method, 'cash');
      expect(payments.single.amountMinor, 20000);
      expect(payments.single.status, SalePaymentStatus.confirmed);
    });

    test('the change is not counted as payment', () async {
      final int saleId = await db.recordSale(
        staffName: 'Alice',
        items: <SaleItem>[
          SaleItem(
            saleId: 0,
            productId: colaId,
            productName: 'Cola',
            qty: 1,
            unitPrice: Money.fromMajor(100),
            unitCost: Money.fromMajor(60),
          ),
        ],
        paymentMethod: 'cash',
        amountTendered: Money.fromMajor(500),
      );

      final payments = await db.getSalePayments(saleId);
      expect(payments.single.tenderedMinor, 50000);
      expect(payments.single.changeMinor, 40000);
      expect(payments.single.amountMinor, 10000,
          reason: 'change is not payment: the shop is owed 100, not 500');
    });

    test('an unverified payment says so', () async {
      final int saleId = await db.recordSale(
        staffName: 'Alice',
        items: <SaleItem>[
          SaleItem(
            saleId: 0,
            productId: colaId,
            productName: 'Cola',
            qty: 1,
            unitPrice: Money.fromMajor(100),
            unitCost: Money.fromMajor(60),
          ),
        ],
        paymentMethod: 'mpesa',
        amountTendered: Money.fromMajor(100),
        paymentVerified: false,
      );

      final payments = await db.getSalePayments(saleId);
      expect(payments.single.status, SalePaymentStatus.unverified);
    });
  });

  group('the tax snapshots', () {
    test('a sale stores the VAT it was taxed', () async {
      final int saleId = await sellOne(qty: 1);

      final row = await db.getSaleRowById(saleId);
      expect(row!['vat_minor'], isNotNull);
      expect(row['taxable_minor'], isNotNull);
      // KSh 100 at 16% VAT-inclusive: 10000 x 16 / 116 = 1379.31, rounded
      // half up by the one division rule the whole app shares.
      expect(row['vat_minor'], 1379);
      expect(row['taxable_minor'], 8621);
    });

    test('the line carries the rate and the class it was taxed at', () async {
      final int saleId = await sellOne(qty: 1);
      final sale = await db.getSaleById(saleId);
      final line = sale!.items.single;

      expect(line.vatRateBps, 1600);
      expect(line.taxClass, 'standard');
      expect(line.vatMinor, 1379);
    });

    test('the line VAT adds up to the sale VAT', () async {
      final int saleId = await db.recordSale(
        staffName: 'Alice',
        items: <SaleItem>[
          SaleItem(
            saleId: 0,
            productId: colaId,
            productName: 'Cola',
            qty: 1,
            unitPrice: Money.fromMajor(100),
            unitCost: Money.fromMajor(60),
          ),
          SaleItem(
            saleId: 0,
            productId: colaId,
            productName: 'Cola',
            qty: 1,
            unitPrice: Money.fromMajor(200),
            unitCost: Money.fromMajor(60),
          ),
        ],
        paymentMethod: 'cash',
        amountTendered: Money.fromMajor(300),
      );

      final sale = await db.getSaleById(saleId);
      final lineTotal =
          sale!.items.fold<int>(0, (sum, i) => sum + (i.vatMinor ?? 0));
      final row = await db.getSaleRowById(saleId);
      expect(row!['vat_minor'], lineTotal,
          reason: 'the sale VAT is the sum of the lines, with no rounding left '
              'over');
    });
  });
}
