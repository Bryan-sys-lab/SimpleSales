// Schema migration tests.
//
// Money moved from REAL shillings to INTEGER minor units at schema v11. This is
// the riskiest change in the project: it rebuilds three tables on a phone that
// holds a shop's live ledger, and a mistake here is silent — wrong totals, or a
// till that will not open at all. So the migration is exercised against a real
// database file built at the old schema rather than asserted structurally.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/models/models.dart';

/// Builds a database at schema v10 with the given rows.
///
/// Written out literally rather than derived from the live code so the test
/// still describes v10 after v11 has landed, and so it genuinely fails if the
/// v10 shape is ever misremembered.
Future<void> _createV10Database(
    String path, {
  List<Map<String, Object?>> products = const [],
  List<Map<String, Object?>> sales = const [],
  List<Map<String, Object?>> saleItems = const [],
}) async {
  final db = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 10,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE products (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            category TEXT,
            cost_price REAL NOT NULL,
            sell_price REAL NOT NULL,
            stock_qty REAL NOT NULL DEFAULT 0,
            reorder_level INTEGER NOT NULL DEFAULT 5,
            bottle_ml INTEGER NOT NULL DEFAULT 750,
            half_price REAL,
            quarter_price REAL,
            excise_stamp_batch TEXT,
            active INTEGER NOT NULL DEFAULT 1,
            updated_at TEXT,
            remote_id TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE sales (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            staff_name TEXT NOT NULL,
            staff_id INTEGER,
            total REAL NOT NULL,
            profit REAL NOT NULL,
            payment_method TEXT NOT NULL DEFAULT 'cash',
            payment_reference TEXT,
            amount_tendered REAL NOT NULL DEFAULT 0,
            change_given REAL NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE sale_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sale_id INTEGER NOT NULL,
            product_id INTEGER NOT NULL,
            product_name TEXT NOT NULL,
            qty REAL NOT NULL,
            unit_price REAL NOT NULL,
            unit_cost REAL NOT NULL,
            portion TEXT NOT NULL DEFAULT 'full',
            portion_ml INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (sale_id) REFERENCES sales (id)
          )
        ''');
        await db.execute('CREATE INDEX idx_sales_date ON sales (created_at)');
        await db.execute(
            'CREATE INDEX idx_sale_items_product ON sale_items (product_id)');
        await db.execute(
            'CREATE INDEX idx_sale_items_sale ON sale_items (sale_id)');
        await db.execute('CREATE INDEX idx_sales_staff ON sales (staff_id)');
      },
    ),
  );

  for (final row in products) {
    await db.insert('products', row);
  }
  for (final row in sales) {
    await db.insert('sales', row);
  }
  for (final row in saleItems) {
    await db.insert('sale_items', row);
  }

  await db.close();
}

Map<String, Object?> product({
  int? id = 1,
  String name = 'Soda 350ml',
  Object cost = 40.0,
  Object sell = 80.0,
  Object? half,
  Object? quarter,
}) =>
    {
      if (id != null) 'id': id,
      'name': name,
      'category': 'Drinks',
      'cost_price': cost,
      'sell_price': sell,
      'stock_qty': 24.0,
      'reorder_level': 6,
      'bottle_ml': 350,
      'half_price': half,
      'quarter_price': quarter,
      'excise_stamp_batch': '',
      'active': 1,
      'updated_at': '2026-01-01T00:00:00.000',
    };

Map<String, Object?> sale({
  int id = 1,
  Object total = 160.0,
  Object profit = 80.0,
  Object tendered = 200.0,
  Object change = 40.0,
}) =>
    {
      'id': id,
      'staff_name': 'Alice',
      'staff_id': 7,
      'total': total,
      'profit': profit,
      'payment_method': 'cash',
      'payment_reference': null,
      'amount_tendered': tendered,
      'change_given': change,
      'created_at': '2026-01-02T09:30:00.000',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  // The production code opens databases through the global factory, which only
  // exists once one has been installed.
  databaseFactory = databaseFactoryFfi;

  late Directory dir;
  late String path;

  setUp(() async {
    DatabaseHelper.resetForTests();
    dir = await Directory.systemTemp.createTemp('duka_migration');
    path = '${dir.path}/legacy_shop.db';
  });

  tearDown(() async {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  /// Builds a v10 file, then opens it at the current schema version so the real
  /// migration runs. Returns the upgraded handle; the caller closes it.
  Future<Database> migrated({
    List<Map<String, Object?>> products = const [],
    List<Map<String, Object?>> sales = const [],
    List<Map<String, Object?>> saleItems = const [],
  }) async {
    await _createV10Database(path,
        products: products, sales: sales, saleItems: saleItems);
    return DatabaseHelper.openExistingForUpgradeTests(path);
  }

  test('v10 amounts become exact integer cents', () async {
    final db = await migrated(
        products: [product(cost: 40.5, sell: 80.0, half: 40.0, quarter: 20.25)]);
    final row = (await db.query('products')).first;

    expect(row['cost_price'], 4050);
    expect(row['sell_price'], 8000);
    expect(row['half_price'], 4000);
    expect(row['quarter_price'], 2025);
    await db.close();
  });

  test('a drifting REAL amount is rounded, not truncated', () async {
    // 19.99 and 59.97 are not representable in binary floating point, so this
    // is the value a real v10 till has on disk.
    final db = await migrated(products: [product(cost: 19.99, sell: 59.97)]);
    final row = (await db.query('products')).first;

    expect(row['sell_price'], 5997);
    expect(row['cost_price'], 1999);
    // Stored as an integer, not a float that merely looks like one.
    expect(row['sell_price'], isA<int>());
    await db.close();
  });

  test('NULL half and quarter prices survive as NULL, not zero', () async {
    // A zero would silently invent a free half-bottle on every product that
    // never had a portion price set.
    final db = await migrated(products: [product()]);
    final row = (await db.query('products')).first;

    expect(row['half_price'], isNull);
    expect(row['quarter_price'], isNull);
    await db.close();
  });

  test('sales and line items survive, and quantities stay REAL', () async {
    final db = await migrated(
      products: [product()],
      sales: [sale()],
      saleItems: [
        {
          'id': 1,
          'sale_id': 1,
          'product_id': 1,
          'product_name': 'Soda 350ml',
          'qty': 2.0,
          'unit_price': 80.0,
          'unit_cost': 40.0,
          'portion': 'full',
          'portion_ml': 350,
        }
      ],
    );

    final s = (await db.query('sales')).first;
    expect(s['total'], 16000);
    expect(s['profit'], 8000);
    expect(s['amount_tendered'], 20000);
    expect(s['change_given'], 4000);
    // Non-money columns must be untouched.
    expect(s['staff_name'], 'Alice');
    expect(s['staff_id'], 7);
    expect(s['payment_method'], 'cash');
    expect(s['created_at'], '2026-01-02T09:30:00.000');

    final item = (await db.query('sale_items')).first;
    expect(item['unit_price'], 8000);
    expect(item['unit_cost'], 4000);
    // qty counts bottles, not shillings, so it stays REAL.
    expect(item['qty'], 2.0);
    expect(item['portion'], 'full');
    expect(item['sale_id'], 1);
    await db.close();
  });

  test('the rebuilt tables are INTEGER, not REAL', () async {
    // Affinity is the entire reason the tables are rebuilt rather than updated:
    // writing an integer into a REAL column silently converts it back to a
    // float, which would reintroduce the bug this migration exists to remove.
    final db = await migrated(products: [product()]);

    const moneyColumns = {
      'cost_price', 'sell_price', 'half_price', 'quarter_price', //
      'total', 'profit', 'amount_tendered', 'change_given',
      'unit_price', 'unit_cost',
    };
    for (final table in ['products', 'sales', 'sale_items']) {
      final info = await db.rawQuery('PRAGMA table_info($table)');
      for (final column in info) {
        if (moneyColumns.contains(column['name'])) {
          expect(column['type'], 'INTEGER',
              reason: '$table.${column['name']} must hold cents');
        }
      }
    }

    final productInfo = await db.rawQuery('PRAGMA table_info(products)');
    expect(productInfo.firstWhere((c) => c['name'] == 'stock_qty')['type'],
        'REAL');
    await db.close();
  });

  test('the sale_items foreign key still points at the rebuilt sales table',
      () async {
    // SQLite 3.25+ rewrites foreign-key clauses when a referenced table is
    // renamed. Had the migration renamed `sales` directly, this reference would
    // now name the throwaway table instead.
    final db = await migrated(
      sales: [sale()],
      saleItems: [
        {
          'id': 1,
          'sale_id': 1,
          'product_id': 1,
          'product_name': 'Soda 350ml',
          'qty': 1.0,
          'unit_price': 80.0,
          'unit_cost': 40.0,
        }
      ],
    );

    final schema = await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name='sale_items'");
    expect(schema.first['sql'], contains('REFERENCES sales (id)'));
    expect(schema.first['sql'], isNot(contains('sales_v11')));

    // Enforcing the constraint proves the reference resolves to a real table.
    await db.execute('PRAGMA foreign_keys = ON');
    await expectLater(
      db.insert('sale_items', {
        'sale_id': 9999,
        'product_id': 1,
        'product_name': 'Orphan',
        'qty': 1.0,
        'unit_price': 1,
        'unit_cost': 1,
      }),
      throwsA(anything),
    );
    await db.close();
  });

  test('indexes are recreated and no temporary tables survive', () async {
    final db = await migrated(
        products: [product()], sales: [sale(total: 10.0)]);

    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'");
    final names = tables.map((t) => t['name'] as String).toList();
    expect(names.where((n) => n.endsWith('_v11')), isEmpty,
        reason: 'an interrupted migration would leave these behind');

    // Indexes live on dropped tables and do not survive the rebuild; without
    // them an upgraded till full-scans every report.
    final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_%'");
    final indexNames = indexes.map((i) => i['name'] as String).toSet();
    expect(indexNames,
        containsAll(['idx_sales_date', 'idx_sale_items_product',
            'idx_sale_items_sale', 'idx_sales_staff']));
    await db.close();
  });

  test('migrated rows read back through the models as exact amounts', () async {
    // The end-to-end claim: after the upgrade the app sees whole shillings
    // again, with no residue from the old float representation.
    final db = await migrated(
      products: [product(cost: 19.99, sell: 59.97)],
      sales: [sale(total: 59.97, profit: 20.0, tendered: 100.0, change: 40.03)],
    );

    final p = Product.fromMap((await db.query('products')).first);
    expect(p.sellPrice.minorUnits, 5997);
    expect(p.sellPrice.asMajor, closeTo(59.97, 1e-9));
    expect(p.costPrice.minorUnits, 1999);
    // A derived portion price is quantised to a real amount.
    expect(p.priceFor('quarter').minorUnits, 1499);

    final s = Sale.fromMap((await db.query('sales')).first);
    expect(s.total.minorUnits, 5997);
    expect(s.amountTendered.minorUnits, 10000);
    expect(s.changeGiven.minorUnits, 4003);
    // Change still reconciles exactly against the tendered cash.
    expect(s.amountTendered - s.total, s.changeGiven);
    await db.close();
  });
}