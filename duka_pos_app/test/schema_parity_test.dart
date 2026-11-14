import 'package:duka_pos/data/local/database/schema.dart' as fresh_install;
import 'package:duka_pos/db/database_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A brand-new install builds its tables through `schema.dart` (each
/// repository's `createTable`), while an upgraded till and `openInMemoryForTests`
/// build them through the older definitions in `database_helper.dart`. When the
/// two disagree, code that works in every other test fails on a fresh install
/// ("table job_payments has no column named uuid").
///
/// These are the tables whose columns code actually writes. Add a table here
/// when you touch both definitions of it.
const List<String> _guardedTables = <String>[
  'jobs',
  'job_costs',
  'job_payments',
  'cost_pools',
  'cost_pool_entries',
  'sale_pool_allocations',
  'owner_transactions',
  'financial_events',
  'credit_ledger',
  'cup_size_suggestions',
  'discount_reasons',
];

Future<Map<String, List<String>>> _columnsByTable(Database db) async {
  final tables = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' "
    "AND name NOT LIKE 'sqlite_%'",
  );
  final out = <String, List<String>>{};
  for (final t in tables) {
    final name = t['name'] as String;
    final info = await db.rawQuery('PRAGMA table_info($name)');
    out[name] = info.map((c) => c['name'] as String).toList()..sort();
  }
  return out;
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('fresh-install schema matches the legacy schema for guarded tables',
      () async {
    final freshDb = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: fresh_install.onCreate,
      ),
    );
    addTearDown(freshDb.close);

    DatabaseHelper.resetForTests();
    final legacyDb = await (await DatabaseHelper.openInMemoryForTests()).database;

    final fresh = await _columnsByTable(freshDb);
    final legacy = await _columnsByTable(legacyDb);

    for (final table in _guardedTables) {
      expect(fresh[table], isNotNull, reason: '$table missing on fresh install');
      expect(legacy[table], isNotNull, reason: '$table missing in legacy path');
      expect(
        fresh[table],
        legacy[table],
        reason: '$table: fresh-install columns differ from the legacy schema',
      );
    }
  });
}
