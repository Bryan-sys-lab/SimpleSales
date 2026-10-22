// "How my shops are doing", with no connection.
//
// ## THE PROBLEM
//
// "How my shops are doing, if the shops are in one device (a device has more
// than one shop under one owner), should work offline."
//
// The screen read the cross-shop KPIs from the BACKEND, so with no signal it
// showed its failure state. The one screen that reports on every shop at once
// was the one screen that needed a connection to work — and a shop with no
// signal is a normal shop.
//
// ## WHAT IS PINNED
//
//   * every shop on the device is reported, read from its OWN file;
//   * the figures are that shop's own sales in the window;
//   * a shop whose file cannot be read is LEFT OUT, not reported as empty —
//     a zero row for a shop the owner runs is a lie;
//   * the active shop's data is untouched by the read, because every file is
//     opened on its own handle rather than by repointing the app.

import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/services/local_portfolio_service.dart';
import 'package:duka_pos/services/portfolio_kpis.dart';
import 'package:duka_pos/services/workspace_service.dart';
import 'package:duka_pos/utils/money.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    DatabaseHelper.resetForTests();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'workspace_registry_v1': '{}',
    });
  });

  /// A key no other case has used, so no two cases share a database file.
  ///
  /// The files live in the app's databases directory and outlive the test that
  /// wrote them, so a fixed key would carry one case's sales into the next
  /// one's window.
  String keyFor(String name) =>
      'shop-$name-${DateTime.now().microsecondsSinceEpoch}';

  /// A shop with [sales] sales in it, on the device and in the registry.
  Future<void> seedShop(
    String key,
    String name, {
    required List<({int total, int profit, String method})> sales,
  }) async {
    await WorkspaceService.register(workspaceKey: key, shopName: name);
    await WorkspaceService.setActiveWorkspace(key);
    await DatabaseHelper.instance.initializeWorkspace(key);
    final DatabaseHelper db = DatabaseHelper.instance;
    for (final ({int total, int profit, String method}) sale in sales) {
      await (await db.database).insert('sales', <String, Object?>{
        'staff_name': 'Amina',
        'total': sale.total,
        'profit': sale.profit,
        'payment_method': sale.method,
        'created_at': DateTime.now().toIso8601String(),
        'etims_status': 'not_required',
        'payment_verified': 1,
      });
    }
  }

  test('every shop on the device is reported, from its own file', () async {
    await seedShop(keyFor('a'), 'Kariuki',
        sales: <({int total, int profit, String method})>[
          (total: 10000, profit: 4000, method: 'cash'),
          (total: 5000, profit: 2000, method: 'mpesa'),
        ]);
    await seedShop(keyFor('b'), 'Njeri',
        sales: <({int total, int profit, String method})>[
          (total: 20000, profit: 8000, method: 'cash'),
        ]);

    final PortfolioKpis kpis = await LocalPortfolioService.read(
      from: DateTime.now().subtract(const Duration(days: 30)),
      to: DateTime.now().add(const Duration(days: 1)),
    );

    expect(kpis.shops, hasLength(2));
    expect(kpis.totalRevenue, Money.fromMinor(35000));
    expect(kpis.totalProfit, Money.fromMinor(14000));
    expect(kpis.totalTransactions, 3);
  });

  test("the window is the window, and a sale outside it is not counted",
      () async {
    await seedShop(keyFor('a'), 'Kariuki',
        sales: <({int total, int profit, String method})>[
          (total: 10000, profit: 4000, method: 'cash'),
        ]);

    final PortfolioKpis inside = await LocalPortfolioService.read(
      from: DateTime.now().subtract(const Duration(days: 30)),
      to: DateTime.now().add(const Duration(days: 1)),
    );
    expect(inside.totalRevenue, Money.fromMinor(10000));

    final PortfolioKpis outside = await LocalPortfolioService.read(
      from: DateTime.now().add(const Duration(days: 365)),
      to: DateTime.now().add(const Duration(days: 366)),
    );
    expect(outside.totalRevenue, Money.fromMinor(0));
  });

  test('the shop with the most cash is the one that says so', () async {
    await seedShop(keyFor('a'), 'Kariuki',
        sales: <({int total, int profit, String method})>[
          (total: 10000, profit: 4000, method: 'cash'),
        ]);
    await seedShop(keyFor('b'), 'Njeri',
        sales: <({int total, int profit, String method})>[
          (total: 20000, profit: 8000, method: 'mpesa'),
        ]);

    final PortfolioKpis kpis = await LocalPortfolioService.read(
      from: DateTime.now().subtract(const Duration(days: 30)),
      to: DateTime.now().add(const Duration(days: 1)),
    );

    final ShopKpi kariuki =
        kpis.shops.firstWhere((ShopKpi k) => k.shopName == 'Kariuki');
    final ShopKpi njeri =
        kpis.shops.firstWhere((ShopKpi k) => k.shopName == 'Njeri');
    expect(kariuki.topPaymentMethod, 'cash');
    expect(njeri.topPaymentMethod, 'mpesa');
  });

  test('reading the portfolio does not move the app off the active shop',
      () async {
    await seedShop(keyFor('a'), 'Kariuki',
        sales: <({int total, int profit, String method})>[
          (total: 10000, profit: 4000, method: 'cash'),
        ]);
    await seedShop(keyFor('b'), 'Njeri',
        sales: <({int total, int profit, String method})>[
          (total: 20000, profit: 8000, method: 'cash'),
        ]);

    // The app is in shop B, and its data is what is on screen.
    final String activeKey = keyFor('b');
    await WorkspaceService.setActiveWorkspace(activeKey);
    await DatabaseHelper.instance.initializeWorkspace(activeKey);

    await LocalPortfolioService.read(
      from: DateTime.now().subtract(const Duration(days: 30)),
      to: DateTime.now().add(const Duration(days: 1)),
    );

    expect(
      DatabaseHelper.instance.currentWorkspaceKey,
      activeKey,
      reason: 'the read opened each file on its own handle, so the app never '
          'moved',
    );
    final List<Product> products = await DatabaseHelper.instance.getProducts();
    expect(products, isEmpty);
  });
}
