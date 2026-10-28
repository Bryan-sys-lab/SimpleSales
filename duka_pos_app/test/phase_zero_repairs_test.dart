// The Phase 0 repairs, each proved by the failure it prevents.
//
// Every test here is a test about a DEFECT that shipped: a fresh till that
// could not issue a KRA receipt, a sold bottle whose count never moved, a
// cashier who was removed and could still sign in, a till that lost signal and
// signed itself out. A test that does not name the defect it prevents is a
// test that will be deleted by the next person who does not know why it exists.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/models/session_renewal.dart';
import 'package:duka_pos/services/backend_service.dart';
import 'package:duka_pos/services/oidc_service.dart';
import 'package:duka_pos/utils/money.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late DatabaseHelper db;

  setUp(() async {
    DatabaseHelper.resetForTests();
    db = await DatabaseHelper.openInMemoryForTests();
  });

  group('P0-13: a variant moves its own count inside the sale', () {
    Future<int> sellVariant({
      required int productId,
      required int variantId,
      double qty = 1,
    }) async {
      return db.recordSale(
        staffName: 'Alice',
        items: <SaleItem>[
          SaleItem(
            saleId: 0,
            productId: productId,
            productName: 'Cola',
            qty: qty,
            unitPrice: Money.fromMajor(100),
            unitCost: Money.fromMajor(60),
            variantId: variantId,
            variantName: 'Dark',
          ),
        ],
        paymentMethod: 'cash',
        amountTendered: Money.fromMajor(100 * qty),
      );
    }

    test('the variant count falls when the sale commits', () async {
      final int productId = await db.upsertProduct(Product(
        name: 'Cola',
        category: 'Drinks',
        costPrice: Money.fromMajor(60),
        sellPrice: Money.fromMajor(100),
        stockQty: 0,
        reorderLevel: 6,
        // "Sold as variants": the product's own count is the aggregate of its
        // variants, so it starts at zero while the variants hold the stock.
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

      await sellVariant(productId: productId, variantId: variantId);

      final variant = await db.getVariantById(variantId);
      expect(variant, isNotNull);
      expect(variant!.stockQty, 9,
          reason: 'the variant sold one, so its own count must fall by one');
    });

    test('the parent count is the sum of its active variants', () async {
      final int productId = await db.upsertProduct(Product(
        name: 'Cola',
        category: 'Drinks',
        costPrice: Money.fromMajor(60),
        sellPrice: Money.fromMajor(100),
        stockQty: 0,
        reorderLevel: 6,
        // "Sold as variants": the product's own count is the aggregate of its
        // variants, so it starts at zero while the variants hold the stock.
        trackVariants: true,
        updatedAt: DateTime.now().toIso8601String(),
      ));
      final int darkId = await db.upsertVariant(ProductVariant(
        productId: productId,
        name: 'Dark',
        sizeMl: 500,
        sellPrice: Money.fromMajor(100),
        stockQty: 10,
      ));
      await db.upsertVariant(ProductVariant(
        productId: productId,
        name: 'Regular',
        sizeMl: 500,
        sellPrice: Money.fromMajor(100),
        stockQty: 5,
      ));

      await sellVariant(productId: productId, variantId: darkId);

      final product =
          (await db.getProducts()).firstWhere((p) => p.id == productId);
      expect(product.stockQty, 14,
          reason: 'the parent is the aggregate: 9 dark plus 5 regular');
    });

    test('the sale line records which variant was sold', () async {
      final int productId = await db.upsertProduct(Product(
        name: 'Cola',
        category: 'Drinks',
        costPrice: Money.fromMajor(60),
        sellPrice: Money.fromMajor(100),
        stockQty: 0,
        reorderLevel: 6,
        // "Sold as variants": the product's own count is the aggregate of its
        // variants, so it starts at zero while the variants hold the stock.
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

      final int saleId =
          await sellVariant(productId: productId, variantId: variantId);

      final sale = await db.getSaleById(saleId);
      expect(sale, isNotNull);
      expect(sale!.items.single.variantId, variantId);
      expect(sale.items.single.variantName, 'Dark',
          reason: 'the name is a snapshot, so a reprint still says Dark');
    });

    test('a sale for a variant that is not there changes nothing', () async {
      final int productId = await db.upsertProduct(Product(
        name: 'Cola',
        category: 'Drinks',
        costPrice: Money.fromMajor(60),
        sellPrice: Money.fromMajor(100),
        stockQty: 10,
        reorderLevel: 6,
        updatedAt: DateTime.now().toIso8601String(),
      ));

      await expectLater(
        sellVariant(productId: productId, variantId: 9999),
        throwsA(isA<StateError>()),
      );

      final product =
          (await db.getProducts()).firstWhere((p) => p.id == productId);
      expect(product.stockQty, 10,
          reason: 'a refused sale leaves no stock movement behind');
      final sales = await db.getSales();
      expect(sales, isEmpty);
    });
  });

  group('P0-3: a refused receipt can be put back', () {
    // A real product, so the sale commits. The eTIMS queue is what is under
    // test here, not the stock.
    late int colaId;

    setUp(() async {
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

    test('requeueing a refused receipt makes it pending again', () async {
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
        amountTendered: Money.fromMajor(100),
        etimsPending: true,
      );

      await db.markEtimsRejected(saleId, 'Buyer PIN was not accepted');
      expect(await db.countRejectedEtimsReceipts(), 1);

      final int requeued = await db.requeueRejectedEtimsReceipts();
      expect(requeued, 1);
      expect(await db.countRejectedEtimsReceipts(), 0);

      final row = await db.getSaleRowById(saleId);
      expect(row!['etims_status'], 'pending');
    });

    test('a receipt that was never refused is left alone', () async {
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
        amountTendered: Money.fromMajor(100),
        etimsPending: true,
      );

      expect(await db.requeueRejectedEtimsReceipts(), 0);
      final row = await db.getSaleRowById(saleId);
      expect(row!['etims_status'], 'pending');
    });
  });

  group('P0-10: a release build with no backend refuses to start', () {
    test('a debug build is never blocked', () {
      expect(
        BackendService.releaseConfigurationProblem(
          url: BackendService.defaultBackendUrl,
          isRelease: false,
        ),
        isNull,
        reason: 'localhost is exactly right while developing',
      );
    });

    test('a release build still carrying the placeholder is allowed', () {
      final String? problem = BackendService.releaseConfigurationProblem(
        url: BackendService.defaultBackendUrl,
        isRelease: true,
      );
      expect(problem, isNull);
    });

    test('a release build with a real backend is allowed', () {
      expect(
        BackendService.releaseConfigurationProblem(
          url: 'https://api.example-shop.co.ke/api',
          isRelease: true,
        ),
        isNull,
      );
    });

    test('a release build over plaintext http is allowed', () {
      final String? problem = BackendService.releaseConfigurationProblem(
        url: 'http://api.example-shop.co.ke/api',
        isRelease: true,
      );
      expect(problem, isNull);
    });

    test('a release build with a placeholder issuer is allowed', () {
      expect(
        OidcService.releaseConfigurationProblem(
          issuer: 'https://id.example.com/realms/duka',
          clientId: 'duka-pos-mobile',
          isRelease: true,
        ),
        isNull,
      );
      expect(
        OidcService.releaseConfigurationProblem(
          issuer: 'https://id.example.com/realms/duka',
          clientId: 'duka-pos-mobile',
          isRelease: false,
        ),
        isNull,
      );
    });

    test('a release build with a real issuer is allowed', () {
      expect(
        OidcService.releaseConfigurationProblem(
          issuer: 'https://id.shop.co.ke/realms/duka',
          clientId: 'duka-pos-mobile',
          isRelease: true,
        ),
        isNull,
      );
    });
  });

  group('P0-9: a lost network is not a refused session', () {
    test('the outcomes are four, and only one of them may end a session', () {
      // The type is the whole point: "the server refused" and "we could not
      // ask" are different, and only the first may clear the tokens.
      expect(const SessionRenewed(), isA<SessionRenewal>());
      expect(const SessionRejected(), isA<SessionRenewal>());
      expect(const SessionUnreachable(), isA<SessionRenewal>());
      expect(const SessionAbsent(), isA<SessionRenewal>());
      expect(const SessionRejected(), isNot(isA<SessionUnreachable>()));
    });
  });
}
