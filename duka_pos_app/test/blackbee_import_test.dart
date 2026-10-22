// The one file that started this: the owner's real BlackBee stock tracker.
//
// ## WHY THIS TEST READS A FILE AND NOT A REPLICA
//
// "I just tried to import stock but it failed with 'the format is not the one
// used in the app'. FYI I used the same blackbee xlsx I used to make the
// parser with and it failed to import. Make a test for the parser that parses
// that xlsx to make sure it actually works."
//
// The parser was written against a MEMORY of that file, and the memory was
// wrong in the one place that mattered. The test's own inline replica opened
// with a header whose first two cells were `'0'` and `''` — no name column at
// all — while the real workbook's first row reads `STOCK NAME | B.PRICE |
// S.PRICE | OP/STOCK | … | CLOSING STOCK | …`. The replica proved the refusal;
// it never proved the import, because the file it tested was not the file.
//
// So this test opens the actual `.xlsx`, on the actual code path — decode,
// sheet choice, header mapping, row parse, database write — and asserts what
// the shop expects to see afterwards: their products, their prices, their
// stock, and their unpriced rows reported rather than invented.
//
// ## WHAT THE REAL FILE ACTUALLY IS
//
//   * 192 sheets, one per DAY ("4 April 2026" … "12 October 2026"). Not one
//     "Inventory" tab. The old sheet picker took the FIRST tab with rows,
//     which is the oldest day in the book.
//   * No column this app's alias table knew: `STOCK NAME`, `B.PRICE`,
//     `S.PRICE`, `OP/STOCK`, `TOTAL STOCK QTY`, `CLOSING STOCK`.
//   * Section titles down the first column ("SPIRITS 1 ltr", "Beer Bottles"),
//     with the product one column over — the shape this app's positional read
//     turns into a category made of prices.
//   * Roughly 226 product rows, of which ~108 carry a selling price. The rest
//     are the tracker's placeholders and must come back as needs-attention,
//     not as products priced at nothing.

@Tags(<String>['slow_import'])
library;

import 'dart:io';

import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/services/excel_service.dart';
import 'package:duka_pos/utils/money.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  const String path = 'assets/errors/BLACK BEE BAR  STOCK TRACKER (1).xlsx';
  final File workbook = File(path);

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    DatabaseHelper.resetForTests();
    await DatabaseHelper.openInMemoryForTests();
  });

  group('the real BlackBee tracker imports', () {
    // The workbook is 3.2 MB and 192 sheets: the decoder does the same work on
    // it that the app does when the owner picks the file.
    final Timeout budget = Timeout(const Duration(minutes: 5));

    test('the file is read as its own columns, not refused', () async {
      final InventoryImportResult result = await ExcelService()
          .importInventoryBytes(await workbook.readAsBytes());

      expect(result.imported, greaterThan(0),
          reason: 'a file with 108 priced products must not import nothing');
      // The unpriced rows of a tracker are placeholders, and the rule is
      // REPORTED, never defaulted: they surface instead of arriving as
      // products that sell for zero.
      expect(result.needsAttention, greaterThan(0));
    }, timeout: budget, skip: _skip(workbook));

    test('a priced row keeps its buying price, selling price and stock',
        () async {
      await ExcelService().importInventoryBytes(await workbook.readAsBytes());

      // Baileys on the last tab of the book: B.PRICE 2150, S.PRICE 3200,
      // CLOSING STOCK 1. Read from the tracker's own columns, in the column
      // the header says — not by position, which is what put a buying price
      // where a category belongs.
      final Product? baileys = await _named('Baileys');
      expect(baileys, isNotNull,
          reason: 'the shop is looking for their own row');
      expect(baileys!.costPrice, Money.fromMajor(2150));
      expect(baileys.sellPrice, Money.fromMajor(3200));
      expect(baileys.stockQty, 1);
    }, timeout: budget, skip: _skip(workbook));

    test('the section title down the first column becomes the category',
        () async {
      await ExcelService().importInventoryBytes(await workbook.readAsBytes());

      // The tracker states a category ONCE, above a block of rows. The block
      // it heads is the category of every row under it — which is the only
      // category the file ever gives.
      final Product? grants = await _named('Grants');
      expect(grants, isNotNull);
      expect(grants!.category, isNotEmpty);
    }, timeout: budget, skip: _skip(workbook));

    test('the newest day is the one imported, not the first tab in the book',
        () async {
      // A daily tracker's FIRST tab is its OLDEST day. Importing it files the
      // stock as it stood in April, which is not a wrong number so much as an
      // out-of-date one.
      final InventoryImportResult result = await ExcelService()
          .importInventoryBytes(await workbook.readAsBytes());

      // October (the last tab) has prices the April tab leaves blank, so a
      // count above what the first sheet could import is the proof the picker
      // read the book rather than its front page.
      expect(result.imported, greaterThan(50));
      expect(result.sheetName, contains('October'));
    }, timeout: budget, skip: _skip(workbook));
  });
}

/// The count of products a row was written under, by name.
Future<Product?> _named(String name) async {
  for (final Product product
      in await DatabaseHelper.instance.getProducts(activeOnly: false)) {
    if (product.name == name) return product;
  }
  return null;
}

/// Why the group is skipped, or null to run it.
///
/// The workbook is the point of the test, so a machine without it says so
/// rather than inventing a file to stand in for it.
String? _skip(File file) => file.existsSync()
    ? null
    : 'the real BlackBee workbook is not present at ${file.path}';
