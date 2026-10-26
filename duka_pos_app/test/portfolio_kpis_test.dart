// The cross-shop KPIs as a value.
//
// This is what the analytics screen reads to answer "how are ALL my shops
// doing", and the property that matters is that the portfolio's figures are
// derived from the portfolio's OWN totals rather than by averaging the shops'
// averages. A shop that sold ten KSh 100 baskets and a shop that sold one KSh
// 10,000 basket average KSh 5,050 each, while the portfolio actually averages
// KSh 1,000 per basket. That is the bug these tests pin down.

import 'package:duka_pos/services/portfolio_kpis.dart';
import 'package:duka_pos/services/analytics.dart';
import 'package:duka_pos/utils/money.dart';
import 'package:duka_pos/profile/shop_profile.dart';
import 'package:flutter_test/flutter_test.dart';

ShopKpi _shop({
  String tenantId = 't1',
  String shopName = 'Amina Duka',
  int revenueMinor = 0,
  int profitMinor = 0,
  int transactions = 0,
  String? role = 'admin',
  String? topPaymentMethod,
}) =>
    ShopKpi(
      tenantId: tenantId,
      shopName: shopName,
      revenue: Money.fromMinor(revenueMinor),
      profit: Money.fromMinor(profitMinor),
      transactions: transactions,
      role: role,
      topPaymentMethod: topPaymentMethod,
    );

void main() {
  test('portfolio keeps each shop profile without blending it into totals', () {
    final ShopKpi shop = ShopKpi.fromJson(<String, dynamic>{
      'tenantId': 't-fashion',
      'shopName': 'Amina Styles',
      'businessProfile': 'fashion',
      'revenue': 1000,
    });
    expect(shop.businessProfile, ShopProfile.fashion);
    expect(shop.revenue, Money.fromMinor(1000));
  });

  test('remote aggregate and product reports preserve minor-unit money', () {
    final summary = RemoteSalesSummary.fromJson(<String, dynamic>{
      'totals': <String, dynamic>{
        'total': 1250,
        'profit': 300,
        'expensesMinor': 80,
        'count': 2,
      },
      'paymentMix': <Map<String, dynamic>>[
        <String, dynamic>{'method': 'cash', 'sales': 1000, 'transactions': 1},
      ],
      'daily': <Map<String, dynamic>>[
        <String, dynamic>{
          'day': '2026-10-24',
          'sales': 1250,
          'profit': 300,
          'transactions': 2,
        },
      ],
    });
    expect(summary.totals.totalMinor, 1250);
    expect(summary.totals.averageMinor, 625);
    expect(summary.totals.expensesMinor, 80);
    expect(summary.payments.single.salesMinor, 1000);
    expect(summary.days.single.day, '2026-10-24');
    expect(summary.days.single.salesMinor, 1250);

    final products = RemoteProductReport.fromJson(<String, dynamic>{
      'products': <Map<String, dynamic>>[
        <String, dynamic>{
          'product_id': 'remote-1',
          'product_name': 'Soda',
          'units': 3,
          'net_sales': 750,
          'gross_profit': 300,
          'transactions': 2,
        },
      ],
    });
    expect(products.products.single.remoteId, 'remote-1');
    expect(products.products.single.revenueMinor, 750);
    expect(products.products.single.profitMinor, 300);
  });

  test('remote product drill-down keeps its synced stock timeline', () {
    final report = RemoteProductReport.fromJson(<String, dynamic>{
      'products': <Map<String, dynamic>>[
        <String, dynamic>{
          'product_id': 'remote-1',
          'product_name': 'Soda',
          'units': 3,
          'net_sales': 750,
          'gross_profit': 300,
          'transactions': 2,
        },
      ],
      'staff': <dynamic>[],
      'payments': <dynamic>[],
      'stockTimeline': <Map<String, dynamic>>[
        <String, dynamic>{
          'uuid': 'movement-1',
          'created_at': '2026-01-05T10:00:00.000Z',
          'product_id': -1,
          'movement_type': 'receipt',
          'qty_delta': 12,
          'balance_after': 12,
        },
      ],
    });

    expect(report.drilldown?.stockTimeline.single.uuid, 'movement-1');
    expect(report.drilldown?.stockTimeline.single.qtyDelta, 12);
    expect(report.drilldown?.stockTimeline.single.type.wire, 'receipt');
  });

  group('portfolio totals', () {
    test('financial totals reconcile from shop-level components', () {
      final portfolio = PortfolioKpis(
        shops: <ShopKpi>[
          ShopKpi(
            tenantId: 'one',
            shopName: 'One',
            revenue: Money.fromMinor(10000),
            profit: Money.fromMinor(3000),
            transactions: 2,
            operatingExpenses: Money.fromMinor(500),
            cashIn: Money.fromMinor(9000),
            cashOut: Money.fromMinor(1200),
            receivableDelta: Money.fromMinor(700),
            payableDelta: Money.fromMinor(200),
            stockValue: Money.fromMinor(8000),
            financialDataComplete: true,
          ),
          ShopKpi(
            tenantId: 'two',
            shopName: 'Two',
            revenue: Money.fromMinor(20000),
            profit: Money.fromMinor(6000),
            transactions: 3,
            operatingExpenses: Money.fromMinor(1000),
            cashIn: Money.fromMinor(18000),
            cashOut: Money.fromMinor(3000),
            receivableDelta: Money.fromMinor(300),
            payableDelta: Money.fromMinor(400),
            stockValue: Money.fromMinor(12000),
            financialDataComplete: true,
          ),
        ],
        windowStart: DateTime(2026, 1, 1),
        windowEnd: DateTime(2026, 2, 1),
      );

      expect(portfolio.totalOperatingExpenses.minorUnits, 1500);
      expect(portfolio.totalNetProfit.minorUnits, 7500);
      expect(portfolio.totalNetCashFlow.minorUnits, 22800);
      expect(portfolio.totalReceivableDelta.minorUnits, 1000);
      expect(portfolio.totalPayableDelta.minorUnits, 600);
      expect(portfolio.totalStockValue.minorUnits, 20000);
      expect(portfolio.financialDataComplete, isTrue);
    });

    test(
        'mixed four-profile totals keep shop identity and completeness explicit',
        () {
      final profiles = <ShopProfile>[
        ShopProfile.drinks,
        ShopProfile.duka,
        ShopProfile.fashion,
        ShopProfile.open,
      ];
      final shops = <ShopKpi>[
        for (var i = 0; i < profiles.length; i++)
          ShopKpi(
            tenantId: 'tenant-$i',
            shopName: 'Shop ${i + 1}',
            businessProfile: profiles[i],
            revenue: Money.fromMinor((i + 1) * 1000),
            profit: Money.fromMinor((i + 1) * 300),
            transactions: i + 1,
            operatingExpenses: Money.fromMinor((i + 1) * 50),
            financialDataComplete: i != 3,
          ),
      ];
      final portfolio = PortfolioKpis(
        shops: shops,
        windowStart: DateTime(2026, 1, 1),
        windowEnd: DateTime(2026, 2, 1),
      );

      expect(
        portfolio.shops.map((shop) => shop.businessProfile).toList(),
        profiles,
      );
      expect(portfolio.totalRevenue.minorUnits, 10000);
      expect(portfolio.totalProfit.minorUnits, 3000);
      expect(portfolio.totalOperatingExpenses.minorUnits, 500);
      expect(portfolio.totalNetProfit.minorUnits, 2500);
      expect(portfolio.financialDataComplete, isFalse,
          reason: 'one incomplete shop must not be represented as complete');
    });

    test('the whole is the sum of the parts, in minor units', () {
      final PortfolioKpis kpis = PortfolioKpis(
        windowStart: DateTime(2026, 1, 1),
        windowEnd: DateTime(2026, 2, 1),
        shops: <ShopKpi>[
          _shop(revenueMinor: 400000, profitMinor: 120000, transactions: 20),
          _shop(
              tenantId: 't2',
              revenueMinor: 900000,
              profitMinor: 300000,
              transactions: 60),
        ],
      );

      expect(kpis.totalRevenue.asMajor, 13000);
      expect(kpis.totalProfit.asMajor, 4200);
      expect(kpis.totalTransactions, 80);
    });

    test("the portfolio average comes from the totals, not the shops' averages",
        () {
      final PortfolioKpis kpis = PortfolioKpis(
        windowStart: DateTime(2026, 1, 1),
        windowEnd: DateTime(2026, 2, 1),
        shops: <ShopKpi>[
          _shop(revenueMinor: 100000, transactions: 10), // avg 1000
          _shop(revenueMinor: 1000000, transactions: 1), // avg 100000
        ],
      );

      // The true portfolio average is 1,100,000 / 11 = 100,000 cents = KSh 1000.
      // Averaging the two shops' averages would say KSh 50,500.
      expect(kpis.averageBasket.asMajor, 1000);
    });

    test('an empty portfolio has a zero average, not a NaN', () {
      const PortfolioKpis kpis = PortfolioKpis.empty();
      expect(kpis.isEmpty, isTrue);
      expect(kpis.averageBasket.isZero, isTrue);
      expect(kpis.totalRevenue.isZero, isTrue);
      expect(kpis.topShopByRevenue, isNull);
      expect(kpis.shopsByRevenue, isEmpty);
    });

    test('a portfolio of shops that sold nothing averages zero', () {
      final PortfolioKpis kpis = PortfolioKpis(
        windowStart: DateTime(2026, 1, 1),
        windowEnd: DateTime(2026, 2, 1),
        shops: <ShopKpi>[_shop(), _shop(tenantId: 't2')],
      );

      // Guarded on transactions, not on shop count: the average of two zeroes
      // is not a fact about sales that happened.
      expect(kpis.averageBasket.isZero, isTrue);
      expect(kpis.shops.length, 2);
    });
  });

  group('ranking', () {
    test('the busiest shop is the one with the most revenue', () {
      final PortfolioKpis kpis = PortfolioKpis(
        windowStart: DateTime(2026, 1, 1),
        windowEnd: DateTime(2026, 2, 1),
        shops: <ShopKpi>[
          _shop(shopName: 'Quiet', revenueMinor: 40000),
          _shop(tenantId: 't2', shopName: 'Busy', revenueMinor: 900000),
          _shop(tenantId: 't3', shopName: 'Middle', revenueMinor: 200000),
        ],
      );

      expect(kpis.topShopByRevenue?.shopName, 'Busy');
      expect(kpis.shopsByRevenue.map((ShopKpi s) => s.shopName).toList(),
          <String>['Busy', 'Middle', 'Quiet']);
    });

    test('ranking is stable when two shops tie', () {
      final PortfolioKpis kpis = PortfolioKpis(
        windowStart: DateTime(2026, 1, 1),
        windowEnd: DateTime(2026, 2, 1),
        shops: <ShopKpi>[
          _shop(shopName: 'First', revenueMinor: 5000),
          _shop(tenantId: 't2', shopName: 'Second', revenueMinor: 5000),
        ],
      );

      // The order they arrived in, not a crash and not an arbitrary shuffle.
      expect(kpis.shopsByRevenue.length, 2);
      expect(kpis.topShopByRevenue, isNotNull);
    });
  });

  group('parsing', () {
    test('a backend body parses into typed money', () {
      final PortfolioKpis kpis = PortfolioKpis.fromJson(<String, dynamic>{
        'from': '2026-01-01T00:00:00.000Z',
        'to': '2026-02-01T00:00:00.000Z',
        'shops': <Map<String, dynamic>>[
          <String, dynamic>{
            'tenantId': 't1',
            'shopName': 'Amina Duka',
            'role': 'admin',
            'revenue': 4000,
            'profit': 1200,
            'transactions': 20,
            'topPaymentMethod': 'mpesa',
          },
          <String, dynamic>{
            'tenantId': 't2',
            'shopName': 'Njeri',
            'role': 'manager',
            'revenue': 9000,
            'profit': 3000,
            'transactions': 60,
            // An empty shop has no dominant tender.
            'topPaymentMethod': null,
          },
        ],
      });

      expect(kpis.shops.length, 2);
      expect(kpis.shops.first.revenue.asMajor, 40);
      expect(kpis.shops.first.topPaymentMethod, 'mpesa');
      expect(kpis.shops.last.topPaymentMethod, isNull);
      expect(kpis.windowStart?.year, 2026);
    });

    test('a missing or malformed figure is a zero, not a crash', () {
      // SQL can hand back a double, and a nullable column hands back null.
      // Losing the whole portfolio view because one shop had no profit yet is
      // not an acceptable trade for a KPI screen.
      final PortfolioKpis kpis = PortfolioKpis.fromJson(<String, dynamic>{
        'shops': <Map<String, dynamic>>[
          <String, dynamic>{
            'tenantId': 't1',
            'shopName': 'Amina',
            'revenue': null,
            'profit': 1200.0,
            'transactions': '20',
          },
        ],
      });

      expect(kpis.shops.single.revenue.isZero, isTrue);
      expect(kpis.shops.single.profit.asMajor, 12);
      expect(kpis.shops.single.transactions, 20);
      expect(kpis.shops.single.role, isNull);
    });

    test('a body with no shops at all is an empty portfolio', () {
      final PortfolioKpis kpis =
          PortfolioKpis.fromJson(<String, dynamic>{'shops': null});
      expect(kpis.isEmpty, isTrue);
    });

    test('a shop with no sales has a zero average basket', () {
      final ShopKpi kpi = ShopKpi.fromJson(<String, dynamic>{
        'tenantId': 't1',
        'shopName': 'Amina',
        'revenue': 0,
        'profit': 0,
        'transactions': 0,
      });
      expect(kpi.averageBasket.isZero, isTrue);
    });
  });
}
