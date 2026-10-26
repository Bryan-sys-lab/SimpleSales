// The supplier, added from the delivery — and the draft that was killed.
//
// ## WHAT IS PINNED
//
// "…and lets users add their supplier name and number for auto restocks
// later." The capture point is the delivery itself: the person knows who
// brought it while it is on the counter. So:
//
//   * Add a supplier FROM the receive sheet — name and phone — and the new
//     supplier is on the list, selected, before the delivery posts;
//   * the number is canonical (+254…) when it reaches the database — the
//     auto-restock messages later must dial it;
//   * a number that is not a Kenyan number is refused NEXT TO THE FIELD;
//   * a session the app killed comes back as a draft, and discarding it asks.

import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/screens/deliveries_history_sheet.dart';
import 'package:duka_pos/screens/receive_stock_sheet.dart';
import 'package:duka_pos/utils/money.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/harness.dart';

/// Drives taps whose handlers do real database I/O, in real time.
///
/// A widget test runs in fake async, and a sqflite-ffi write answers on a
/// real isolate — a pumpAndSettle never sees it. `runAsync` lets the real
/// async complete; the frames are pumped after, once.
Future<void> inRealTime(WidgetTester tester, Future<void> Function() body) =>
    tester.runAsync(body);

/// Waits for the frames the real-time interactions scheduled.
Future<void> settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 120));
  await tester.pumpAndSettle();
}

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

  final Product product = Product(
    id: 1,
    name: 'Tusker',
    category: 'Beer',
    costPrice: Money.fromMajor(60),
    sellPrice: Money.fromMajor(100),
    stockQty: 10,
    reorderLevel: 2,
    bottleMl: 500,
    updatedAt: DateTime.now().toIso8601String(),
  );

  /// Opens the sheet through ITS OWN entry point, so a pop value is readable.
  ///
  /// [result] holds what the sheet popped (null plain-dismiss, [0] a
  /// discarded draft, an id a posted delivery).
  Future<void> openThroughEntry(
    WidgetTester tester, {
    ValueNotifier<Object?>? result,
    ReceiveDraftSnapshot? draft,
  }) async {
    // The suppliers are read in real time (a background isolate serve), so
    // the sheet opens on data already in hand — the same discipline every
    // sheet in this app is opened with.
    List<Supplier> suppliers = <Supplier>[];
    await tester.runAsync(() async {
      suppliers = await DatabaseHelper.instance.getSuppliers();
    });
    await tester.pumpApp(
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => Center(
            child: FilledButton(
              onPressed: () async {
                final int? popped = await showReceiveStockSheet(
                  context,
                  products: <Product>[product],
                  suppliers: suppliers,
                  lastCostFor: (_) async => null,
                  staffName: 'Amina',
                  staffId: 7,
                  draft: draft,
                );
                result?.value = popped;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  group('adding a supplier from the delivery', () {
    testWidgets('a name and a number become a supplier, selected', (
      WidgetTester tester,
    ) async {
      await openThroughEntry(tester);

      await tester.tap(find.byTooltip('Add a supplier'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Supplier name'),
          'Kentex Distributors');
      final Finder phoneField =
          find.widgetWithText(TextFormField, 'Phone number').last;
      await tester.enterText(phoneField, '0712 345 678');
      await inRealTime(tester, () async {
        await tester.tap(find.text('Save supplier'), warnIfMissed: false);
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await settle(tester);

      // The sheet is back on the delivery, with the supplier named in the
      // picker — and selected, because the supplier OF THIS delivery is the
      // one being named.
      expect(find.text('Kentex Distributors'), findsOneWidget);

      // And the number reached the database in its canonical form: what the
      // auto-restock messages will dial later.
      final List<Supplier> suppliers = (await tester.runAsync(
        () => DatabaseHelper.instance.getSuppliers(),
      ))!;
      expect(suppliers, isNotEmpty);
      expect(suppliers.first.name, 'Kentex Distributors');
      expect(suppliers.first.phone, '+254712345678');
    });

    testWidgets('a number that is not Kenyan is refused by the field', (
      WidgetTester tester,
    ) async {
      await openThroughEntry(tester);

      await tester.tap(find.byTooltip('Add a supplier'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Supplier name'), 'Foreign Ltd');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Phone number').last,
          '+441632960437');
      await tester.pumpAndSettle();

      expect(find.textContaining('not a Kenyan number'), findsOneWidget);
    });

    testWidgets('it fits a small phone at twice the text size', (
      WidgetTester tester,
    ) async {
      tester.useDevice(Device.compact);
      await openThroughEntry(tester);
      tester.expectNoOverflow('the add supplier sheet');
    });
  });

  group('a killed session comes back as a draft', () {
    testWidgets('the lines are resumed and discarding asks first', (
      WidgetTester tester,
    ) async {
      final ValueNotifier<Object?> result = ValueNotifier<Object?>(null);
      // A draft from the person's last visit: a supplier reference and a line.
      await tester.runAsync(() async {
        // The supplier it names is on the list.
        await DatabaseHelper.instance.addSupplier(name: 'Kentex');
        await DatabaseHelper.instance.saveReceiveDraft(7, <String, Object?>{
          'supplier_id': 1,
          'supplier_ref': 'INV-14',
          'lines': <Object?>[
            <String, Object?>{
              'product_id': 1,
              'product_name': 'Tusker',
              'qty': 6,
              'unit_cost_minor': 9000,
            },
          ],
        });
      });
      await openThroughEntry(
        tester,
        result: result,
        draft: ReceiveDraftSnapshot.fromJson(<String, dynamic>{
          'supplier_id': 1,
          'supplier_ref': 'INV-14',
          'lines': <Object?>[
            <String, Object?>{
              'product_id': 1,
              'product_name': 'Tusker',
              'qty': 6,
              'unit_cost_minor': 9000,
            },
          ],
        }),
      );

      // The draft: one line, its cost, the supplier picked.
      expect(find.text('Tusker'), findsOneWidget);
      expect(find.text('KSh 540'), findsOneWidget);
      expect(find.text('Kentex Distributors'), findsNothing); // none saved yet
      expect(find.textContaining('half-finished'), findsOneWidget);

      // Discarding asks. Saying NO keeps the draft.
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        await tester.runAsync(
          () => DatabaseHelper.instance.getReceiveDraft(7),
        ),
        isNotNull,
      );
      expect(find.text('Tusker'), findsOneWidget);

      // Discarding, for real: the sheet closes with the discarded signal.
      // The dialog is BROUGHT UP between pumps, and its button pressed while
      // real time runs the write.
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      await inRealTime(tester, () async {
        final Finder dialogConfirm = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Discard it'),
        );
        await tester.tap(dialogConfirm);
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await settle(tester);

      expect(result.value, 0);
      // The trailing write (the draft's row) is real I/O: real time knows it.
      await inRealTime(tester, () async {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      expect(
        await tester.runAsync(
          () => DatabaseHelper.instance.getReceiveDraft(7),
        ),
        isNull,
      );
    });
  });

  group('the deliveries history', () {
    testWidgets('a posted delivery shows its supplier, and the owner can '
        'void it', (WidgetTester tester) async {
      await tester.runAsync(() async {
        final int supplierId =
            await DatabaseHelper.instance.addSupplier(name: 'Kentex');
        final int productId =
            await DatabaseHelper.instance.upsertProduct(Product(
          name: 'Tusker',
          category: 'Beer',
          costPrice: Money.fromMajor(60),
          sellPrice: Money.fromMajor(100),
          stockQty: 10,
          reorderLevel: 2,
          bottleMl: 500,
          updatedAt: DateTime.now().toIso8601String(),
        ));
        await DatabaseHelper.instance.postStockReceipt(
          lines: <StockReceiptLine>[
            StockReceiptLine(
              productId: productId,
              productName: 'Tusker',
              qty: 12,
              unitCost: Money.fromMajor(90),
            ),
          ],
          supplierId: supplierId,
          staffName: 'Amina',
          staffId: 7,
        );
      });
      List<StockReceipt> receipts = <StockReceipt>[];
      Map<int, String> supplierNames = <int, String>{};
      await tester.runAsync(() async {
        receipts = await DatabaseHelper.instance.getStockReceipts();
        supplierNames = <int, String>{
          for (final Supplier supplier
              in await DatabaseHelper.instance.getSuppliers())
            if (supplier.id != null) supplier.id!: supplier.name,
        };
      });
      await tester.pumpApp(
        home: Scaffold(
          body: DeliveriesHistorySheet(
            receipts: receipts,
            supplierNames: supplierNames,
            canVoid: true,
            staffName: 'Owner',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Kentex'), findsOneWidget);
      expect(find.text('KSh 1,080'), findsOneWidget);

      // The void: expand the row, press, confirm.
      await tester.tap(find.text('Kentex'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Void delivery'));
      await tester.pumpAndSettle();
      await inRealTime(tester, () async {
        // The confirm lives in the dialog; the row's own button is behind
        // the barrier and must not be tapped "again" by accident.
        await tester.tap(find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Void delivery'),
        ));
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await settle(tester);

      // The stock went back off the shelf, the posting is voided in history.
      final List<Product> products = (await tester.runAsync(
        () => DatabaseHelper.instance.getProducts(),
      ))!;
      final Product after =
          products.firstWhere((Product p) => p.name == 'Tusker');
      expect(after.stockQty, 10);
      final StockReceipt receipt = (await tester.runAsync(
        () => DatabaseHelper.instance.getStockReceipts(),
      ))!.single;
      expect(receipt.status, 'voided');
    });
  });
}
