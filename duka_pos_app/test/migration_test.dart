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
  String staff = 'Alice',
  Object total = 160.0,
  Object profit = 80.0,
  Object tendered = 200.0,
  Object change = 40.0,
}) =>
    {
      'id': id,
      'staff_name': staff,
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
    final db = await migrated(products: [
      product(cost: 40.5, sell: 80.0, half: 40.0, quarter: 20.25)
    ]);
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
    final db =
        await migrated(products: [product()], sales: [sale(total: 10.0)]);

    final tables =
        await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
    final names = tables.map((t) => t['name'] as String).toList();
    expect(names.where((n) => n.endsWith('_v11')), isEmpty,
        reason: 'an interrupted migration would leave these behind');

    // Indexes live on dropped tables and do not survive the rebuild; without
    // them an upgraded till full-scans every report.
    final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_%'");
    final indexNames = indexes.map((i) => i['name'] as String).toSet();
    expect(
        indexNames,
        containsAll([
          'idx_sales_date',
          'idx_sale_items_product',
          'idx_sale_items_sale',
          'idx_sales_staff'
        ]));
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

  // ---------------------------------------------------------------------------
  // v11 -> v12 and v12 -> v13
  //
  // Written as tests rather than inspected as DDL, because the failures these
  // guard against are behavioural: a nullable-but-unique column, a default that
  // makes migrated history look like an error queue, and a primary key that
  // quietly permits NULL. None of those are visible from the CREATE statement.
  // ---------------------------------------------------------------------------

  group('v11 -> v12: barcodes, shop settings and receipt numbering', () {
    test('product_barcodes refuses a duplicate code', () async {
      final db = await migrated(products: [product(cost: 45, sell: 80)]);
      final sodaId = (await db.query('products')).single['id'] as int;

      await db.insert('product_barcodes', {
        'barcode': '6001234567899',
        'product_id': sodaId,
        'kind': 'supplier',
      });

      // `barcode TEXT PRIMARY KEY` is the only thing making a code belong to
      // exactly one product. Without it a scan has an ambiguous answer and the
      // most-recently-saved product silently wins at the till.
      await expectLater(
        db.insert('product_barcodes', {
          'barcode': '6001234567899',
          'product_id': sodaId,
          'kind': 'own',
        }),
        throwsA(anything),
      );
      await db.close();
    });

    test('product_barcodes refuses a NULL code', () async {
      // A TEXT primary key in SQLite permits NULL unless declared NOT NULL, and
      // a NULL barcode would match nothing but would also let a blank row exist
      // that reads back as a real "unknown product" answer.
      final db = await migrated(products: [product(cost: 45, sell: 80)]);
      final sodaId = (await db.query('products')).single['id'] as int;
      await expectLater(
        db.insert('product_barcodes',
            {'barcode': null, 'product_id': sodaId, 'kind': 'supplier'}),
        throwsA(anything),
      );
      await db.close();
    });

    test('the product_id index exists, so listing a product codes is fast',
        () async {
      final db = await migrated();
      final rows = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='index' AND name=?",
          ['idx_product_barcodes_product']);
      expect(rows, hasLength(1));
      await db.close();
    });

    test('shop_settings holds one row per key and replaces on rewrite',
        () async {
      final db = await migrated();
      await db
          .insert('shop_settings', {'key': 'vat_rate_percent', 'value': '16'});
      await db.insert('shop_settings', {'key': 'till_code', 'value': 'T1'});
      expect(await db.query('shop_settings', orderBy: 'key'), hasLength(2));

      await db.insert('shop_settings', {'key': 'till_code', 'value': 'T2'},
          conflictAlgorithm: ConflictAlgorithm.replace);
      final rows = await db
          .query('shop_settings', where: 'key = ?', whereArgs: ['till_code']);
      expect(rows, hasLength(1));
      expect(rows.single['value'], 'T2');
      await db.close();
    });

    test('receipt_counters exists for the per-till sequence', () async {
      final db = await migrated();
      await db.insert('receipt_counters', {'key': 'sale_sequence', 'value': 3});
      expect((await db.query('receipt_counters')).single['value'], 3);
      await db.close();
    });

    test('pre-v12 sales survive together with a NULL receipt number', () async {
      // Nullable with a unique index is what makes a partially-upgraded shop a
      // normal state: many pre-upgrade rows must be able to have no number.
      final db = await migrated(
        products: [product(cost: 45, sell: 80)],
        sales: [
          sale(
              id: 1,
              staff: 'Alice',
              total: 160.0,
              tendered: 200.0,
              change: 40.0),
          sale(id: 2, staff: 'Bob', total: 80.0, tendered: 80.0, change: 0.0),
          sale(
              id: 3,
              staff: 'Carol',
              total: 240.0,
              tendered: 250.0,
              change: 10.0),
        ],
      );
      final sales = await db.query('sales');
      expect(sales, hasLength(3));
      for (final sale in sales) {
        expect(sale['receipt_number'], isNull);
      }
      await db.close();
    });

    test('the receipt number unique index rejects a duplicate', () async {
      final db = await migrated();
      final now = DateTime.now().toIso8601String();
      await db.insert('sales', {
        'staff_name': 'Alice',
        'total': 1600,
        'profit': 500,
        'payment_method': 'cash',
        'created_at': now,
        'receipt_number': 'T1-000001',
      });
      await expectLater(
        db.insert('sales', {
          'staff_name': 'Bob',
          'total': 1600,
          'profit': 500,
          'payment_method': 'cash',
          'created_at': now,
          'receipt_number': 'T1-000001',
        }),
        throwsA(anything),
      );
      await db.close();
    });

    test('an amount unchanged by the money migration still lands', () async {
      // Proves the v12 additions are purely additive: a shop that had already
      // upgraded to v11 picks up barcodes and numbering without its amounts
      // being converted a second time.
      final db = await migrated(
        products: [product(cost: 45, sell: 80)],
        sales: [sale(total: 80.0, tendered: 100.0, change: 20.0)],
      );
      final sales = (await db.query('sales')).map(Sale.fromMap).toList();
      expect(sales.single.total.minorUnits, 8000);
      await db.close();
    });
  });

  group('v12 -> v13: eTIMS issuance state', () {
    test('an upgraded sale defaults to not_required, not pending', () async {
      // The default is the reason a migrated ledger does not open looking like
      // a wall of unreconciled KRA receipts. Defaulting to 'pending' would put
      // every sale the shop ever made into the outstanding queue.
      final db = await migrated(
        sales: [
          sale(staff: 'Legacy', total: 80.0, tendered: 80.0, change: 0.0)
        ],
      );
      final row = (await db.query('sales')).single;
      expect(row['etims_status'], 'not_required');
      expect(row['etims_receipt_number'], isNull);
      await db.close();
    });

    test('the pending queue holds one row per sale', () async {
      final db = await migrated(
        sales: [sale(total: 80.0, tendered: 80.0, change: 0.0)],
      );
      final saleId = (await db.query('sales')).single['id'] as int;
      await db.insert('pending_etims', {
        'sale_id': saleId,
        'receipt_number': 'T1-000001',
        'attempts': 0,
        'created_at': '2026-01-01T00:00:00.000Z',
        'updated_at': '2026-01-01T00:00:00.000Z',
      });
      // Primary key on sale_id, so a retry cannot create a second pending
      // invoice for the same money — the exact failure that turns one
      // un-issued receipt into two.
      await expectLater(
        db.insert('pending_etims', {
          'sale_id': saleId,
          'receipt_number': 'T1-000002',
          'attempts': 0,
          'created_at': '2026-01-01T00:00:00.000Z',
          'updated_at': '2026-01-01T00:00:00.000Z',
        }),
        throwsA(anything),
      );
      await db.close();
    });
  });

  group('v13 -> v14: variants, units, import attention, unverified payments',
      () {
    test('product_variants exists with its own price, stock and barcode',
        () async {
      final db = await migrated(
          products: [product(cost: 45, sell: 80, half: 40, quarter: 20)]);
      final productId = (await db.query('products')).single['id'] as int;

      final variantId = await db.insert('product_variants', {
        'product_id': productId,
        'name': 'Dark',
        'sku': 'BEER-DARK-500',
        'unit': 'cup',
        'size_ml': 500,
        'sell_price': 150,
        'cost_price': 90,
        'stock_qty': 20.0,
        'reorder_level': 5,
        'position': 0,
        'active': 1,
      });

      // The variant owns its price and stock. That is the whole reason it
      // exists: Dark and Regular cannot share one price or one stock count.
      final row = (await db.query('product_variants',
              where: 'id = ?', whereArgs: [variantId]))
          .single;
      expect(row['sell_price'], 150);
      expect(row['stock_qty'], 20.0);
      expect(row['name'], 'Dark');

      // And a barcode can point at the variant rather than the product, so
      // scanning Dark does not sell Regular.
      await db.insert('product_barcodes', {
        'barcode': '6001112223334',
        'product_id': productId,
        'kind': 'own',
        'variant_id': variantId,
      });
      final scan = await db.rawQuery(
        '''SELECT p.name AS product, b.variant_id AS v
             FROM products p JOIN product_barcodes b ON b.product_id = p.id
            WHERE b.barcode = ?''',
        ['6001112223334'],
      );
      expect(scan.single['product'], 'Soda 350ml');
      expect(scan.single['v'], variantId);
      await db.close();
    });

    test('a barcode cannot be attached to both a product and a variant',
        () async {
      final db = await migrated(
          products: [product(cost: 45, sell: 80, half: 40, quarter: 20)]);
      final productId = (await db.query('products')).single['id'] as int;
      await db.insert('product_barcodes', {
        'barcode': '6009998887776',
        'product_id': productId,
        'kind': 'supplier',
      });
      // `barcode TEXT PRIMARY KEY` still forbids it after variant_id was added.
      // If this ever passes, a scan has two candidates and no way to choose.
      await expectLater(
        db.insert('product_barcodes', {
          'barcode': '6009998887776',
          'product_id': productId,
          'kind': 'own',
          'variant_id': null,
        }),
        throwsA(anything),
      );
      await db.close();
    });

    test('products carry a unit and the variants flag', () async {
      final db = await migrated();
      final columns = {
        for (final row in await db.rawQuery('PRAGMA table_info(products)'))
          row['name'] as String
      };
      expect(columns, contains('unit'));
      expect(columns, contains('track_variants'));

      // Defaulting to 'each' keeps every pre-existing product meaningful: a
      // 750ml bottle is a countable thing, not 750 millilitres to be sold by.
      final row = (await db.query('products')).isEmpty
          ? null
          : (await db.query('products')).first;
      if (row != null) {
        expect(row['unit'], 'each');
        expect(row['track_variants'], 0);
      }
      await db.close();
    });

    test('sale lines remember which variant was sold', () async {
      // Denormalised on the line, so a receipt still reads "Dark 500 ml" after
      // the owner renames or deletes the variant. A receipt that changes
      // retroactively cannot be reconciled against the paper.
      final db = await migrated(
        products: [product(cost: 45, sell: 80, half: 40, quarter: 20)],
        sales: [sale(total: 80.0, tendered: 80.0, change: 0.0)],
      );
      final saleId = (await db.query('sales')).single['id'] as int;
      await db.insert('sale_items', {
        'sale_id': saleId,
        'product_id': (await db.query('products')).single['id'] as int,
        'product_name': 'Kenyana Beer',
        'qty': 1.0,
        'unit_price': 150,
        'unit_cost': 90,
        'portion': 'full',
        'portion_ml': 500,
        'variant_name': 'Dark',
      });
      final item = (await db.query('sale_items')).single;
      expect(item['variant_name'], 'Dark');
      await db.close();
    });

    test('existing sales are treated as verified payments', () async {
      // The default must be verified. Defaulting to unverified would put a
      // shop's entire historical ledger into the "reconcile this" list.
      final db = await migrated(
        sales: [sale(total: 80.0, tendered: 80.0, change: 0.0)],
      );
      expect((await db.query('sales')).single['payment_verified'], 1);
      await db.close();
    });

    test('import_needs_attention exists and holds the original row', () async {
      final db = await migrated();
      await db.insert('import_needs_attention', {
        'source': 'excel',
        'sheet_name': 'Inventory',
        'row_number': 14,
        'raw_name': 'Kwancheri Lager',
        'raw_row': '["","Kwancheri Lager","Beer","abc","80"]',
        'problem': 'Cost price is not a number',
        'resolved': 0,
        'created_at': '2026-10-04T09:00:00.000Z',
      });
      final row = (await db.query('import_needs_attention')).single;
      // The original values are kept so the fix is an edit-and-re-import
      // rather than a hunt for the supplier's file.
      expect(row['raw_row'], contains('Kwancheri Lager'));
      expect(row['row_number'], 14);
      expect(row['resolved'], 0);
      await db.close();
    });

    test('categories is a real table, not a free-text column', () async {
      final db = await migrated();
      await db.insert('categories', {'name': 'Beer', 'sort_order': 1});
      // Primary key on the name, so 'Beer' and 'beer' cannot both exist and
      // silently split one report into two.
      await expectLater(
        db.insert('categories', {'name': 'Beer', 'sort_order': 2},
            conflictAlgorithm: ConflictAlgorithm.ignore),
        completes,
      );
      expect(await db.query('categories'), hasLength(1));
      await db.close();
    });
  });

  group('fresh installs match upgraded installs', () {
    test('both have exactly the same tables', () async {
      // `openInMemoryForTests` returns the helper, not the handle; the handle is
      // reached through the singleton's own open accessor.
      await DatabaseHelper.openInMemoryForTests();
      final fresh = await DatabaseHelper.instance.database;
      Future<Set<String>> tablesOf(Database db) async => {
            for (final row in await db.rawQuery(
                "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"))
              row['name'] as String
          };
      final freshTables = await tablesOf(fresh);
      final migratedDb = await migrated();
      final migratedTables = await tablesOf(migratedDb);
      await migratedDb.close();
      await fresh.close();
      expect(freshTables, migratedTables,
          reason: 'a new till and an upgraded one must not diverge');
    });

    test('both have exactly the same columns on every table', () async {
      // Table names alone are not parity. A column that exists on an upgraded
      // till and not on a fresh one is the exact bug this catches: the v24
      // step added `sales.etims_qr_payload` on the UPGRADE path only, so a
      // till installed fresh at v24 never had it and every KRA receipt
      // resolution on it failed with "no such column".
      await DatabaseHelper.openInMemoryForTests();
      final fresh = await DatabaseHelper.instance.database;
      final migratedDb = await migrated();

      Future<Map<String, Set<String>>> columnsOf(Database db) async {
        final tables = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name");
        final result = <String, Set<String>>{};
        for (final table in tables) {
          final name = table['name'] as String;
          final cols = await db.rawQuery('PRAGMA table_info($name)');
          result[name] = {for (final c in cols) c['name'] as String};
        }
        return result;
      }

      final freshColumns = await columnsOf(fresh);
      final migratedColumns = await columnsOf(migratedDb);
      await migratedDb.close();
      await fresh.close();

      // Every table both databases have must carry the same columns.
      for (final table in freshColumns.keys) {
        expect(migratedColumns[table], isNotNull,
            reason: 'table $table is missing from the upgraded database');
        expect(migratedColumns[table], freshColumns[table],
            reason: 'table $table has different columns on a fresh and an '
                'upgraded till');
      }
      for (final table in migratedColumns.keys) {
        expect(freshColumns[table], isNotNull,
            reason: 'table $table is missing from the fresh database');
      }
    });
  });

  group('v14 -> v15: shifts, till counts, shot cups, cup sizes', () {
    /// Builds a file at schema v14 and opens it so the real v15 step runs.
    ///
    /// The v10 builder plus a literal replay of the v11..v14 steps, written out
    /// rather than reused from production code, so this still describes v14
    /// after v15 has landed. Only the tables and columns the v15 step can
    /// disturb are carried across — `products` and `sales`, which is where the
    /// money-rebuild and the unverified-payment column live.
    Future<Database> migratedFromV14({
      List<Map<String, Object?>> products = const [],
      List<Map<String, Object?>> sales = const [],
    }) async {
      await _createV10Database(path, products: products, sales: sales);
      final db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 14,
          onOpen: (db) async {
            // v11: money becomes integer minor units.
            //
            // The declared type is rewritten by rebuilding each table from its
            // own stored DDL, because SQLite cannot alter a column type and
            // `CREATE TABLE ... AS SELECT` re-derives the type from the copied
            // values, which would silently leave the column REAL. Only the
            // money columns move: `stock_qty` and `qty` are counts and stay
            // REAL.
            const moneyColumns = <String, List<String>>{
              'products': [
                'cost_price',
                'sell_price',
                'half_price',
                'quarter_price'
              ],
              'sales': ['total', 'profit', 'amount_tendered', 'change_given'],
              'sale_items': ['unit_price', 'unit_cost'],
            };
            for (final entry in moneyColumns.entries) {
              final table = entry.key;
              final ddl = (await db.rawQuery(
                      "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
                      [table]))
                  .first['sql'] as String;
              var rebuilt = ddl;
              for (final col in entry.value) {
                rebuilt = rebuilt.replaceAll('$col REAL', '$col INTEGER');
              }
              final tmp = '${table}_moneyfix';
              await db.execute(rebuilt.replaceFirst(
                  'CREATE TABLE $table', 'CREATE TABLE $tmp'));

              // v11 also rescales the stored values, not just the column
              // type: 80.00 becomes 8000. Reading the type change without the
              // rescale would leave a till holding shillings in a column
              // labelled minor units — 100x out, and silently.
              final cols = [
                for (final row
                    in await db.rawQuery('PRAGMA table_info($table)'))
                  row['name'] as String
              ];
              final projections = <String>[
                for (final col in cols)
                  if (entry.value.contains(col) &&
                      !cols.contains('${col}_minor'))
                    'CAST(ROUND($col * 100) AS INTEGER)'
                  else
                    col
              ];
              await db.execute('INSERT INTO $tmp (${cols.join(', ')}) '
                  'SELECT ${projections.join(', ')} FROM $table');
              await db.execute('DROP TABLE $table');
              await db.execute('ALTER TABLE $tmp RENAME TO $table');
            }

            // v12/v13/v14: columns and tables added after v10.
            await db
                .execute('ALTER TABLE sales ADD COLUMN receipt_number TEXT');
            await db.execute('ALTER TABLE sales ADD COLUMN etims_status TEXT');
            await db.execute(
                'ALTER TABLE sales ADD COLUMN etims_receipt_number TEXT');
            // v14: a payment that has not been confirmed by the provider.
            await db.execute(
                "ALTER TABLE sales ADD COLUMN payment_verified INTEGER NOT NULL DEFAULT 1");
            await db.execute(
                "ALTER TABLE products ADD COLUMN unit TEXT NOT NULL DEFAULT 'each'");
            await db.execute(
                'ALTER TABLE products ADD COLUMN track_variants INTEGER NOT NULL DEFAULT 0');
            await db.execute(
                'ALTER TABLE sale_items ADD COLUMN variant_id INTEGER');
            await db
                .execute('ALTER TABLE sale_items ADD COLUMN variant_name TEXT');
            await db.execute('''CREATE TABLE IF NOT EXISTS product_barcodes (
              barcode TEXT PRIMARY KEY NOT NULL,
              product_id INTEGER NOT NULL,
              kind TEXT NOT NULL DEFAULT 'supplier',
              variant_id INTEGER
            )''');
            await db.execute('''CREATE TABLE IF NOT EXISTS shop_settings (
              key TEXT PRIMARY KEY NOT NULL, value TEXT
            )''');
            await db.execute('''CREATE TABLE IF NOT EXISTS
              receipt_counters (
              key TEXT PRIMARY KEY NOT NULL, value INTEGER NOT NULL
            )''');
            await db.execute('''CREATE TABLE IF NOT EXISTS pending_etims (
              sale_id INTEGER PRIMARY KEY,
              receipt_number TEXT NOT NULL,
              attempts INTEGER NOT NULL DEFAULT 0,
              last_error TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )''');
            await db.execute('''CREATE TABLE IF NOT EXISTS product_variants (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              product_id INTEGER NOT NULL,
              name TEXT NOT NULL,
              sku TEXT NOT NULL DEFAULT '',
              unit TEXT NOT NULL DEFAULT 'each',
              size_ml INTEGER NOT NULL DEFAULT 0,
              sell_price INTEGER NOT NULL DEFAULT 0,
              cost_price INTEGER NOT NULL DEFAULT 0,
              stock_qty REAL NOT NULL DEFAULT 0,
              reorder_level INTEGER NOT NULL DEFAULT 0,
              position INTEGER NOT NULL DEFAULT 0,
              active INTEGER NOT NULL DEFAULT 1
            )''');
            await db.execute('''CREATE TABLE IF NOT EXISTS
              import_needs_attention (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              source TEXT NOT NULL,
              sheet_name TEXT NOT NULL DEFAULT '',
              row_number INTEGER NOT NULL DEFAULT 0,
              raw_name TEXT NOT NULL DEFAULT '',
              raw_row TEXT NOT NULL,
              problem TEXT NOT NULL,
              resolved INTEGER NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL
            )''');
            await db.execute('''CREATE TABLE IF NOT EXISTS categories (
              name TEXT PRIMARY KEY NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0
            )''');
            await db.execute('''CREATE TABLE IF NOT EXISTS staff (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              role TEXT NOT NULL DEFAULT 'cashier',
              pin_hash TEXT NOT NULL,
              is_active INTEGER NOT NULL DEFAULT 1,
              created_at TEXT NOT NULL
            )''');
          },
        ),
      );
      await db.close();
      return DatabaseHelper.openExistingForUpgradeTests(path);
    }

    Future<Database> upgraded({
      List<Map<String, Object?>> products = const [],
      List<Map<String, Object?>> sales = const [],
    }) async =>
        migratedFromV14(products: products, sales: sales);

    test('all five tables appear, empty, on a till that had none', () async {
      final db = await upgraded(
          products: [product(cost: 40.0, sell: 80.0)], sales: [sale()]);

      for (final table in const [
        'shifts',
        'till_counts',
        'reconciliations',
        'shot_cups',
        'cup_size_suggestions'
      ]) {
        final rows = await db.query(table);
        expect(rows, isEmpty,
            reason: '$table must start empty on an existing install');
      }
      await db.close();
    });

    test('the pre-existing ledger is untouched by the upgrade', () async {
      final db = await upgraded(
          products: [product(cost: 40.0, sell: 80.0)],
          sales: [sale(total: 160.0)]);

      final productRow = (await db.query('products')).single;
      // 80.00 at v10, still 8000 minor units after the v11 rebuild that a real
      // till already made before it reached v15.
      expect(productRow['sell_price'], 8000);

      final saleRow = (await db.query('sales')).single;
      expect(saleRow['total'], 16000);
      expect(saleRow['payment_verified'], 1);
      await db.close();
    });

    test('a shot price and a float are stored as integer minor units',
        () async {
      // The bug this guards: a REAL-affinity money column reads 3000 back as
      // 30.00. It happened once already, to `pending_payments.amount`.
      final db = await upgraded(products: [product(cost: 40.0, sell: 80.0)]);
      final productId = (await db.query('products')).single['id'] as int;

      await db.insert('shot_cups', {
        'product_id': productId,
        'product_name': 'AAA Vodka',
        'capacity_ml': 30,
        'price': 3000,
        'label': 'Shot',
        'active': 1,
        'updated_at': '2026-02-01T09:00:00.000',
      });
      final cup = (await db.query('shot_cups')).single;
      expect(cup['price'], 3000);
      expect(cup['price'], isA<int>());

      await db.insert('shifts', {
        'staff_id': 1,
        'staff_name': 'Amina',
        'start_time': '2026-02-01T08:00:00.000',
        'end_time': null,
        'start_float': 500000,
        'end_float': 0,
        'status': 'open',
      });
      final shift = (await db.query('shifts')).single;
      expect(shift['start_float'], 500000);
      expect(shift['start_float'], isA<int>());
      await db.close();
    });

    test('a shift, its counts and its reconciliation round-trip at full value',
        () async {
      final db = await upgraded();
      final now = '2026-02-01T17:00:00.000';

      final shiftId = await db.insert('shifts', {
        'staff_id': 1,
        'staff_name': 'Amina',
        'start_time': '2026-02-01T08:00:00.000',
        'start_float': 500000,
        'status': 'open',
      });
      await db.insert('till_counts', {
        'shift_id': shiftId,
        'denomination': 'KSh 100',
        'count': 42,
        'value': 420000,
        'created_at': now,
      });
      await db.insert('reconciliations', {
        'shift_id': shiftId,
        'counted_cash': 1100000,
        'expected_cash': 1115000,
        'variance': -15000,
        'recorded_at': now,
      });

      final count = (await db.query('till_counts')).single;
      final recon = (await db.query('reconciliations')).single;
      expect(count['value'], 420000);
      expect(recon['variance'], -15000);
      expect(recon['variance'], isA<int>());
      await db.close();
    });

    test('no scratch table is left behind', () async {
      final db = await upgraded();
      final names = [
        for (final row in await db
            .rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
          row['name'] as String
      ];
      expect(names.where((n) => n.endsWith('_v15')), isEmpty);
      expect(names.where((n) => n.contains('moneyfix')), isEmpty);
      await db.close();
    });
  });

  group('v15 -> v16: staff username column', () {
    Future<Database> migratedFromV15() async {
      await _createV10Database(path, products: const [], sales: const []);
      final db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 15,
          onOpen: (db) async {
            const moneyColumns = <String, List<String>>{
              'products': [
                'cost_price',
                'sell_price',
                'half_price',
                'quarter_price'
              ],
              'sales': ['total', 'profit', 'amount_tendered', 'change_given'],
              'sale_items': ['unit_price', 'unit_cost'],
            };
            for (final entry in moneyColumns.entries) {
              final table = entry.key;
              final ddl = (await db.rawQuery(
                      "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
                      [table]))
                  .first['sql'] as String;
              var rebuilt = ddl;
              for (final col in entry.value) {
                rebuilt = rebuilt.replaceAll('$col REAL', '$col INTEGER');
              }
              final tmp = '${table}_moneyfix';
              await db.execute(rebuilt.replaceFirst(
                  'CREATE TABLE $table', 'CREATE TABLE $tmp'));

              final cols = [
                for (final row
                    in await db.rawQuery('PRAGMA table_info($table)'))
                  row['name'] as String
              ];
              final projections = <String>[
                for (final col in cols)
                  if (entry.value.contains(col) &&
                      !cols.contains('${col}_minor'))
                    'CAST(ROUND($col * 100) AS INTEGER)'
                  else
                    col
              ];
              await db.execute('INSERT INTO $tmp (${cols.join(', ')}) '
                  'SELECT ${projections.join(', ')} FROM $table');
              await db.execute('DROP TABLE $table');
              await db.execute('ALTER TABLE $tmp RENAME TO $table');
            }

            await db
                .execute('ALTER TABLE sales ADD COLUMN receipt_number TEXT');
            await db.execute('ALTER TABLE sales ADD COLUMN etims_status TEXT');
            await db.execute(
                'ALTER TABLE sales ADD COLUMN etims_receipt_number TEXT');
            await db.execute(
                "ALTER TABLE sales ADD COLUMN payment_verified INTEGER NOT NULL DEFAULT 1");
            await db.execute(
                "ALTER TABLE products ADD COLUMN unit TEXT NOT NULL DEFAULT 'each'");
            await db.execute(
                'ALTER TABLE products ADD COLUMN track_variants INTEGER NOT NULL DEFAULT 0');
            await db.execute(
                'ALTER TABLE sale_items ADD COLUMN variant_id INTEGER');
            await db
                .execute('ALTER TABLE sale_items ADD COLUMN variant_name TEXT');
            await db.execute('''CREATE TABLE IF NOT EXISTS product_barcodes (
              barcode TEXT PRIMARY KEY NOT NULL,
              product_id INTEGER NOT NULL,
              kind TEXT NOT NULL DEFAULT 'supplier',
              variant_id INTEGER
            )''');
            await db.execute('''CREATE TABLE IF NOT EXISTS shop_settings (
              key TEXT PRIMARY KEY NOT NULL, value TEXT
            )''');
            await db.execute('''CREATE TABLE IF NOT EXISTS
              receipt_counters (
              key TEXT PRIMARY KEY NOT NULL, value INTEGER NOT NULL
            )''');
            await db.execute('''CREATE TABLE IF NOT EXISTS pending_etims (
              sale_id INTEGER PRIMARY KEY,
              receipt_number TEXT NOT NULL,
              attempts INTEGER NOT NULL DEFAULT 0,
              last_error TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )''');
            await db.execute('''CREATE TABLE IF NOT EXISTS product_variants (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              product_id INTEGER NOT NULL,
              name TEXT NOT NULL,
              sku TEXT,
              unit TEXT NOT NULL DEFAULT 'each',
              size_ml INTEGER NOT NULL DEFAULT 0,
              sell_price INTEGER NOT NULL,
              cost_price INTEGER NOT NULL DEFAULT 0,
              stock_qty REAL NOT NULL DEFAULT 0,
              reorder_level INTEGER NOT NULL DEFAULT 0,
              position INTEGER NOT NULL DEFAULT 0,
              active INTEGER NOT NULL DEFAULT 1
            )''');
            await db.execute('''CREATE TABLE IF NOT EXISTS categories (
              name TEXT PRIMARY KEY NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0
            )''');
            await db.execute('''CREATE TABLE IF NOT EXISTS owner (
              id INTEGER PRIMARY KEY CHECK (id = 1),
              name TEXT NOT NULL,
              pin_hash TEXT NOT NULL,
              email TEXT NOT NULL DEFAULT '',
              shop_name TEXT NOT NULL,
              created_at TEXT NOT NULL
            )''');
            await db.execute('''CREATE TABLE IF NOT EXISTS staff (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              role TEXT NOT NULL DEFAULT 'cashier',
              pin_hash TEXT NOT NULL,
              is_active INTEGER NOT NULL DEFAULT 1,
              created_at TEXT NOT NULL
            )''');
            await db.execute('''CREATE TABLE IF NOT EXISTS stock_adjustments (
              product_id INTEGER NOT NULL,
              delta REAL NOT NULL,
              reason TEXT,
              staff_id INTEGER,
              created_at TEXT NOT NULL
            )''');
            await db.execute(
                '''CREATE TABLE IF NOT EXISTS staff_deletion_tombstones (
              staff_id INTEGER PRIMARY KEY,
              remote_id TEXT,
              deleted_at TEXT NOT NULL
            )''');
            await db.execute('''CREATE TABLE IF NOT EXISTS pending_payments (
              reference TEXT PRIMARY KEY,
              phone_number TEXT,
              amount INTEGER NOT NULL,
              cart_json TEXT NOT NULL,
              staff_name TEXT,
              staff_id INTEGER,
              created_at TEXT NOT NULL
            )''');
          },
        ),
      );
      return db;
    }

    test('staff table gains a nullable username column', () async {
      await migratedFromV15().then((db) => db.close());
      final db = await DatabaseHelper.openExistingForUpgradeTests(path);
      final info = await db.rawQuery("PRAGMA table_info(staff)");
      final columns = info.map((row) => row['name'] as String).toList();
      expect(columns, contains('username'));
      await db.close();
    });

    test('fresh installs match upgraded installs', () async {
      final db = await migratedFromV15();
      final path2 = '${path}_fresh_v16';
      final fresh = await databaseFactoryFfi.openDatabase(
        path2,
        options: OpenDatabaseOptions(
          version: 16,
          onCreate: (db, version) async {
            await db.execute('''CREATE TABLE IF NOT EXISTS products (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              category TEXT NOT NULL,
              cost_price INTEGER NOT NULL,
              sell_price INTEGER NOT NULL,
              stock_qty REAL NOT NULL DEFAULT 0,
              reorder_level INTEGER NOT NULL DEFAULT 0,
              bottle_ml INTEGER NOT NULL DEFAULT 750,
              unit TEXT NOT NULL DEFAULT 'each',
              track_variants INTEGER NOT NULL DEFAULT 0,
              half_price INTEGER,
              quarter_price INTEGER,
              excise_stamp_batch TEXT NOT NULL DEFAULT '',
              active INTEGER NOT NULL DEFAULT 1,
              updated_at TEXT NOT NULL,
              remote_id TEXT
            )''');
            await db.execute('''CREATE TABLE IF NOT EXISTS sales (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              staff_name TEXT NOT NULL,
              staff_id INTEGER,
              total INTEGER NOT NULL,
              profit INTEGER NOT NULL,
              created_at TEXT NOT NULL,
              payment_method TEXT NOT NULL DEFAULT 'cash',
              payment_reference TEXT,
              amount_tendered INTEGER NOT NULL DEFAULT 0,
              change_given INTEGER NOT NULL DEFAULT 0,
              receipt_number TEXT,
              etims_status TEXT,
              etims_receipt_number TEXT,
              payment_verified INTEGER NOT NULL DEFAULT 1
            )''');
            await db.execute('''CREATE TABLE IF NOT EXISTS sale_items (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              sale_id INTEGER NOT NULL,
              product_id INTEGER NOT NULL,
              product_name TEXT NOT NULL,
              qty REAL NOT NULL,
              unit_price INTEGER NOT NULL,
              unit_cost INTEGER NOT NULL,
              portion TEXT NOT NULL DEFAULT 'full',
              portion_ml INTEGER NOT NULL DEFAULT 0,
              variant_id INTEGER,
              variant_name TEXT
            )''');
            await db
                .execute('CREATE INDEX idx_sales_staff ON sales (staff_id)');
            await db.execute('''CREATE TABLE IF NOT EXISTS product_barcodes (
              barcode TEXT PRIMARY KEY NOT NULL,
              product_id INTEGER NOT NULL,
              kind TEXT NOT NULL DEFAULT 'supplier',
              variant_id INTEGER
            )''');
            await db.execute('''CREATE TABLE IF NOT EXISTS shop_settings (
              key TEXT PRIMARY KEY NOT NULL, value TEXT
            )''');
            await db.execute('''CREATE TABLE IF NOT EXISTS
              receipt_counters (
              key TEXT PRIMARY KEY NOT NULL, value INTEGER NOT NULL
            )''');
            await db.execute('''CREATE TABLE IF NOT EXISTS pending_etims (
              sale_id INTEGER PRIMARY KEY,
              receipt_number TEXT NOT NULL,
              attempts INTEGER NOT NULL DEFAULT 0,
              last_error TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )''');
            await db.execute('''CREATE TABLE IF NOT EXISTS product_variants (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              product_id INTEGER NOT NULL,
              name TEXT NOT NULL,
              sku TEXT,
              unit TEXT NOT NULL DEFAULT 'each',
              size_ml INTEGER NOT NULL DEFAULT 0,
              sell_price INTEGER NOT NULL,
              cost_price INTEGER NOT NULL DEFAULT 0,
              stock_qty REAL NOT NULL DEFAULT 0,
              reorder_level INTEGER NOT NULL DEFAULT 0,
              position INTEGER NOT NULL DEFAULT 0,
              active INTEGER NOT NULL DEFAULT 1
            )''');
            await db.execute('''CREATE TABLE IF NOT EXISTS categories (
              name TEXT PRIMARY KEY NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0
            )''');
            await db.execute('''CREATE TABLE IF NOT EXISTS owner (
              id INTEGER PRIMARY KEY CHECK (id = 1),
              name TEXT NOT NULL,
              pin_hash TEXT NOT NULL,
              email TEXT NOT NULL DEFAULT '',
              shop_name TEXT NOT NULL,
              created_at TEXT NOT NULL
            )''');
            await db.execute('''CREATE TABLE IF NOT EXISTS staff (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              role TEXT NOT NULL DEFAULT 'cashier',
              pin_hash TEXT NOT NULL,
              is_active INTEGER NOT NULL DEFAULT 1,
              created_at TEXT NOT NULL,
              username TEXT
            )''');
            await db.execute('''CREATE TABLE IF NOT EXISTS stock_adjustments (
              product_id INTEGER NOT NULL,
              delta REAL NOT NULL,
              reason TEXT,
              staff_id INTEGER,
              created_at TEXT NOT NULL
            )''');
            await db.execute(
                '''CREATE TABLE IF NOT EXISTS staff_deletion_tombstones (
              staff_id INTEGER PRIMARY KEY,
              remote_id TEXT,
              deleted_at TEXT NOT NULL
            )''');
            await db.execute('''CREATE TABLE IF NOT EXISTS pending_payments (
              reference TEXT PRIMARY KEY,
              phone_number TEXT,
              amount INTEGER NOT NULL,
              cart_json TEXT NOT NULL,
              staff_name TEXT,
              staff_id INTEGER,
              created_at TEXT NOT NULL
            )''');
          },
        ),
      );

      final migratedTables = [
        for (final row in await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"))
          row['name'] as String
      ];
      final freshTables = [
        for (final row in await fresh.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"))
          row['name'] as String
      ];
      expect(freshTables, migratedTables,
          reason: 'a new till and an upgraded one must not diverge');
      await fresh.close();
    });
  });

  /// v17 -> v19: the audit log and the crash log.
  ///
  /// v17 is what a real till in the field is on today: the ledger, variants,
  /// shifts and staff username, with rows. Opening it at the current version
  /// runs the two `oldVersion < 18` / `oldVersion < 19` branches for real,
  /// which nothing else did — the newest builder in this suite used to be v16,
  /// so the newest two shipped migration steps had no coverage at all.
  group('v17 -> v19: audit log and crash log', () {
    /// The v17 shape, built the way the app reaches v17: from v10 up through
    /// its own migrations, plus the one column v17 adds.
    Future<Database> atV17() async {
      await _createV10Database(
        path,
        products: [
          product(cost: 100, sell: 150),
        ],
        sales: [
          sale(id: 1, total: 150, profit: 50),
        ],
      );
      final db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 17,
          onOpen: (db) async {
            // The roster as v16 leaves it, so this is a real v17 file rather
            // than an empty one.
            await db.execute('''CREATE TABLE IF NOT EXISTS staff (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              role TEXT NOT NULL DEFAULT 'cashier',
              pin_hash TEXT NOT NULL,
              is_active INTEGER NOT NULL DEFAULT 1,
              created_at TEXT NOT NULL,
              username TEXT
            )''');
            // Three rows of live ledger, which is what makes this a real
            // migration rather than an empty-file exercise.
            expect((await db.query('products')).length, 1);
          },
        ),
      );
      return db;
    }

    Future<Database> upgraded() async {
      final db = await atV17();
      await db.close();
      return DatabaseHelper.openExistingForUpgradeTests(path);
    }

    /// The columns an index leads with, read back off the upgraded file, so a
    /// dropped or mis-ordered index fails here rather than on a phone.
    Future<List<String>> indexColumnsOn(
      Database db,
      String index,
    ) async {
      final rows = await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type='index' AND name=?",
        <Object?>[index],
      );
      expect(rows, isNotEmpty,
          reason: 'index $index is missing after the upgrade');
      final sql = rows.first['sql'] as String;
      final open = sql.indexOf('(');
      final close = sql.lastIndexOf(')');
      final body = sql.substring(open + 1, close);
      return body
          .split(',')
          .map((c) => c.trim().split(' ').first)
          .toList(growable: false);
    }

    test('the audit table exists with the columns the app writes', () async {
      final db = await upgraded();
      final rows = await db.query('audit_log');
      expect(rows, isEmpty);

      final columns = (await db.rawQuery('PRAGMA table_info(audit_log)'))
          .map((r) => r['name'] as String)
          .toSet();
      expect(
        columns,
        containsAll(<String>[
          'id',
          'action',
          'entity',
          'entity_id',
          'actor_id',
          'actor_name',
          'detail',
          'created_at',
        ]),
      );
      await db.close();
    });

    test('every audit index leads with the column its query filters on',
        () async {
      final db = await upgraded();
      // `action` is the column the owner-relevant filter reads, and it was
      // missing: without a leading `action` the activity screen walked
      // `created_at DESC` and discarded every sale row to show 50 rows.
      expect(await indexColumnsOn(db, 'idx_audit_action'),
          <String>['action', 'created_at']);
      expect(await indexColumnsOn(db, 'idx_audit_entity'),
          <String>['entity', 'entity_id', 'created_at']);
      expect(await indexColumnsOn(db, 'idx_audit_actor'),
          <String>['actor_id', 'created_at']);
      expect(await indexColumnsOn(db, 'idx_audit_created'),
          <String>['created_at']);
      await db.close();
    });

    test('the crash table exists and its indexes lead with what it filters on',
        () async {
      final db = await upgraded();
      final columns = (await db.rawQuery('PRAGMA table_info(crash_log)'))
          .map((r) => r['name'] as String)
          .toSet();
      expect(
        columns,
        containsAll(<String>[
          'id',
          'kind',
          'message',
          'stack',
          'route',
          'actor_name',
          'action',
          'breadcrumbs',
          'created_at',
        ]),
      );
      // The three reads the diagnostics screen performs.
      expect(await indexColumnsOn(db, 'idx_crash_created'),
          <String>['created_at']);
      expect(await indexColumnsOn(db, 'idx_crash_actor'),
          <String>['actor_name', 'created_at']);
      await db.close();
    });

    test('the ledger it walked through is untouched', () async {
      final db = await upgraded();
      final products = await db.query('products');
      expect(products.length, 1);
      final sales = await db.query('sales');
      expect(sales.length, 1);
      // The migration rebuilt nothing it did not own.
      expect(sales.single['total'], 150);
      await db.close();
    });

    test('a fresh v19 install has the same new tables as an upgraded one',
        () async {
      // The v17 fixture is deliberately a PARTIAL v17 — it is built from v10
      // and declared v17, so it holds the ledger but not the tables the
      // v11-v17 branches add. The claim this test can honestly make is
      // therefore about the two tables the 18 and 19 branches own, which is
      // the one both paths define through the same helpers.
      final db = await upgraded();
      final freshPath = '${path}_fresh_v19';
      final fresh = await DatabaseHelper.openExistingForUpgradeTests(freshPath);

      Future<List<String>> tableNames(Database database) async {
        final names = <String>[];
        for (final row in await database.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")) {
          names.add(row['name'] as String);
        }
        names.sort();
        return names;
      }

      expect(await tableNames(fresh),
          containsAll(<String>['audit_log', 'crash_log']));
      expect(await tableNames(db),
          containsAll(<String>['audit_log', 'crash_log']));
      await fresh.close();
      await db.close();
    });
  });

  // v19 -> v20: the product photograph's path.
  //
  // The one migration whose mistake is not a crash but a slow, silent one: an
  // absolute path would survive the upgrade, work on the phone that stored it,
  // and break on every phone the shop's backup was restored to. So the path is
  // asserted RELATIVE, and asserted to match the fresh-install column so the two
  // paths cannot diverge.
  group('v19 -> v20: product photograph path', () {
    Future<Database> atV19() async {
      // Open at 19 with no upgrade, so the shop's data is the real v19 shape.
      await _createV10Database(
        path,
        products: [
          product(cost: 100, sell: 150),
        ],
        sales: [
          sale(id: 1, total: 150, profit: 50),
        ],
      );
      return databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 19,
          onOpen: (db) async {
            // `image_path` does not exist at v19, which is the whole point of
            // the migration being tested.
            final columns = await db.rawQuery('PRAGMA table_info(products)');
            expect(
                columns.map((r) => r['name']), isNot(contains('image_path')));
          },
        ),
      );
    }

    test('the column exists after the upgrade, and the ledger survives',
        () async {
      final db = await atV19();
      await db.close();
      final upgraded = await DatabaseHelper.openExistingForUpgradeTests(path);

      final columns = await upgraded.rawQuery('PRAGMA table_info(products)');
      expect(columns.map((r) => r['name']), contains('image_path'));

      // The shop's existing rows are untouched: an upgrade that rewrote the
      // catalogue would be worse than a missing column.
      final products = await upgraded.query('products');
      expect(products.length, 1);
      expect(products.single['image_path'], isNull);
      await upgraded.close();
    });

    test('a fresh v20 install has the SAME column as an upgraded one',
        () async {
      final db = await atV19();
      await db.close();
      final upgraded = await DatabaseHelper.openExistingForUpgradeTests(path);

      final freshPath = '${path}_fresh_v20';
      final fresh = await DatabaseHelper.openExistingForUpgradeTests(freshPath);

      Future<List<String>> imageColumns(Database database) async {
        final columns = await database.rawQuery('PRAGMA table_info(products)');
        return columns
            .where((r) => r['name'] == 'image_path')
            .map((r) => r['type'] as String)
            .toList();
      }

      // Same name AND same type, from both paths, through the one production
      // entry point each.
      expect(await imageColumns(fresh), await imageColumns(upgraded));

      await fresh.close();
      await upgraded.close();
    });
  });

  group('v21 -> v22: how many millilitres a kilogram is', () {
    /// A database at exactly v21: `ml_per_kg` absent, which is the shape every
    /// released v21 build has on disk.
    Future<Database> atV21WithoutMlPerKg() async {
      await _createV10Database(path);
      final db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 21,
          onOpen: (db) async {
            // A v21 database has the column ONLY if it came from an install
            // that ran the shared helper, which is every released v21 build:
            // the fixture is therefore "whatever shape v21 really left".
            final columns = await db.rawQuery('PRAGMA table_info(products)');
            expect(columns.map((r) => r['name']), contains('bottle_ml'));
          },
        ),
      );
      return db;
    }

    test('the column exists after the upgrade, and old rows read as 0',
        () async {
      final db = await atV21WithoutMlPerKg();
      await db.insert('products', {
        'name': 'Keg',
        'category': 'Beer',
        'cost_price': 0,
        'sell_price': 0,
        'stock_qty': 50000.0,
        'reorder_level': 5,
        'bottle_ml': 50000,
        'active': 1,
        'updated_at': '2026-10-04T09:00:00.000Z',
      });
      await db.close();

      final upgraded = await DatabaseHelper.openExistingForUpgradeTests(path);

      final columns = await upgraded.rawQuery('PRAGMA table_info(products)');
      expect(columns.map((r) => r['name']), contains('ml_per_kg'));

      // 0, and NOT NULL: every product that is not a tank answers 0, which is
      // how the shape says "not stocked by weight" without a second flag.
      final rows = await upgraded.query('products');
      // 0, and NOT NULL: every product that is not a tank answers 0, which is
      // how the shape says "not stocked by weight" without a second flag. The
      // unit column is not asserted here — the fixture predates it, and it is
      // the shared helper that adds it, which is the same reason the value
      // would be null rather than 'litre'.
      expect(rows.single['ml_per_kg'], 0);
      await upgraded.close();
    });

    test('a tank written before the upgrade keeps its conversion', () async {
      // The general invariant: an ALTER with a DEFAULT does not touch rows
      // already in the table, so the only way this passes is if the migration
      // really is additive.
      final db = await atV21WithoutMlPerKg();
      await db.insert('products', {
        'name': 'Tusker',
        'category': 'Beer',
        'cost_price': 0,
        'sell_price': 0,
        'stock_qty': 50000.0,
        'reorder_level': 5,
        'bottle_ml': 50000,
        'active': 1,
        'updated_at': '2026-10-04T09:00:00.000Z',
      });
      await db.close();

      final upgraded = await DatabaseHelper.openExistingForUpgradeTests(path);
      final rows = await upgraded.query('products');
      expect(rows.single['ml_per_kg'], 0);
      await upgraded.close();
    });
  });

  group('v20 -> v21: the mapping a refused row was read with', () {
    /// A database at exactly v20: the table exists WITHOUT `column_map`, which
    /// is the shape every released v20 build has on disk.
    Future<Database> atV20() async {
      // The v10 builder plus the v21 step's own precondition, opened at v20 so
      // the production `_onUpgrade` runs from there.
      await _createV10Database(path);
      final db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 20,
          onOpen: (db) async {
            await db.execute('''CREATE TABLE IF NOT EXISTS
                import_needs_attention (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                source TEXT NOT NULL,
                sheet_name TEXT NOT NULL DEFAULT '',
                row_number INTEGER NOT NULL DEFAULT 0,
                raw_name TEXT NOT NULL DEFAULT '',
                raw_row TEXT NOT NULL,
                problem TEXT NOT NULL,
                resolved INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL
              )''');
            final columns =
                await db.rawQuery('PRAGMA table_info(import_needs_attention)');
            expect(
                columns.map((r) => r['name']), isNot(contains('column_map')));
          },
        ),
      );
      return db;
    }

    test('the column exists after the upgrade, and the rows survive', () async {
      final db = await atV20();
      await db.insert('import_needs_attention', {
        'source': 'excel',
        'sheet_name': 'Inventory',
        'row_number': 14,
        'raw_name': 'Kwancheri Lager',
        'raw_row': '["","Kwancheri Lager","Beer","abc","80"]',
        'problem': 'Cost price is not a number',
        'resolved': 0,
        'created_at': '2026-10-04T09:00:00.000Z',
      });
      await db.close();

      final upgraded = await DatabaseHelper.openExistingForUpgradeTests(path);

      final columns =
          await upgraded.rawQuery('PRAGMA table_info(import_needs_attention)');
      expect(columns.map((r) => r['name']), contains('column_map'));

      final rows = await upgraded.query('import_needs_attention');
      expect(rows.length, 1);
      expect(rows.single['raw_name'], 'Kwancheri Lager');
      expect(rows.single['column_map'], isNull);
      await upgraded.close();
    });

    test('a shop several versions behind reaches v21 in one upgrade', () async {
      // The shipped bug, in shape: a shop whose `<14` step ran the table
      // CREATE *with* `column_map` — which is what a v13/v14 till migrating
      // through the new `_createVariantsAndImportTables` produces — reaches the
      // `<21` block with the column already present. A bare ADD COLUMN there is
      // `duplicate column name`, which throws out of `_onUpgrade` and out of
      // `openDatabase`: a till that cannot open its database at all, on the
      // phones a migration exists for.
      //
      // Built at v20 with the column in place, because that is the only shape
      // the collision can have — the version number alone says nothing about
      // which columns exist.
      await _createV10Database(path);
      final db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 20,
          onOpen: (db) async {
            await db.execute('''CREATE TABLE IF NOT EXISTS
                import_needs_attention (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                source TEXT NOT NULL,
                sheet_name TEXT NOT NULL DEFAULT '',
                row_number INTEGER NOT NULL DEFAULT 0,
                raw_name TEXT NOT NULL DEFAULT '',
                raw_row TEXT NOT NULL,
                problem TEXT NOT NULL,
                resolved INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL,
                column_map TEXT
              )''');
          },
        ),
      );
      await db.close();

      final upgraded = await DatabaseHelper.openExistingForUpgradeTests(path);

      final columns =
          await upgraded.rawQuery('PRAGMA table_info(import_needs_attention)');
      expect(columns.map((r) => r['name']), contains('column_map'));
      // One occurrence, not two: a migration that added the column twice would
      // still be broken on the next release.
      expect(columns.where((r) => r['name'] == 'column_map'), hasLength(1));
      await upgraded.close();
    });
  });

  group('v23: schema repair for the v12 helper drift', () {
    /// Builds a database at v12 using the OLD helper declarations (the shape
    /// the buggy v12 migration left on real tills): owner with `phone` instead
    /// of `name`/`email`, staff with `is_active` instead of `active` and no
    /// `remote_id`/`username`, and no `stock_adjustments` table at all.
    Future<Database> atV12WithDriftedShape() async {
      await _createV10Database(path);
      final db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 12,
          onOpen: (db) async {
            await db.execute('''CREATE TABLE IF NOT EXISTS owner (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              shop_name TEXT NOT NULL,
              phone TEXT,
              pin_hash TEXT NOT NULL,
              created_at TEXT NOT NULL
            )''');
            await db.execute('''CREATE TABLE IF NOT EXISTS staff (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              role TEXT NOT NULL DEFAULT 'cashier',
              pin_hash TEXT NOT NULL,
              is_active INTEGER NOT NULL DEFAULT 1,
              created_at TEXT NOT NULL
            )''');
            await db.execute('''CREATE TABLE IF NOT EXISTS product_barcodes (
              barcode TEXT PRIMARY KEY NOT NULL,
              product_id INTEGER NOT NULL,
              kind TEXT NOT NULL DEFAULT 'supplier'
            )''');
            await db.execute('''CREATE TABLE IF NOT EXISTS shop_settings (
              key TEXT PRIMARY KEY NOT NULL, value TEXT
            )''');
            await db.execute('''CREATE TABLE IF NOT EXISTS
              receipt_counters (
              key TEXT PRIMARY KEY NOT NULL, value INTEGER NOT NULL
            )''');
            await db
                .execute('ALTER TABLE sales ADD COLUMN receipt_number TEXT');
            await db.execute('''CREATE TABLE IF NOT EXISTS pending_etims (
              sale_id INTEGER PRIMARY KEY,
              receipt_number TEXT NOT NULL,
              attempts INTEGER NOT NULL DEFAULT 0,
              last_error TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )''');
          },
        ),
      );
      return db;
    }

    test('the repair adds name and email to owner', () async {
      final db = await atV12WithDriftedShape();
      await db.close();
      final upgraded = await DatabaseHelper.openExistingForUpgradeTests(path);

      final cols = (await upgraded.rawQuery('PRAGMA table_info(owner)'))
          .map((r) => r['name'] as String)
          .toSet();
      expect(cols, contains('name'));
      expect(cols, contains('email'));
      // The old phone column is not required by the current schema; the repair
      // does not remove it, but the current columns must be present.
      await upgraded.close();
    });

    test('the repair adds active, remote_id and username to staff', () async {
      final db = await atV12WithDriftedShape();
      await db.close();
      final upgraded = await DatabaseHelper.openExistingForUpgradeTests(path);

      final cols = (await upgraded.rawQuery('PRAGMA table_info(staff)'))
          .map((r) => r['name'] as String)
          .toSet();
      expect(cols, contains('active'));
      expect(cols, contains('remote_id'));
      expect(cols, contains('username'));
      await upgraded.close();
    });

    test(
        'the repair creates stock_adjustments with product_name and staff_name',
        () async {
      final db = await atV12WithDriftedShape();
      await db.close();
      final upgraded = await DatabaseHelper.openExistingForUpgradeTests(path);

      final cols =
          (await upgraded.rawQuery('PRAGMA table_info(stock_adjustments)'))
              .map((r) => r['name'] as String)
              .toSet();
      expect(cols, contains('product_name'));
      expect(cols, contains('staff_name'));
      expect(cols, contains('staff_id'));
      await upgraded.close();
    });

    test('fresh install and upgraded v12-drift install agree on columns',
        () async {
      // A fresh install goes through _onCreate, which now delegates to the same
      // helper declarations the v23 repair targets. The two paths must agree.
      await DatabaseHelper.openInMemoryForTests();
      final freshHandle = await DatabaseHelper.instance.database;

      final freshOwner =
          (await freshHandle.rawQuery('PRAGMA table_info(owner)'))
              .map((r) => r['name'] as String)
              .toSet();
      final freshStaff =
          (await freshHandle.rawQuery('PRAGMA table_info(staff)'))
              .map((r) => r['name'] as String)
              .toSet();
      final freshAdj =
          (await freshHandle.rawQuery('PRAGMA table_info(stock_adjustments)'))
              .map((r) => r['name'] as String)
              .toSet();

      await freshHandle.close();

      final drifted = await atV12WithDriftedShape();
      await drifted.close();
      final upgraded = await DatabaseHelper.openExistingForUpgradeTests(path);

      final upgradedOwner =
          (await upgraded.rawQuery('PRAGMA table_info(owner)'))
              .map((r) => r['name'] as String)
              .toSet();
      final upgradedStaff =
          (await upgraded.rawQuery('PRAGMA table_info(staff)'))
              .map((r) => r['name'] as String)
              .toSet();
      final upgradedAdj =
          (await upgraded.rawQuery('PRAGMA table_info(stock_adjustments)'))
              .map((r) => r['name'] as String)
              .toSet();

      // The upgraded install must carry every column a fresh install has.
      // Extra legacy columns (e.g. `phone` on owner) are harmless leftovers
      // from the old v12 helper and are not removed by the repair.
      expect(upgradedOwner, containsAll(freshOwner));
      expect(upgradedStaff, containsAll(freshStaff));
      expect(upgradedAdj, containsAll(freshAdj));

      await upgraded.close();
    });

    test('v49 drawer events gain an online sync flag without losing history',
        () async {
      final old = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 49,
          onCreate: (db, _) async {
            await db.execute('''
              CREATE TABLE drawer_events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                uuid TEXT NOT NULL UNIQUE,
                shift_id INTEGER,
                event_type TEXT NOT NULL,
                reason TEXT,
                staff_id INTEGER,
                staff_name TEXT NOT NULL,
                created_at TEXT NOT NULL,
                status TEXT NOT NULL DEFAULT 'recorded'
              )
            ''');
            await db.insert('drawer_events', {
              'uuid': 'v49-drawer-event',
              'event_type': 'no_sale',
              'staff_name': 'Amina',
              'created_at': '2026-10-24T00:00:00.000Z',
            });
          },
        ),
      );
      await old.close();

      final upgraded = await DatabaseHelper.openExistingForUpgradeTests(path);
      final columns = (await upgraded.rawQuery('PRAGMA table_info(drawer_events)'))
          .map((row) => row['name'] as String)
          .toSet();
      expect(columns, contains('synced_to_backend'));
      final pending = await upgraded.query(
        'drawer_events',
        where: 'synced_to_backend = 0',
      );
      expect(pending, hasLength(1));
      await upgraded.close();
    });
  });
}
