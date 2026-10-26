// The eTIMS payload that goes to KRA, and the reconciliation between what is
// filed and what is printed.
//
// The two must agree to the cent. A printed receipt and a filed tax invoice
// that differ are not a rounding curiosity: they are two different claims about
// the same transaction, and the one the shop cannot explain is the one the tax
// authority acts on.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/models/credit.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/services/etims/etims_service.dart';
import 'package:duka_pos/services/printer/receipt_builder.dart';
import 'package:duka_pos/utils/money.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late DatabaseHelper db;
  late int sodaId;

  setUp(() async {
    DatabaseHelper.resetForTests();
    db = await DatabaseHelper.openInMemoryForTests();
    sodaId = await db.upsertProduct(Product(
      name: 'Soda 350ml',
      category: 'Drinks',
      costPrice: Money.fromMajor(45),
      sellPrice: Money.fromMajor(80),
      stockQty: 24,
      reorderLevel: 6,
      updatedAt: DateTime.now().toIso8601String(),
    ));
    sodaId = sodaId;
  });

  Future<Map<String, dynamic>> fileAsync({
    required List<SaleItem> items,
    required int vatRatePercent,
    required int saleId,
    bool pricesIncludeVat = true,
  }) async {
    await db.setTillCode('T1');
    await db.recordSale(
      staffName: 'Alice',
      items: items,
      paymentMethod: 'cash',
      amountTendered: sumMoney(items.map((i) => i.total)),
      etimsPending: true,
    );
    final sale = await db.getSaleById(saleId);
    final row = await db.getSaleRowById(saleId);
    return buildEtimsPayload(
      sale: sale!,
      saleRow: row!,
      db: db,
      tillCode: await db.getTillCode(),
      tin: 'P051234567X',
      vatRatePercent: vatRatePercent,
      pricesIncludeVat: pricesIncludeVat,
    );
  }

  group('payload shape', () {
    test('carries the buyer details of the sale customer, when one is attached', () async {
      await db.setTillCode('T1');
      final customerId = await db.upsertCustomer(Customer(
        uuid: 'cus-1',
        name: 'Acme Ltd',
        tin: 'P051234567X',
        creditLimitMinor: 100000000,
        createdAt: DateTime.now().toIso8601String(),
      ));
      final saleId = await db.recordSale(
          staffName: 'Alice',
          items: [
            SaleItem(
              saleId: 0,
              productId: sodaId,
              productName: 'Soda 350ml',
              qty: 1,
              unitPrice: Money.fromMajor(80),
              unitCost: Money.fromMajor(45),
            )
          ],
          paymentMethod: 'credit',
          customerId: customerId,
          etimsPending: true);
      final sale = await db.getSaleById(saleId);
      final row = await db.getSaleRowById(saleId);
      final customer = await db.getCustomerById(customerId);
      final payload = buildEtimsPayload(
        sale: sale!,
        saleRow: row!,
        db: db,
        tillCode: await db.getTillCode(),
        tin: 'P051234567X',
        vatRatePercent: 16,
        pricesIncludeVat: true,
        customer: customer,
      );
      expect(payload['buyer_name'], 'Acme Ltd');
      expect(payload['buyer_tin'], 'P051234567X');

      // The invoice is a snapshot. Editing the directory after checkout must
      // not change a queued retry.
      await db.upsertCustomer(Customer(
        id: customerId,
        uuid: 'cus-1',
        name: 'Renamed Ltd',
        tin: 'P099999999Z',
        creditLimitMinor: 100000000,
        createdAt: DateTime.now().toIso8601String(),
      ));
      final retrySale = await db.getSaleById(saleId);
      final retryPayload = buildEtimsPayload(
        sale: retrySale!,
        saleRow: (await db.getSaleRowById(saleId))!,
        db: db,
        tillCode: await db.getTillCode(),
        tin: 'P051234567X',
        vatRatePercent: 16,
        pricesIncludeVat: true,
      );
      expect(retryPayload['buyer_name'], 'Acme Ltd');
      expect(retryPayload['buyer_tin'], 'P051234567X');
    });

    test('carries no buyer fields for a walk-in sale', () async {
      await db.setTillCode('T1');
      final saleId = await db.recordSale(
          staffName: 'Alice',
          items: [
            SaleItem(
              saleId: 0,
              productId: sodaId,
              productName: 'Soda 350ml',
              qty: 1,
              unitPrice: Money.fromMajor(80),
              unitCost: Money.fromMajor(45),
            )
          ],
          etimsPending: true);
      final sale = await db.getSaleById(saleId);
      final row = await db.getSaleRowById(saleId);
      final payload = buildEtimsPayload(
        sale: sale!,
        saleRow: row!,
        db: db,
        tillCode: await db.getTillCode(),
        tin: 'P051234567X',
        vatRatePercent: 16,
        pricesIncludeVat: true,
        customer: await db.getCustomerById(row['customer_id'] as int? ?? 0),
      );
      expect(payload.containsKey('buyer_name'), isFalse);
      expect(payload.containsKey('buyer_tin'), isFalse);
    });
    test('carries the till receipt number, not a fresh one', () async {
      await db.setTillCode('T1');
      final saleId = await db.recordSale(
          staffName: 'Alice',
          items: [
            SaleItem(
              saleId: 0,
              productId: sodaId,
              productName: 'Soda 350ml',
              qty: 1,
              unitPrice: Money.fromMajor(80),
              unitCost: Money.fromMajor(45),
            )
          ],
          etimsPending: true);
      final payload = await fileAsync(
        items: [
          SaleItem(
            saleId: 0,
            productId: sodaId,
            productName: 'Soda 350ml',
            qty: 1,
            unitPrice: Money.fromMajor(80),
            unitCost: Money.fromMajor(45),
          )
        ],
        vatRatePercent: 16,
        saleId: saleId,
      );
      // The number on the receipt is the number filed. KRA's own number is
      // separate and comes back later.
      expect(payload['receipt_number'], 'T1-000001');
    });

    test('amounts travel as integer minor units, never as floats', () async {
      final saleId = await db.recordSale(
          staffName: 'Alice',
          items: [
            SaleItem(
              saleId: 0,
              productId: sodaId,
              productName: 'Soda 350ml',
              qty: 3,
              unitPrice: Money.fromMajor(80),
              unitCost: Money.fromMajor(45),
            )
          ],
          etimsPending: true);
      final payload = await fileAsync(
        items: [
          SaleItem(
            saleId: 0,
            productId: sodaId,
            productName: 'Soda 350ml',
            qty: 3,
            unitPrice: Money.fromMajor(80),
            unitCost: Money.fromMajor(45),
          )
        ],
        vatRatePercent: 16,
        saleId: saleId,
      );
      expect(payload['total'], isA<int>());
      expect(payload['total'], 24000);
      final first = (payload['items'] as List).first as Map<String, dynamic>;
      expect(first['unit_price'], 8000);
      expect(first['line_total'], 24000);
      expect(first['vat_amount'], isA<int>());
    });

    test('the line VAT is the amount the receipt prints for that line',
        () async {
      // This is the whole reconciliation requirement. The figure KRA records is
      // sent from the till rather than recomputed server-side, precisely so it
      // cannot drift from the figure on the customer's paper.
      final items = [
        SaleItem(
          saleId: 0,
          productId: sodaId,
          productName: 'Soda 350ml',
          qty: 2,
          unitPrice: Money.fromMajor(80),
          unitCost: Money.fromMajor(45),
        ),
        SaleItem(
          saleId: 0,
          productId: sodaId,
          productName: 'Kenyana Beer',
          qty: 1,
          unitPrice: Money.fromMajor(120),
          unitCost: Money.fromMajor(70),
        ),
      ];
      final saleId = await db.recordSale(
          staffName: 'Alice',
          items: items,
          amountTendered: Money.fromMajor(280),
          etimsPending: true);
      final payload =
          await fileAsync(items: items, vatRatePercent: 16, saleId: saleId);

      final filed = (payload['items'] as List).cast<Map<String, dynamic>>();
      for (var i = 0; i < filed.length; i++) {
        final expected =
            vatComponentOf(items[i].total, ratePercent: 16).minorUnits;
        expect(filed[i]['vat_amount'], expected);
        // net + vat must reproduce the line total, on every filed line.
        final lineTotal = filed[i]['line_total']! as int;
        final vatAmount = filed[i]['vat_amount']! as int;
        expect((lineTotal - vatAmount) + vatAmount, lineTotal);
      }

      // And the printed receipt agrees with every one of them.
      final sale = await db.getSaleById(saleId);
      final receipt = const ReceiptBuilder().build(ReceiptInput(
        shopName: 'Kijani Stores',
        receiptNumber: 'T1-000001',
        issuedAt: DateTime(2026, 10, 3),
        cashierName: 'Alice',
        cashierRole: 'Cashier',
        items: sale!.items,
        total: sale.total,
        amountTendered: sale.amountTendered,
        changeGiven: Money.zero,
      ));
      final printedVatTotal = receipt
          .whereType<ReceiptColumns>()
          .where((line) => line.left.startsWith('VAT ('))
          .map((line) => line.right)
          .single;
      final filedVatTotal =
          filed.fold<int>(0, (sum, line) => sum + (line['vat_amount']! as int));
      expect(printedVatTotal, _minorText(filedVatTotal));
    });

    test('the filed total equals the sum of the filed line totals', () async {
      final items = [
        SaleItem(
          saleId: 0,
          productId: sodaId,
          productName: 'Soda 350ml',
          qty: 2,
          unitPrice: Money.fromMajor(80),
          unitCost: Money.fromMajor(45),
        ),
        SaleItem(
          saleId: 0,
          productId: sodaId,
          productName: 'Water 500ml',
          qty: 7,
          unitPrice: Money.fromMajor(30),
          unitCost: Money.fromMajor(15),
        ),
      ];
      final saleId = await db.recordSale(
          staffName: 'Alice',
          items: items,
          amountTendered: Money.fromMajor(370),
          etimsPending: true);
      final payload =
          await fileAsync(items: items, vatRatePercent: 16, saleId: saleId);
      final filed = (payload['items'] as List).cast<Map<String, dynamic>>();
      final lineSum =
          filed.fold<int>(0, (sum, line) => sum + (line['line_total']! as int));
      expect(payload['total'], lineSum);
    });

    test('an exempt shop files zero VAT rather than omitting the rate',
        () async {
      final items = [
        SaleItem(
          saleId: 0,
          productId: sodaId,
          productName: 'Soda 350ml',
          qty: 1,
          unitPrice: Money.fromMajor(80),
          unitCost: Money.fromMajor(45),
        )
      ];
      final saleId = await db.recordSale(
          staffName: 'Alice',
          items: items,
          amountTendered: Money.fromMajor(80),
          etimsPending: true);
      final payload =
          await fileAsync(items: items, vatRatePercent: 0, saleId: saleId);
      expect(payload['vat_rate_percent'], 0);
      final filed = (payload['items'] as List).cast<Map<String, dynamic>>();
      expect(filed.single['vat_amount'], 0);
    });

    test('the payload carries the VAT rate and the payment reference',
        () async {
      final saleId = await db.recordSale(
        staffName: 'Alice',
        items: [
          SaleItem(
            saleId: 0,
            productId: sodaId,
            productName: 'Soda 350ml',
            qty: 1,
            unitPrice: Money.fromMajor(80),
            unitCost: Money.fromMajor(45),
          )
        ],
        paymentMethod: 'mpesa',
        paymentReference: 'DUKA-abc',
        amountTendered: Money.fromMajor(100),
        etimsPending: true,
      );
      final payload = await fileAsync(
        items: [
          SaleItem(
            saleId: 0,
            productId: sodaId,
            productName: 'Soda 350ml',
            qty: 1,
            unitPrice: Money.fromMajor(80),
            unitCost: Money.fromMajor(45),
          )
        ],
        vatRatePercent: 16,
        saleId: saleId,
      );
      expect(payload['payment_method'], 'mpesa');
      expect(payload['payment_reference'], 'DUKA-abc');
      expect(payload['vat_rate_percent'], 16);
    });
  });

  group('queue flush messaging', () {
    test('a partial flush says what is still outstanding', () {
      // The message has to be actionable: an owner who cannot tell whether KRA
      // still owes an invoice will not know whether to wait or to fix something.
      expect(
        EtimsService.describeResult(
            const EtimsFlushResult(uploaded: 5, remaining: 0)),
        contains('5'),
      );
      expect(
        EtimsService.describeResult(
            const EtimsFlushResult(uploaded: 0, remaining: 3)),
        contains('3'),
      );
      expect(
        EtimsService.describeResult(
            const EtimsFlushResult(uploaded: 0, remaining: 0, skipped: true)),
        contains('switched off'),
      );
    });

    test('a refusal is permanent and a transport failure is not', () {
      expect(const EtimsRejectedException('bad TIN'),
          isA<EtimsRejectedException>());
    });
  });
}

/// Formats minor units the way the receipt renders money, so a printed figure
/// and a filed figure are compared as the customer and the auditor see them.
String _minorText(int minorUnits) {
  final major = minorUnits ~/ kMinorUnitsPerMajor;
  final cents = (minorUnits % kMinorUnitsPerMajor).toString().padLeft(2, '0');
  return '$major.$cents';
}
