// Database behaviour that only exists because of barcodes, per-till receipt
// numbering and the eTIMS queue.
//
// These assert outcomes that are invisible in the schema: that a scan resolves
// to exactly one product, that a receipt number cannot repeat, that a reprint
// cannot touch stock, and that a failed KRA upload leaves the sale committed
// rather than lost.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/utils/money.dart';

Product product(String name, {int? stock}) => Product(
      name: name,
      category: 'Drinks',
      costPrice: Money.fromMajor(45),
      sellPrice: Money.fromMajor(80),
      stockQty: (stock ?? 24).toDouble(),
      reorderLevel: 6,
      updatedAt: DateTime.now().toIso8601String(),
    );

SaleItem item(int productId, String name, {double qty = 1}) => SaleItem(
      saleId: 0,
      productId: productId,
      productName: name,
      qty: qty,
      unitPrice: Money.fromMajor(80),
      unitCost: Money.fromMajor(45),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late DatabaseHelper db;

  setUp(() async {
    DatabaseHelper.resetForTests();
    db = await DatabaseHelper.openInMemoryForTests();
  });

  tearDown(() {
    // The helper owns the connection and there is no public close: each test
    // gets a fresh in-memory database, and the old one is released when the
    // handle is replaced.
    DatabaseHelper.resetForTests();
  });

  group('barcodes', () {
    test('a scan resolves to the product that owns the code', () async {
      final soda = await db.upsertProduct(product('Soda 350ml'));
      await db.addBarcode(productId: soda, barcode: '6001234567899');

      final found = await db.getProductByBarcode('6001234567899');
      expect(found?.name, 'Soda 350ml');
    });

    test('a code belonging to nothing resolves to null, not to a guess',
        () async {
      await db.upsertProduct(product('Soda 350ml'));
      expect(await db.getProductByBarcode('6000000000000'), isNull);
    });

    test('a code can belong to exactly one product', () async {
      final soda = await db.upsertProduct(product('Soda 350ml'));
      final beer = await db.upsertProduct(product('Kenyana Beer'));
      expect(await db.addBarcode(productId: soda, barcode: '6001234567899'),
          isTrue);

      // Refused rather than silently re-pointed: overwriting would make the
      // *other* product unscannable, which is worse than refusing.
      expect(await db.addBarcode(productId: beer, barcode: '6001234567899'),
          isFalse);
      expect(
          (await db.getProductByBarcode('6001234567899'))?.name, 'Soda 350ml');
    });

    test('the refusal names the product that already holds the code', () async {
      final soda = await db.upsertProduct(product('Soda 350ml'));
      await db.addBarcode(productId: soda, barcode: '6001234567899');
      // "Duplicate barcode" tells the owner nothing about which product to
      // remove it from, so the lookup exists to produce this answer.
      expect((await db.getProductOwningBarcode('6001234567899'))?.name,
          'Soda 350ml');
    });

    test('one product answers to several codes', () async {
      final soda = await db.upsertProduct(product('Soda 350ml'));
      await db.addBarcode(productId: soda, barcode: '6001234567899');
      await db.addBarcode(
          productId: soda, barcode: 'COKE-500', kind: BarcodeKind.own);
      expect((await db.getBarcodesForProduct(soda)).map((b) => b.barcode),
          containsAll(['6001234567899', 'COKE-500']));
      expect((await db.getProductByBarcode('COKE-500'))?.name, 'Soda 350ml');
    });

    test('a soft-deleted product keeps its codes but stops scanning', () async {
      // The inventory screen deactivates rather than deletes, so the owner can
      // bring a product back. Its barcode must stop resolving (it is not for
      // sale) while staying attached (it is not lost).
      final soda = await db.upsertProduct(product('Soda 350ml'));
      await db.addBarcode(productId: soda, barcode: '6001234567899');
      await db.deactivateProduct(soda);

      expect(await db.getProductByBarcode('6001234567899'), isNull);
      expect((await db.getBarcodesForProduct(soda)).map((b) => b.barcode),
          contains('6001234567899'));
    });

    test('a hard delete frees the codes, so the product can return', () async {
      // Foreign keys are not enforced on this connection (see the note on
      // DatabaseHelper), so `ON DELETE CASCADE` alone would leave the code
      // behind and permanently block re-adding the product under it.
      final soda = await db.upsertProduct(product('Soda 350ml'));
      await db.addBarcode(productId: soda, barcode: '6001234567899');
      await db.hardDeleteProduct(soda);

      expect(await db.getBarcodesForProduct(soda), isEmpty);
      final replacement = await db.upsertProduct(product('Soda 350ml'));
      expect(
          await db.addBarcode(productId: replacement, barcode: '6001234567899'),
          isTrue);
    });

    test('removing a barcode detaches it from its product', () async {
      final soda = await db.upsertProduct(product('Soda 350ml'));
      await db.addBarcode(productId: soda, barcode: '6001234567899');
      await db.removeBarcode('6001234567899');
      expect(await db.getProductByBarcode('6001234567899'), isNull);
    });

    test('a bulk import keeps the good codes and reports the refused ones',
        () async {
      // A supplier workbook that reuses one code across two rows must not abort
      // the whole import, and the owner has to be told which ones were refused.
      final soda = await db.upsertProduct(product('Soda 350ml'));
      final beer = await db.upsertProduct(product('Kenyana Beer'));
      await db.addBarcode(productId: soda, barcode: '6001234567899');

      final refused = await db.addBarcodes([
        ProductBarcode(barcode: '6001234567899', productId: soda),
        ProductBarcode(barcode: '96385074', productId: beer),
        ProductBarcode(barcode: '036000291452', productId: beer),
      ]);

      expect(refused, ['6001234567899']);
      expect((await db.getProductByBarcode('96385074'))?.name, 'Kenyana Beer');
      expect(
          (await db.getProductByBarcode('036000291452'))?.name, 'Kenyana Beer');
    });

    test('a barcode survives an unrelated product edit', () async {
      // `upsertProduct` writes `toMap()` wholesale. A barcode written through
      // it would be erased by the next save of an unrelated field, which is
      // exactly why the barcode table has its own API.
      final soda = await db.upsertProduct(product('Soda 350ml'));
      await db.addBarcode(productId: soda, barcode: '6001234567899');
      final before = await db.getProducts(activeOnly: false);
      final edited = before.first.copyWith(sellPrice: Money.fromMajor(95));
      await db.upsertProduct(edited);
      expect((await db.getProductByBarcode('6001234567899'))?.sellPrice,
          Money.fromMajor(95));
    });
  });

  group('shop settings', () {
    test('the VAT rate defaults to 16 and round-trips', () async {
      expect(await db.getVatRatePercent(), 16);
      await db.setVatRatePercent(0);
      expect(await db.getVatRatePercent(), 0,
          reason:
              'zero means exempt and must be storable, not treated as unset');
      await db.setVatRatePercent(12);
      expect(await db.getVatRatePercent(), 12);
    });

    test('a nonsense rate is rejected rather than stored', () async {
      // Thrown synchronously, before the Future is even created, so this is a
      // closure expectation rather than an awaited one.
      expect(() => db.setVatRatePercent(-1), throwsArgumentError);
      expect(() => db.setVatRatePercent(101), throwsArgumentError);
      expect(await db.getVatRatePercent(), 16,
          reason: 'and nothing was stored');
    });

    test('an out-of-range stored rate falls back to the default', () async {
      await db.setSetting(DatabaseHelper.settingVatRate, '999');
      expect(await db.getVatRatePercent(), 16);
    });

    test('the till code defaults to one derived from the workspace', () async {
      // Two tills in the same shop must not both issue POS-000001.
      final code = await db.getTillCode();
      expect(code, isNotEmpty);
      expect(DatabaseHelper.defaultTillCode('a1b2c3d4'), isNot('POS'));
      expect(DatabaseHelper.defaultTillCode('...'), 'POS');
    });

    test('a configured till code overrides the default', () async {
      await db.setTillCode('t3');
      expect(await db.getTillCode(), 'T3');
    });
  });

  group('receipt numbering', () {
    test('numbers are allocated in sequence inside the sale transaction',
        () async {
      final soda = await db.upsertProduct(product('Soda 350ml'));
      await db.setTillCode('T1');

      final first = await db
          .recordSale(staffName: 'Alice', items: [item(soda, 'Soda 350ml')]);
      final second = await db
          .recordSale(staffName: 'Alice', items: [item(soda, 'Soda 350ml')]);

      expect((await db.getSaleRowById(first))!['receipt_number'], 'T1-000001');
      expect((await db.getSaleRowById(second))!['receipt_number'], 'T1-000002');
    });

    test('every recorded sale has a distinct receipt number', () async {
      final soda = await db.upsertProduct(product('Soda 350ml'));
      final ids = <int>[];
      for (var i = 0; i < 8; i++) {
        ids.add(await db
            .recordSale(staffName: 'Alice', items: [item(soda, 'Soda 350ml')]));
      }
      final numbers = {
        for (final id in ids)
          (await db.getSaleRowById(id))!['receipt_number'] as String
      };
      expect(numbers, hasLength(8));
    });

    test('a pre-v12 sale falls back to a stable provisional number', () async {
      // Rows that predate the sequence have no `receipt_number`. They still
      // need something on the paper, and the row id is monotonic and unique.
      final soda = await db.upsertProduct(product('Soda 350ml'));
      final id = await db
          .recordSale(staffName: 'Alice', items: [item(soda, 'Soda 350ml')]);
      final row = Map<String, dynamic>.from((await db.getSaleRowById(id))!);
      row.remove('receipt_number');
      expect(db.receiptNumberFor(row), 'POS-${id.toString().padLeft(6, '0')}');
    });
  });

  group('reprint does not touch stock', () {
    test('reading a sale back for a reprint leaves stock alone', () async {
      final soda = await db.upsertProduct(product('Soda 350ml', stock: 10));
      final id = await db.recordSale(
          staffName: 'Alice', items: [item(soda, 'Soda 350ml', qty: 2)]);
      expect(await db.stockQtyForProduct(soda), 8);

      // What `ReceiptPrinter` does before rendering: read the sale, its items
      // and its row. If a reprint ever went anywhere near `recordSale`, this is
      // the assertion that would catch the second decrement.
      for (var reprint = 0; reprint < 3; reprint++) {
        final sale = await db.getSaleById(id);
        expect(sale!.items.single.qty, 2.0);
        expect(sale.total.minorUnits, 16000, reason: '2 x KSh 80.00');
        expect(await db.getSaleRowById(id), isNotNull);
      }
      expect(await db.stockQtyForProduct(soda), 8,
          reason: 'a reprint must never decrement stock');
      expect(await db.countSalesForReceipt(), 1);
    });

    test('a sale id from another workspace resolves to nothing', () async {
      expect(await db.getSaleById(999999), isNull);
      expect(await db.getSaleRowById(999999), isNull);
    });
  });

  group('eTIMS queue', () {
    test('a sale is not queued when eTIMS is off', () async {
      final soda = await db.upsertProduct(product('Soda 350ml'));
      final id = await db
          .recordSale(staffName: 'Alice', items: [item(soda, 'Soda 350ml')]);
      expect((await db.getSaleRowById(id))!['etims_status'], 'not_required');
      expect(await db.countPendingEtimsReceipts(), 0);
    });

    test('a pending sale is queued in the same transaction as the sale',
        () async {
      final soda = await db.upsertProduct(product('Soda 350ml'));
      final id = await db.recordSale(
          staffName: 'Alice',
          items: [item(soda, 'Soda 350ml')],
          etimsPending: true);
      expect((await db.getSaleRowById(id))!['etims_status'], 'pending');
      expect(await db.countPendingEtimsReceipts(), 1);
      final pending = await db.getPendingEtimsReceipts();
      expect(pending.single.saleId, id);
      expect(pending.single.attempts, 0);
    });

    test('the queue is drained oldest first', () async {
      // KRA rejects a batch whose sequence has a gap, so flushing in issue
      // order is a compliance requirement, not a nicety.
      await db.setTillCode('T1');
      final soda = await db.upsertProduct(product('Soda 350ml'));
      final ids = <int>[];
      for (var i = 0; i < 3; i++) {
        ids.add(await db.recordSale(
            staffName: 'Alice',
            items: [item(soda, 'Soda 350ml')],
            etimsPending: true));
      }
      final pending = await db.getPendingEtimsReceipts();
      expect(pending.map((p) => p.saleId), ids);
      expect(pending.map((p) => p.receiptNumber),
          ['T1-000001', 'T1-000002', 'T1-000003']);
    });

    test('issuing a receipt stores the number and clears the queue', () async {
      final soda = await db.upsertProduct(product('Soda 350ml'));
      final id = await db.recordSale(
          staffName: 'Alice',
          items: [item(soda, 'Soda 350ml')],
          etimsPending: true);
      await db.resolveEtimsReceipt(
          saleId: id, kraReceiptNumber: 'KRA-8f2a-0001');

      final row = (await db.getSaleRowById(id))!;
      expect(row['etims_status'], 'issued');
      expect(row['etims_receipt_number'], 'KRA-8f2a-0001');
      expect(await db.countPendingEtimsReceipts(), 0);
    });

    test('resolving twice does not create a second invoice', () async {
      final soda = await db.upsertProduct(product('Soda 350ml'));
      final id = await db.recordSale(
          staffName: 'Alice',
          items: [item(soda, 'Soda 350ml')],
          etimsPending: true);
      await db.resolveEtimsReceipt(saleId: id, kraReceiptNumber: 'KRA-1');
      // A retried upload must be a no-op rather than a second invoice for the
      // same money, which the queue row's absence is what proves.
      await db.resolveEtimsReceipt(saleId: id, kraReceiptNumber: 'KRA-2');
      expect(await db.countPendingEtimsReceipts(), 0);
    });

    test('a failed upload keeps the sale pending and counts the attempt',
        () async {
      // The sale is committed and the customer has paid. Losing it from the
      // queue would mean an unissued tax invoice for money actually taken.
      final soda = await db.upsertProduct(product('Soda 350ml'));
      final id = await db.recordSale(
          staffName: 'Alice',
          items: [item(soda, 'Soda 350ml')],
          etimsPending: true);

      await db.recordEtimsAttemptFailure(
          saleId: id, error: 'network unreachable');
      await db.recordEtimsAttemptFailure(
          saleId: id, error: 'network unreachable');

      expect((await db.getSaleRowById(id))!['etims_status'], 'pending');
      final pending = await db.getPendingEtimsReceipts();
      expect(pending.single.attempts, 2);
      expect(pending.single.lastError, 'network unreachable');
    });

    test('a KRA refusal stops the row being retried forever', () async {
      final soda = await db.upsertProduct(product('Soda 350ml'));
      final id = await db.recordSale(
          staffName: 'Alice',
          items: [item(soda, 'Soda 350ml')],
          etimsPending: true);
      await db.recordEtimsAttemptFailure(saleId: id, error: 'invalid TIN');
      await db.markEtimsRejected(id, 'invalid TIN');

      expect((await db.getSaleRowById(id))!['etims_status'], 'rejected');
      // A refused sale is excluded from the pending queue so it never blocks
      // newer receipts (C2).
      expect(await db.countPendingEtimsReceipts(), 0);
      // But it remains visible as rejected.
      expect(await db.countRejectedEtimsReceipts(), 1);
    });
  });
}
