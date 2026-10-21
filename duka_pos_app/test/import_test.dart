// Imports that never lose a row, never throw on one, and never report a
// number the database does not agree with.
//
// Each test here is a bug that shipped. The workbook drives real .xlsx bytes
// through the real importer and then reads the database back, because the bugs
// being pinned down — the sheet found by position, the unconditional skip(1),
// the count that reported parses as imports — live in the code between the file
// and the database and cannot be reproduced any other way.

import 'package:excel/excel.dart' as xl;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/services/excel_service.dart';
import 'package:duka_pos/services/inventory_importer.dart';
import 'package:duka_pos/services/import_row_parser.dart';
import 'package:duka_pos/utils/money.dart';
import 'package:duka_pos/utils/units.dart';

/// The Inventory header this app exports. Column order matters for a
/// header-less file, so the tests build from the model's own list rather than
/// hard-coding twelve strings that could drift.
List<dynamic> get _inventoryHeader => Product.sheetHeaders;

/// A data row in export order.
List<dynamic> _row({
  Object? id,
  required String name,
  String category = 'General',
  Object cost = 60,
  Object sell = 100,
  Object stock = 24,
  Object reorder = 6,
  Object bottle = 750,
  Object? half = '',
  Object? quarter = '',
  Object? barcode = '',
  String unit = 'each',
}) =>
    [
      id,
      name,
      category,
      cost,
      sell,
      stock,
      reorder,
      '',
      bottle,
      half,
      quarter,
      barcode,
      unit,
    ];

xl.CellValue? _cell(dynamic value) {
  if (value == null) return null;
  if (value is int) return xl.IntCellValue(value);
  if (value is double) return xl.DoubleCellValue(value);
  if (value is num) return xl.DoubleCellValue(value.toDouble());
  return xl.TextCellValue(value.toString());
}

/// Real .xlsx bytes.
///
/// [tabs] is name → rows, each row already including its own header row if it
/// has one. Order is preserved, so a test can put `Sales` before `Inventory`.
List<int> _workbook(Map<String, List<List<dynamic>>> tabs) {
  final book = xl.Excel.createExcel();
  if (book.tables.containsKey('Sheet1')) book.delete('Sheet1');
  for (final entry in tabs.entries) {
    final sheet = book[entry.key];
    for (final row in entry.value) {
      sheet.appendRow(row.map(_cell).toList());
    }
  }
  return book.encode()!;
}

/// The shape of the workbook that shipped this bug.
///
/// Products in column B — where our own export puts the name — so the names
/// read correctly and nothing about the file LOOKS wrong. Its buying price sits
/// one column over in C, which is where our export writes out the category as
/// words. That shifted column is the whole bug: read positionally, a buying
/// price becomes a category, a selling price becomes a cost, and an opening
/// stock becomes a selling price.
List<List<dynamic>> _tracker({List<dynamic>? header, int products = 6}) {
  final rows = <List<dynamic>>[
    header ??
        <dynamic>[
          '0',
          '',
          'B.PRICE',
          'S.PRICE',
          'OP/STOCK',
          'NEW STOCK',
          'TOTAL STOCK QTY',
          'TOTAL STOCK VALUE',
          'SOLD STOCK',
          'CLOSING STOCK',
          'SALES AMOUNT',
          'PROFIT',
        ],
    <dynamic>['SPIRITS 1 ltr'],
  ];
  for (var i = 0; i < products; i++) {
    rows.add(<dynamic>[
      '',
      'Bond ${i + 7}',
      90 + i,
      200 + i,
      i + 1,
      i + 4,
      5 + i,
      450 + i,
      3 + i,
      4 + i,
      600 + i,
      200 + i,
    ]);
  }
  return rows;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late DatabaseHelper db;

  setUp(() async {
    DatabaseHelper.resetForTests();
    db = await DatabaseHelper.openInMemoryForTests();
  });

  tearDown(() => DatabaseHelper.resetForTests());

  group('the import says what it is doing', () {
    // The owner watching an import needs to know it is WORKING, and the
    // import is the only thing the app does with no button to press while it
    // happens. A silent import reads as a broken app, and the answer to that
    // is the owner pressing the button again.
    test('it reports every stage, and finishes', () async {
      final List<ImportStage> stages = <ImportStage>[];

      final result = await ExcelService().importInventoryBytes(
        _workbook(<String, List<List<dynamic>>>{
          'Inventory': <List<dynamic>>[
            _inventoryHeader,
            _row(id: 1, name: 'Kenya Lager', category: 'BEER'),
            _row(id: 2, name: 'Maziwa', category: 'Milk & Dairy'),
          ],
        }),
        onProgress: (ImportProgress progress) => stages.add(progress.stage),
      );

      expect(result.imported, greaterThan(0));
      expect(stages, contains(ImportStage.reading));
      expect(stages, contains(ImportStage.parsing));
      expect(stages, contains(ImportStage.writing));
      expect(stages.last, ImportStage.done);
    });

    test('it reports the same result with and without a listener', () async {
      final List<ImportStage> stages = <ImportStage>[];
      final bytes = _workbook(<String, List<List<dynamic>>>{
        'Inventory': <List<dynamic>>[
          _inventoryHeader,
          _row(id: 1, name: 'Kenya Lager', category: 'BEER'),
          _row(id: 2, name: 'Maziwa', category: 'Milk & Dairy'),
        ],
      });

      final withProgress = await ExcelService().importInventoryBytes(
        bytes,
        onProgress: (ImportProgress progress) => stages.add(progress.stage),
      );

      // A fresh catalogue, so the second import CREATES what the first one
      // created rather than updating it — otherwise the comparison would be
      // measuring the first import, not the listener.
      DatabaseHelper.resetForTests();
      db = await DatabaseHelper.openInMemoryForTests();

      final without = await ExcelService().importInventoryBytes(bytes);

      expect(withProgress.imported, without.imported);
      expect(withProgress.created, without.created);
      expect(withProgress.updated, without.updated);
      expect(stages, isNotEmpty);
    });
  });

  Future<Product?> productNamed(String name) async {
    for (final product in await db.getProducts(activeOnly: false)) {
      if (product.name == name) return product;
    }
    return null;
  }

  group('a bad row never aborts the file', () {
    // One mistyped price used to throw a FormatException out of Product.fromRow
    // and take all forty products with it. The owner lost the whole workbook to
    // one cell in row two.
    test('the rows after a bad one still import', () async {
      final bytes = _workbook({
        'Inventory': [
          _inventoryHeader,
          _row(id: 1, name: 'Kenya Lager', category: 'BEER'),
          _row(
            id: 2,
            name: 'Broken Row',
            category: 'Beer',
            cost: 'not a price',
          ),
          _row(id: 3, name: 'Maziwa', category: 'Milk & Dairy'),
        ],
      });

      final result = await ExcelService().importInventoryBytes(bytes);

      expect(result.imported, 2);
      expect(await productNamed('Kenya Lager'), isNotNull);
      expect(await productNamed('Maziwa'), isNotNull);
      expect(await productNamed('Broken Row'), isNull);
    });

    test('the dropped row lands on the needs-attention list with its values',
        () async {
      final bytes = _workbook({
        'Inventory': [
          _inventoryHeader,
          _row(id: 1, name: 'Kenya Lager'),
          _row(id: 2, name: 'Broken Row', cost: 'ask supplier'),
        ],
      });

      final result = await ExcelService().importInventoryBytes(bytes);

      expect(result.needsAttention, 1);
      final open = await db.getImportProblems();
      expect(open, hasLength(1));
      expect(open.single.rawName, 'Broken Row');
      expect(open.single.rowNumber, 3, reason: '1-based, header included');
      expect(open.single.sheetName, 'Inventory');
      expect(open.single.problem, contains('ask supplier'));
      expect(open.single.rawRow, contains('ask supplier'));
      expect(open.single.resolved, isFalse);
    });

    test('Product.fromRow returns null instead of throwing', () {
      // The editor and the old Sheets importer both call this, and a throw here
      // used to abort a whole import mid-file.
      expect(
        Product.fromRow(
          [7, 'x' * 200, 'Wine', '100', '200', '3', '1', '', '750', '', ''],
        ),
        isNull,
      );
    });
  });

  group('the reported count is the written count', () {
    // The old importer reported the number of rows it *parsed*. A row dropped
    // for an unusable barcode was counted as a success, so the owner's stock
    // count came out short with a report that said it was fine.
    test('imported equals the number of rows in the database', () async {
      final bytes = _workbook({
        'Inventory': [
          _inventoryHeader,
          _row(id: 1, name: 'Kenya Lager', barcode: '6001234567899'),
          // Too short to be a barcode: the product is still written, the code
          // is not attached, and the row is flagged.
          _row(id: 2, name: 'Short Code', barcode: '123'),
          // Rejected outright, so not written and not counted.
          _row(id: 3, name: 'No Cost', cost: ''),
          _row(id: 4, name: '   '),
          _row(id: 5, name: 'Soda 350ml', category: 'Soft Drinks'),
        ],
      });

      final result = await ExcelService().importInventoryBytes(bytes);
      final inDatabase = await db.getProducts(activeOnly: false);

      expect(result.imported, 3);
      expect(result.imported, inDatabase.length);
      expect(result.created, 3);
      expect(result.updated, 0);
      // Three rows the owner must look at: the bad code, the missing cost and
      // the missing name.
      expect(result.needsAttention, 3);
      expect(await db.countOpenImportProblems(), 3);
    });

    test('a second import of the same file counts updates, not creations',
        () async {
      final bytes = _workbook({
        'Inventory': [
          _inventoryHeader,
          _row(id: 1, name: 'Kenya Lager', sell: 100),
          _row(id: 2, name: 'Maziwa', category: 'Milk & Dairy'),
        ],
      });
      final first = await ExcelService().importInventoryBytes(bytes);
      expect(first.created, 2);
      expect(first.updated, 0);

      final second = await ExcelService().importInventoryBytes(bytes);
      expect(second.imported, 2);
      expect(second.created, 0, reason: 'both rows already existed');
      expect(second.updated, 2);
      expect(second.imported, second.created + second.updated);
      expect((await db.getProducts(activeOnly: false)).length, 2);
    });

    test('refused barcodes are named by the product that owns them', () async {
      final first = _workbook({
        'Inventory': [
          _inventoryHeader,
          _row(id: 1, name: 'Coke', barcode: '6001234567899')
        ],
      });
      await ExcelService().importInventoryBytes(first);

      final second = _workbook({
        'Inventory': [
          _inventoryHeader,
          _row(id: 2, name: 'Fanta', barcode: '6001234567899'),
        ],
      });
      final result = await ExcelService().importInventoryBytes(second);

      expect(result.refusedBarcodes['6001234567899'], 'Coke');
      expect(result.imported, 1, reason: 'the product itself still imports');
    });
  });

  group('volume units', () {
    // "750" in a tank and "750" in a bottle are different things, and reading a
    // tank as 750 millilitres is a stock error nobody sees until month end.
    test('litres, millilitres and bare numbers all convert', () async {
      final bytes = _workbook({
        'Inventory': [
          _inventoryHeader,
          _row(id: 1, name: 'Bare Millilitres', bottle: 750),
          _row(id: 2, name: 'Bare Litres', bottle: '0.75'),
          _row(id: 3, name: 'Explicit Litres', bottle: '1.5 L'),
          _row(id: 4, name: 'Explicit Millilitres', bottle: '500ml'),
          _row(id: 5, name: 'Decimal Litres', bottle: 0.75),
        ],
      });

      await ExcelService().importInventoryBytes(bytes);

      expect((await productNamed('Bare Millilitres'))!.bottleMl, 750);
      expect((await productNamed('Bare Litres'))!.bottleMl, 750);
      expect((await productNamed('Explicit Litres'))!.bottleMl, 1500);
      expect((await productNamed('Explicit Millilitres'))!.bottleMl, 500);
      expect((await productNamed('Decimal Litres'))!.bottleMl, 750);
    });

    test('a declared unit column overrides the bare-number guess', () async {
      // A 50-litre keg written as "50" must not become 50 millilitres.
      final bytes = _workbook({
        'Inventory': [
          _inventoryHeader,
          _row(id: 1, name: 'Keg', bottle: 50, unit: 'litre'),
          _row(id: 2, name: 'Syrup', bottle: 2, unit: 'litre'),
          _row(id: 3, name: 'Bottle', bottle: 750, unit: 'each'),
        ],
      });

      await ExcelService().importInventoryBytes(bytes);

      expect((await productNamed('Keg'))!.bottleMl, 50000);
      expect((await productNamed('Keg'))!.unit, ProductUnit.litre);
      expect((await productNamed('Syrup'))!.bottleMl, 2000);
      expect((await productNamed('Bottle'))!.unit, ProductUnit.each);
    });

    test('a missing size on a volumetric row is flagged, never guessed',
        () async {
      // Guessing 750ml for a tank is worse than asking.
      final bytes = _workbook({
        'Inventory': [
          _inventoryHeader,
          _row(id: 1, name: 'Unlabelled Keg', bottle: '', unit: 'litre'),
        ],
      });

      final result = await ExcelService().importInventoryBytes(bytes);

      expect(result.imported, 0);
      expect(result.needsAttention, 1);
      expect((await db.getImportProblems()).single.problem,
          contains('cannot be guessed'));
    });

    test('a missing size on a countable row is written and flagged', () async {
      final bytes = _workbook({
        'Inventory': [
          _inventoryHeader,
          _row(id: 1, name: 'Loaf', bottle: ''),
        ],
      });

      final result = await ExcelService().importInventoryBytes(bytes);

      expect(result.imported, 1);
      expect(result.needsAttention, 1);
      expect((await productNamed('Loaf'))!.bottleMl, 750);
    });

    test('an unreadable size is rejected rather than defaulted', () async {
      final parsed = ImportRowParser.parseProductRow(
        _row(name: 'Mystery Box', bottle: 'big'),
      );
      expect(parsed.product, isNull);
      expect(parsed.problem, contains('not a size the app understands'));
    });
  });

  group('categories', () {
    test('are normalised on the way in and added to the vocabulary', () async {
      final bytes = _workbook({
        'Inventory': [
          _inventoryHeader,
          _row(id: 1, name: 'Cola', category: '  soft   DRINKS '),
          _row(id: 2, name: 'Chips', category: 'snacks'),
          _row(id: 3, name: 'Soap', category: 'household'),
        ],
      });

      await ExcelService().importInventoryBytes(bytes);

      expect((await productNamed('Cola'))!.category, 'Soft Drinks');
      expect((await productNamed('Chips'))!.category, 'Snacks');
      final categories = await db.getCategories();
      expect(categories, contains('Soft Drinks'));
      expect(categories, contains('Snacks'));
      expect(categories, contains('Household'));
      expect(categories, isNot(contains('snacks')));
    });

    test('an empty category is inferred from the product name', () async {
      final bytes = _workbook({
        'Inventory': [
          _inventoryHeader,
          _row(id: 1, name: 'Tusker Lager 500ml', category: ''),
          _row(id: 2, name: 'Ken Stout', category: ''),
          _row(id: 3, name: 'Fresh Milk 1L', category: ''),
          _row(id: 4, name: 'Safi Water 1.5L', category: ''),
          _row(id: 5, name: 'Zebra Widget 5pc', category: ''),
        ],
      });

      await ExcelService().importInventoryBytes(bytes);

      expect((await productNamed('Tusker Lager 500ml'))!.category, 'Beer');
      expect((await productNamed('Ken Stout'))!.category, 'Beer');
      expect((await productNamed('Fresh Milk 1L'))!.category, 'Milk & Dairy');
      expect((await productNamed('Safi Water 1.5L'))!.category, 'Water');
      expect((await productNamed('Zebra Widget 5pc'))!.category,
          CategoryName.general);
    });

    test('the inference is one pure function', () {
      // Guessing that lives in two importers is how the Excel path files a
      // lager under Beer and the Sheets path files it under General, and neither
      // report looks wrong on its own.
      expect(
          ImportRowParser.inferCategoryFromName('Tusker Lager 500ml'), 'Beer');
      expect(ImportRowParser.inferCategoryFromName('Mala 1L'), 'Milk & Dairy');
      expect(ImportRowParser.inferCategoryFromName('Safi Water'), 'Water');
      expect(ImportRowParser.inferCategoryFromName('Sultani 300g'), 'Snacks');
      expect(ImportRowParser.inferCategoryFromName('Zebra Widget'), isNull);
      expect(ImportRowParser.inferCategoryFromName(''), isNull);
      // An explicit category is never overridden by inference.
      expect(ImportRowParser.resolveCategory('Wine', 'Tusker Lager'), 'Wine');
      expect(
          ImportRowParser.resolveCategory(
              '  wines  AND spirits ', 'Tusker Lager'),
          'Wines & Spirits');
      expect(ImportRowParser.resolveCategory(null, 'Ken Stout'), 'Beer');
      expect(ImportRowParser.resolveCategory('', 'Zebra Widget'),
          CategoryName.general);
    });
  });

  group('header-less files', () {
    // `sheet.rows.skip(1)` was unconditional, so a supplier file with no header
    // row lost its first product — silently, because a file that starts with a
    // product has nothing about it that looks like an error.
    test('row 1 is treated as data when it is a product', () async {
      final bytes = _workbook({
        'Inventory': [
          _row(id: 1, name: 'First Product', category: 'Beer'),
          _row(id: 2, name: 'Second Product', category: 'Beer'),
          _row(id: 3, name: 'Third Product', category: 'Beer'),
        ],
      });

      final result = await ExcelService().importInventoryBytes(bytes);

      expect(result.imported, 3);
      expect(await productNamed('First Product'), isNotNull);
    });

    test('a header row is detected and skipped when it is one', () async {
      final layout = SheetLayout.fromRawRows([
        _inventoryHeader,
        _row(name: 'A Product'),
      ]);
      expect(layout.headerRowDetected, isTrue);
      expect(layout.rows, hasLength(1));
      expect(layout.rows.single.number, 2);
    });

    test('a first data row is never mistaken for a header', () {
      // "Blue Band 2pk" has a number in it, so it cannot be a header row however
      // many of its words happen to be field names.
      expect(
        SheetLayout.fromRawRows([
          ['1', 'Blue Band 2pk', 'Household', '60', '90', '12', '4'],
        ]).headerRowDetected,
        isFalse,
      );
    });

    test('column names map the columns, not their position', () async {
      // A workbook whose columns were dragged around used to import every price
      // into the wrong field.
      final bytes = _workbook({
        'Inventory': [
          ['Product Name', 'Selling Price', 'Cost Price', 'Size', 'Category'],
          ['Kenya Lager', '120', '70', '750', 'beer'],
        ],
      });

      final result = await ExcelService().importInventoryBytes(bytes);

      expect(result.imported, 1);
      final product = await productNamed('Kenya Lager');
      expect(product!.sellPrice, Money.fromMajor(120));
      expect(product.costPrice, Money.fromMajor(70));
      expect(product.bottleMl, 750);
      expect(product.category, 'Beer');
    });
  });

  group('optional prices are never destroyed', () {
    // The confirmed bug: a non-numeric half_price became null and was written,
    // destroying a real price. Then the till quietly charged half the sell price
    // for a portion the shop had priced by hand.
    test('a bad optional price rejects the row and keeps the stored price',
        () async {
      await db.upsertProduct(Product(
        id: 1,
        name: 'Kenya Lager',
        category: 'Beer',
        costPrice: Money.fromMajor(60),
        sellPrice: Money.fromMajor(100),
        stockQty: 24,
        reorderLevel: 6,
        halfPrice: Money.fromMajor(25),
        quarterPrice: Money.fromMajor(15),
        bottleMl: 750,
        updatedAt: DateTime.now().toIso8601String(),
      ));

      final bytes = _workbook({
        'Inventory': [
          _inventoryHeader,
          _row(id: 1, name: 'Kenya Lager', half: 'TBD', quarter: 15),
        ],
      });

      final result = await ExcelService().importInventoryBytes(bytes);

      expect(result.imported, 0,
          reason: 'nothing was written, so nothing broke');
      final stored = await productNamed('Kenya Lager');
      expect(stored!.halfPrice, Money.fromMajor(25));
      expect(stored.quarterPrice, Money.fromMajor(15));
    });

    test('the rejected row keeps its original values for the owner', () async {
      final bytes = _workbook({
        'Inventory': [
          _inventoryHeader,
          _row(id: 1, name: 'Kenya Lager', half: 'TBD'),
        ],
      });

      await ExcelService().importInventoryBytes(bytes);

      final problem = (await db.getImportProblems()).single;
      expect(problem.problem, contains('TBD'));
      expect(problem.problem, contains('Half price'));
      expect(problem.rawName, 'Kenya Lager');
      expect(problem.rawRow, contains('TBD'));
    });

    test('an empty optional price still means "not sold in portions"',
        () async {
      final bytes = _workbook({
        'Inventory': [
          _inventoryHeader,
          _row(id: 1, name: 'Soda 350ml', half: '', quarter: ''),
        ],
      });

      final result = await ExcelService().importInventoryBytes(bytes);

      expect(result.imported, 1);
      expect(result.needsAttention, 0);
      final product = await productNamed('Soda 350ml');
      expect(product!.halfPrice, isNull);
      expect(product.quarterPrice, isNull);
    });

    test('a real optional price is written', () async {
      final bytes = _workbook({
        'Inventory': [
          _inventoryHeader,
          _row(id: 1, name: 'Kenya Lager', half: 55, quarter: '30.50'),
        ],
      });

      await ExcelService().importInventoryBytes(bytes);

      final product = await productNamed('Kenya Lager');
      expect(product!.halfPrice, Money.fromMajor(55));
      expect(product.quarterPrice, Money.fromMajor(30.5));
    });
  });

  group('required and defaulted fields', () {
    test('cost and sell price are required; everything else defaults',
        () async {
      final bytes = _workbook({
        'Inventory': [
          _inventoryHeader,
          // `bottle: ''` is the point: the row omits the size, which is the
          // one thing here worth flagging. Left at the 750 default there is
          // nothing missing and nothing to flag.
          _row(id: 1, name: 'Bare Minimum', stock: '', reorder: '', bottle: ''),
        ],
      });

      final result = await ExcelService().importInventoryBytes(bytes);

      expect(result.imported, 1);
      final product = await productNamed('Bare Minimum');
      expect(product!.stockQty, 0,
          reason: 'blank stock is zero, and is not flagged');
      expect(product.reorderLevel, 5);
      expect(result.needsAttention, 1,
          reason: 'only the missing size is worth the owner looking at it');
    });

    test('a missing cost price is flagged', () {
      final parsed =
          ImportRowParser.parseProductRow(_row(name: 'No Cost', cost: ''));
      expect(parsed.product, isNull);
      expect(parsed.problem, 'No Cost price');
    });

    test('a missing sell price is flagged', () {
      final parsed =
          ImportRowParser.parseProductRow(_row(name: 'No Price', sell: ''));
      expect(parsed.product, isNull);
      expect(parsed.problem, 'No Selling price');
    });

    test('a missing name is flagged', () {
      final parsed =
          ImportRowParser.parseProductRow(_row(name: '', cost: 10, sell: 20));
      expect(parsed.product, isNull);
      expect(parsed.problem, 'No product name');
    });

    test('a row with too few cells is flagged, not silently skipped', () {
      final parsed = ImportRowParser.parseProductRow(['1', 'Only A Name']);
      expect(parsed.product, isNull);
      expect(parsed.problem, isNotNull);
    });

    test('a completely blank row is not a row at all', () {
      expect(SheetColumns.isBlankRow([null, '', '   ', null]), isTrue);
      expect(SheetColumns.isBlankRow([null, '', 'Coke', '']), isFalse);
    });
  });

  group('finding the inventory sheet', () {
    // The sheet used to be found by position, so a workbook whose first tab was
    // something else was parsed as if it were the catalogue and then failed with
    // one generic message for the whole file.
    test('the tab named Inventory wins over an earlier tab', () async {
      final bytes = _workbook({
        'Sales': [
          ['date', 'staff', 'total'],
          ['2026-01-01', 'Amina', '4000'],
        ],
        'inventory': [_inventoryHeader, _row(name: 'Kenya Lager')],
      });

      final result = await ExcelService().importInventoryBytes(bytes);

      expect(result.imported, 1);
      expect(await productNamed('Kenya Lager'), isNotNull);
    });

    test('an unrecognised first tab falls back to it', () async {
      final bytes = _workbook({
        'Price List': [_inventoryHeader, _row(name: 'Kenya Lager')],
      });

      final result = await ExcelService().importInventoryBytes(bytes);

      expect(result.imported, 1);
      expect(result.skippedSheets, isEmpty,
          reason: 'the tab it fell back to is the one it read');
    });

    test('the tabs it did not read are reported', () async {
      final bytes = _workbook({
        'Inventory': [_inventoryHeader, _row(name: 'Kenya Lager')],
        'Sales': [
          ['date', 'total']
        ],
        'Notes': [
          ['hello']
        ],
      });

      final result = await ExcelService().importInventoryBytes(bytes);

      expect(result.skippedSheets, containsAll(['Sales', 'Notes']));
    });

    test('a file that is not a workbook says so in words', () async {
      expect(
        () => ExcelService().importInventoryBytes(List<int>.filled(64, 0x41)),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('the optional extra sheets', () {
    test('an additional barcode attaches to the product that was imported',
        () async {
      final bytes = _workbook({
        'Inventory': [_inventoryHeader, _row(id: 7, name: 'Kenya Lager')],
        'Barcodes': [
          ProductBarcode.sheetHeaders,
          [7, '6002222222226', 'own'],
        ],
      });

      final result = await ExcelService().importInventoryBytes(bytes);

      expect(result.imported, 1);
      expect(result.needsAttention, 0);
      final product = await productNamed('Kenya Lager');
      expect(await db.getBarcodesForProduct(product!.id!), hasLength(1));
    });

    test('a barcode pointing at a product outside the import is kept, not lost',
        () async {
      final bytes = _workbook({
        'Inventory': [_inventoryHeader, _row(id: 7, name: 'Kenya Lager')],
        'Barcodes': [
          ProductBarcode.sheetHeaders,
          [999, '6003333333337', 'supplier'],
        ],
      });

      final result = await ExcelService().importInventoryBytes(bytes);

      expect(result.imported, 1);
      expect(result.needsAttention, 1);
      expect((await db.getImportProblems()).single.problem,
          contains('not in this import'));
    });

    test('a re-import supersedes the barcode rows it replaces too', () async {
      // The shipped bug resolved problems only under the inventory tab, but
      // barcode rows are recorded under the Barcodes tab — so every previous
      // import's barcode problems accumulated forever and the dashboard's open
      // count could never reach zero for a shop whose barcodes ever failed.
      final broken = _workbook({
        'Inventory': [_inventoryHeader, _row(id: 7, name: 'Kenya Lager')],
        'Barcodes': [
          ProductBarcode.sheetHeaders,
          [999, '6003333333337', 'supplier'],
        ],
      });
      await ExcelService().importInventoryBytes(broken);
      expect(await db.countOpenImportProblems(), 1);

      final fixed = _workbook({
        'Inventory': [_inventoryHeader, _row(id: 7, name: 'Kenya Lager')],
        'Barcodes': [
          ProductBarcode.sheetHeaders,
          [7, '6003333333337', 'supplier'],
        ],
      });
      final result = await ExcelService().importInventoryBytes(fixed);

      expect(result.needsAttention, 0);
      expect(await db.countOpenImportProblems(), 0,
          reason: 'the re-import replaced the barcode failure it fixed');
    });

    test('variants attach to the product row that was imported', () async {
      final bytes = _workbook({
        'Inventory': [_inventoryHeader, _row(id: 3, name: 'Kenyana Beer')],
        'Variants': [
          ProductVariant.sheetHeaders,
          [3, '', 'Dark', 'DK1', 'each', 500, 120, 70, 10, 4],
          [3, '', 'Regular', 'RG1', 'each', 500, 110, 65, 12, 4],
        ],
      });

      final result = await ExcelService().importInventoryBytes(bytes);

      expect(result.imported, 1);
      expect(result.needsAttention, 0);
      final product = await productNamed('Kenyana Beer');
      final variants = await db.getVariants(product!.id!, activeOnly: false);
      expect(variants.map((v) => v.name), containsAll(['Dark', 'Regular']));
      final dark = variants.firstWhere((v) => v.name == 'Dark');
      expect(dark.sellPrice, Money.fromMajor(120));
      expect(dark.sizeMl, 500);
    });

    test('a variant row with no price is flagged, not written silently',
        () async {
      final bytes = _workbook({
        'Inventory': [_inventoryHeader, _row(id: 3, name: 'Kenyana Beer')],
        'Variants': [
          ProductVariant.sheetHeaders,
          [3, '', 'Dark', '', 'each', 500, '', '', '', ''],
        ],
      });

      final result = await ExcelService().importInventoryBytes(bytes);

      expect(result.needsAttention, 1);
      expect((await db.getImportProblems()).single.problem,
          contains('no selling price'));
    });

    test('a workbook from before these sheets existed still imports', () async {
      final bytes = _workbook({
        'Inventory': [_inventoryHeader, _row(name: 'Kenya Lager')],
      });

      final result = await ExcelService().importInventoryBytes(bytes);

      expect(result.imported, 1);
      expect(result.needsAttention, 0);
      expect(result.skippedSheets, isEmpty);
    });
  });

  group('number formats a supplier actually writes', () {
    test('grouped thousands and a currency prefix are read', () async {
      final parsed = ImportRowParser.parseProductRow(
        _row(name: 'Bulk Order', cost: '1,200.50', sell: 'KSh 2,000'),
      );
      expect(parsed.product!.costPrice, Money.fromMajor(1200.5));
      expect(parsed.product!.sellPrice, Money.fromMajor(2000));
    });

    test('an ambiguous comma is not silently guessed at', () async {
      // "12,50" is 12.50 in one convention and 1250 in another. Guessing is how
      // a price nobody typed ends up on the shelf.
      final parsed = ImportRowParser.parseProductRow(
        _row(name: 'Ambiguous', cost: '12,50'),
      );
      expect(parsed.product, isNull);
      expect(parsed.problem, contains('is not a number'));
    });

    test('a garbage stock count defaults to zero and is flagged', () async {
      final parsed = ImportRowParser.parseProductRow(
        _row(name: 'Uncounted', stock: 'twenty'),
      );
      expect(parsed.product!.stockQty, 0);
      expect(parsed.problem, contains('Stock quantity'));
      expect(parsed.severity, ImportProblem.attention);
    });
  });

  group('the export shape the importer reads back', () {
    test('a round trip through toSheetRow preserves money', () {
      final product = Product(
        name: 'Soda 350ml',
        category: 'Soft Drinks',
        costPrice: Money.fromMajor(40.5),
        sellPrice: Money.fromMajor(59.97),
        stockQty: 24,
        reorderLevel: 6,
        halfPrice: Money.fromMajor(35),
        bottleMl: 350,
        updatedAt: '2026-01-01T00:00:00.000',
      );

      final reimported = Product.fromRow(product.toSheetRow())!;

      expect(reimported.sellPrice, product.sellPrice);
      expect(reimported.costPrice, product.costPrice);
      expect(reimported.halfPrice, product.halfPrice);
      expect(reimported.bottleMl, 350);
      expect(reimported.category, 'Soft Drinks');
    });

    test('the unit column is part of the sheet', () {
      expect(Product.sheetHeaders, contains('unit'));
      expect(Product.sheetColumnCount, Product.sheetHeaders.length);
      expect(Product.sheetRange, 'Inventory!A1:M');
      final product = Product(
        name: 'Keg',
        category: 'Beer',
        costPrice: Money.fromMajor(500),
        sellPrice: Money.fromMajor(900),
        stockQty: 2,
        reorderLevel: 1,
        bottleMl: 50000,
        unit: ProductUnit.litre,
        updatedAt: '2026-01-01T00:00:00.000',
      );
      expect(product.toSheetRow().last, 'litre');
      // The size column carries litres for a litre-declared row. Writing 50000
      // there and reading it back as litres produced 50 000 000 ml — a
      // thousand-fold error that survived the round trip looking perfectly
      // valid, which is the only reason this assertion exists.
      final row = product.toSheetRow();
      // By column position, not by searching the row for a number that has
      // deliberately just changed.
      final sizeColumn = Product.sheetHeaders.indexOf('bottle_ml');
      expect(row[sizeColumn], '50',
          reason: 'litres, matching the declared unit');
      final parsed = Product.fromRow(row);
      expect(parsed!.unit, ProductUnit.litre);
      expect(parsed.bottleMl, 50000,
          reason:
              'a 50-litre keg must survive export and re-import as 50 000 ml');
    });

    test('an exported product imports with no attention flags', () async {
      final product = Product(
        name: 'Kenya Lager',
        category: 'Beer',
        costPrice: Money.fromMajor(60),
        sellPrice: Money.fromMajor(100),
        stockQty: 24,
        reorderLevel: 6,
        bottleMl: 750,
        updatedAt: '2026-01-01T00:00:00.000',
      );

      final result = await ExcelService().importInventoryBytes(_workbook({
        'Inventory': [_inventoryHeader, product.toSheetRow()],
      }));

      expect(result.imported, 1);
      expect(result.needsAttention, 0);
    });
  });

  group('a workbook we cannot map is refused whole', () {
    // The tracker above, read positionally, wrote 38 products at the wrong
    // numbers and flagged 287 rows as failed. Both outcomes came from the same
    // mistake, so the tests below assert neither happens.

    test('the whole file is refused, and nothing is written', () async {
      final bytes = _workbook({'Sheet1': _tracker()});

      await expectLater(
        ExcelService().importInventoryBytes(bytes),
        throwsA(isA<UnreadableLayoutException>()),
      );

      // The point of refusing whole: no product, and no phantom needs-attention
      // rows for a file whose rows were never readable in the first place.
      expect(await db.getProducts(activeOnly: false), isEmpty);
      expect(await db.countOpenImportProblems(), 0);
    });

    test('the owner is told the file is not ours, not that 287 rows are bad',
        () async {
      final bytes = _workbook({'Sheet1': _tracker(products: 3)});

      await expectLater(
        ExcelService().importInventoryBytes(bytes),
        throwsA(isA<UnreadableLayoutException>().having(
          (UnreadableLayoutException e) => e.message,
          'message',
          allOf(contains('category'), contains('inventory format')),
        )),
      );
    });

    test('a file in this app\'s own export order still imports', () async {
      // Header-less is a promise the app makes and keeps: our export names its
      // products in the first column, so the positional read is right for it.
      // Refusing on shape must not take the legitimate case down with it.
      final bytes = _workbook({
        'Inventory': [
          _row(id: 1, name: 'Kenya Lager', category: 'Beer'),
          _row(id: 2, name: 'Bond 7', category: 'Spirits'),
          _row(id: 3, name: 'Blue Ice', category: 'Spirits'),
        ],
      });

      final result = await ExcelService().importInventoryBytes(bytes);

      expect(result.imported, 3);
      expect(result.needsAttention, 0);
      expect(await productNamed('Kenya Lager'), isNotNull);
    });

    test('a header row with a number in it is still a header', () async {
      // The latent half of the same bug. A year, a version column, a count of
      // rows: a header row with a number in it used to be discarded whole and
      // the file read positionally, so every field landed one column over.
      final bytes = _workbook({
        'Inventory': [
          <dynamic>[
            '2026',
            'Name',
            'Cost price',
            'Selling price',
            'Stock qty',
            'Bottle ml',
          ],
          <dynamic>['', 'Kenya Lager', 60, 100, 24, 500],
          <dynamic>['', 'Bond 7', 90, 200, 12, 750],
        ],
      });

      final result = await ExcelService().importInventoryBytes(bytes);

      expect(result.imported, 2);
      expect(result.needsAttention, 0);
      final kenya = await productNamed('Kenya Lager');
      expect(kenya!.costPrice.minorUnits, 6000,
          reason: 'read from Cost price, not from the year column');
      expect(kenya.sellPrice.minorUnits, 10000);
      expect(kenya.stockQty, 24);
    });

    test('a file whose category column was deleted is not accused of it',
        () async {
      // Only FILLED cells are counted. Blank is no evidence that a file is not
      // ours, and an owner who deletes the category column from their own
      // export must still be able to import it.
      final bytes = _workbook({
        'Inventory': [
          <dynamic>['', 'Kenya Lager', null, 60, 100, 24],
          <dynamic>['', 'Bond 7', null, 90, 200, 12],
          <dynamic>['', 'Blue Ice', null, 110, 260, 9],
        ],
      });

      final result = await ExcelService().importInventoryBytes(bytes);

      expect(result.imported, 3);
      final kenya = await productNamed('Kenya Lager');
      expect(kenya!.costPrice.minorUnits, 6000);
      expect(kenya.sellPrice.minorUnits, 10000);
    });

    test('an import supersedes what the last import of the sheet recorded',
        () async {
      // The dashboard tells the owner to re-import the spreadsheet to finish
      // the update. That is only true if a re-import clears the rows the
      // previous import failed on, so a fixed file must not leave the old
      // failures counted against it forever.
      final broken = _workbook({
        'Inventory': [
          _inventoryHeader,
          _row(
              id: 1,
              name: 'Kenya Lager',
              category: 'Beer',
              cost: 'not a price'),
          _row(id: 2, name: 'Bond 7', category: 'Spirits'),
        ],
      });
      await ExcelService().importInventoryBytes(broken);
      expect(await db.countOpenImportProblems(), 1);

      final fixed = _workbook({
        'Inventory': [
          _inventoryHeader,
          _row(id: 1, name: 'Kenya Lager', category: 'Beer'),
          _row(id: 2, name: 'Bond 7', category: 'Spirits'),
        ],
      });
      final result = await ExcelService().importInventoryBytes(fixed);

      expect(result.imported, 2);
      expect(result.needsAttention, 0);
      expect(await db.countOpenImportProblems(), 0,
          reason: 'the re-import replaced the failure it fixed');
    });

    test('a refused import leaves what that sheet recorded alone', () async {
      // A refusal says nothing about the rows a PREVIOUS import left behind.
      // The refused file was read, wrote nothing, and the tab name it failed on
      // need not even be the tab the problems were recorded under — resolving
      // them here destroys the only copy of those raw row values, which is
      // what the imports screen exists to finish.
      final broken = _workbook({
        'Sheet1': [
          _inventoryHeader,
          _row(
              id: 1,
              name: 'Kenya Lager',
              category: 'Beer',
              cost: 'not a price'),
        ],
      });
      await ExcelService().importInventoryBytes(broken);
      expect(await db.countOpenImportProblems(), 1);

      final tracker = _workbook({'Sheet1': _tracker(products: 3)});
      await expectLater(
        ExcelService().importInventoryBytes(tracker),
        throwsA(isA<UnreadableLayoutException>()),
      );

      expect(await db.countOpenImportProblems(), 1);
    });

    test('a refused import cannot clear a different file\'s problems',
        () async {
      // The shipped bug's other half: the refusal resolved problems keyed on
      // the REFUSING file's tab name, which falls back to its first non-empty
      // tab. A broken workbook whose only tab shares a name with last week's
      // good import therefore wiped last week's rows.
      final broken = _workbook({
        'Sheet1': [
          _inventoryHeader,
          _row(
              id: 1,
              name: 'Kenya Lager',
              category: 'Beer',
              cost: 'not a price'),
        ],
      });
      await ExcelService().importInventoryBytes(broken);
      expect(await db.countOpenImportProblems(), 1);

      // A different workbook — the supplier tracker shape — refused, and its
      // tab shares the name the problems were recorded under.
      final other = _workbook({'Sheet1': _tracker(products: 2)});
      await expectLater(
        ExcelService().importInventoryBytes(other),
        throwsA(isA<UnreadableLayoutException>()),
      );

      expect(await db.countOpenImportProblems(), 1);
    });

    test('a price is parsed as the exact figure written, not a float of it',
        () async {
      // The money path used to go double -> *100 -> round(), which is a binary
      // float carrying a hidden remainder and a second rounding site in the same
      // breath. "40.55" is 40 shillings and 55 cents because the digits say so.
      for (final MapEntry<String, int> expected in <MapEntry<String, int>>[
        const MapEntry<String, int>('150', 15000),
        const MapEntry<String, int>('150.5', 15050),
        const MapEntry<String, int>('150.05', 15005),
        const MapEntry<String, int>('0.01', 1),
        const MapEntry<String, int>('1200.55', 120055),
        const MapEntry<String, int>('1,200.50', 120050),
        const MapEntry<String, int>('KSh 40.50', 4050),
        const MapEntry<String, int>('40.555', 4056),
        const MapEntry<String, int>('.5', 50),
        const MapEntry<String, int>('197.10', 19710),
        const MapEntry<String, int>('  12.34  ', 1234),
      ]) {
        expect(SheetColumns.parseMinorUnits(expected.key), expected.value,
            reason: '${expected.key} must read as exactly what is written');
      }
      // Not a price is reported as not a price, never defaulted.
      expect(SheetColumns.parseMinorUnits('not a price'), isNull);
      expect(SheetColumns.parseMinorUnits(''), isNull);
      expect(SheetColumns.parseMinorUnits(null), isNull);

      // And the same for a digit string too long to be a price. The shipped
      // bug threw out of the parser — `int.parse` on 20 digits — and the throw
      // escaped the row loop into the screens' `on FormatException`, so one
      // pasted serial number in a price column cost the owner the whole file
      // instead of one reported row. Null is one row; a throw is every row.
      expect(SheetColumns.parseMinorUnits('12345678901234567890'), isNull);
      expect(SheetColumns.parseMinorUnits('1,234,567,890,123,456,789,012'),
          isNull);
      expect(SheetColumns.parseMinorUnits(1e20), isNull);

      final bytes = _workbook({
        'Inventory': [
          _inventoryHeader,
          _row(id: 1, name: 'Kenya Lager', cost: 40.55, sell: 60.25),
          _row(id: 2, name: 'Bond 7', cost: 0.29, sell: 1.99),
        ],
      });
      await ExcelService().importInventoryBytes(bytes);

      final kenya = await productNamed('Kenya Lager');
      expect(kenya!.costPrice.minorUnits, 4055);
      expect(kenya.sellPrice.minorUnits, 6025);
      final bond = await productNamed('Bond 7');
      expect(bond!.costPrice.minorUnits, 29);
      expect(bond.sellPrice.minorUnits, 199);
    });

    test('an absurd price is one bad row, not the whole import', () async {
      // The companion to the parse above: a digit string too long for minor
      // units is a row the parser rejects, so the rest of the file still
      // imports. The bug this replaces aborted the workbook with the generic
      // "that workbook is invalid".
      final bytes = _workbook({
        'Inventory': [
          _inventoryHeader,
          _row(id: 1, name: 'Kenya Lager', cost: 60, sell: 100),
          _row(id: 2, name: 'Serial Kersteen', cost: '12345678901234567890'),
          _row(id: 3, name: 'Bond 7', cost: 29, sell: 45),
        ],
      });
      final result = await ExcelService().importInventoryBytes(bytes);

      expect(result.imported, 2, reason: 'the two real products survive');
      expect(result.needsAttention, 1);
      expect(await productNamed('Serial Kersteen'), isNull);
      expect((await productNamed('Kenya Lager'))!.costPrice.minorUnits, 6000);
    });

    test('a section title in the sheet files every product under it', () async {
      // A supplier groups its rows under titles sitting alone in the first
      // column. That row is not a product, and skipping it without reading it
      // throws away the only category the sheet ever states — leaving the
      // owner to re-file goods by hand forever, or worse, with the title
      // itself imported as a product.
      final bytes = _workbook({
        'Inventory': [
          <dynamic>['', 'Name', 'Cost price', 'Selling price', 'Category'],
          <dynamic>['SPIRITS 1 ltr'],
          <dynamic>['', 'Bond 7', 90, 200],
          <dynamic>['', 'Best Gin', 110, 260],
          <dynamic>['Beer Bottles'],
          <dynamic>['', 'Tusker', 120, 180],
        ],
      });

      final result = await ExcelService().importInventoryBytes(bytes);

      expect(result.imported, 3, reason: 'the title rows are not products');
      final bond = await productNamed('Bond 7');
      // Normalised by the same rule every category goes through, so a sheet's
      // titles differing by case or trailing space produce one category.
      expect(bond!.category, CategoryName.normalise('SPIRITS 1 ltr'));
      final gin = await productNamed('Best Gin');
      expect(gin!.category, CategoryName.normalise('SPIRITS 1 ltr'));
      final tusker = await productNamed('Tusker');
      expect(tusker!.category, CategoryName.normalise('Beer Bottles'),
          reason: 'the row under a different title takes THAT title');
    });

    test('a stray number sitting alone is not a category title', () async {
      // The same sheets carry counts in that first column — a bottle tally, a
      // page number. Read as a title, the next twenty products would file
      // themselves under "13".
      final bytes = _workbook({
        'Inventory': [
          <dynamic>['', 'Name', 'Cost price', 'Selling price'],
          <dynamic>['13'],
          <dynamic>['', 'Bond 7', 90, 200],
        ],
      });

      final result = await ExcelService().importInventoryBytes(bytes);

      expect(result.imported, 1);
      final bond = await productNamed('Bond 7');
      expect(bond!.category, 'General',
          reason: 'a number is a count, not a category');
    });

    test("a row's own category cell wins over the section title", () async {
      final bytes = _workbook({
        'Inventory': [
          <dynamic>['', 'Name', 'Cost price', 'Selling price', 'Category'],
          <dynamic>['SPIRITS 1 ltr'],
          <dynamic>['', 'Bond 7', 90, 200, 'Gin'],
        ],
      });

      await ExcelService().importInventoryBytes(bytes);

      final bond = await productNamed('Bond 7');
      expect(bond!.category, 'Gin',
          reason: 'an owner who filled the column in meant it');
    });

    test('a named header row wins over the shape check', () async {
      // Once the header is read by name, the shape of the columns is irrelevant
      // — which is the whole point of reading headers. A tracker whose owner has
      // labelled the columns imports correctly rather than being refused.
      final bytes = _workbook({
        'Inventory': [
          <dynamic>[
            'Section',
            'Product name',
            'Cost price',
            'Selling price',
            'Stock qty'
          ],
          <dynamic>['SPIRITS', 'Bond 7', 90, 200, 5],
          <dynamic>['SPIRITS', 'Best Gin', 110, 260, 8],
        ],
      });

      final result = await ExcelService().importInventoryBytes(bytes);

      expect(result.imported, 2);
      final bond = await productNamed('Bond 7');
      expect(bond!.costPrice.minorUnits, 9000);
      expect(bond.sellPrice.minorUnits, 20000);
      expect(bond.stockQty, 5);
    });
  });
}
