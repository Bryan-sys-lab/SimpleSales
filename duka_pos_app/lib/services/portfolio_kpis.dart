/// What the cross-shop KPI endpoint returns, as a value.
///
/// The app already refuses to render raw JSON from the network anywhere else —
/// a `Map` leaking into a widget becomes `['revenue'] ?? 0` in a build() and a
/// `null` next release. This parses once, at the boundary, into fields a widget
/// can read.
///
/// ## Money is minor units end to end
///
/// Every amount arrives from the backend as an integer of minor units (cents)
/// and is turned into a [Money] here, not in the widget. A `num` would invite a
/// double to carry a currency somewhere in between, which is how a ledger grows
/// a rounding error.
library;

import '../utils/money.dart';

/// One shop's KPIs over the window.
class ShopKpi {
  const ShopKpi({
    required this.tenantId,
    required this.shopName,
    required this.revenue,
    required this.profit,
    required this.transactions,
    this.role,
    this.topPaymentMethod,
    this.shiftsClosed = 0,
    this.shiftsOpen = 0,
    this.cashVariance = Money.zero,
  });

  /// The backend's tenant id. Identifying, never a display value.
  final String tenantId;

  final String shopName;

  /// The caller's role in THIS shop — an owner of one duka is not thereby an
  /// owner of the next, and a screen that implies otherwise is a screen asking
  /// someone to change a shop they do not run.
  final String? role;

  final Money revenue;
  final Money profit;

  /// A count, not money. Named in full because "transactions" beside two
  /// figures is the one number here that is not currency.
  final int transactions;

  /// The dominant tender, wire-valued: 'cash', 'mpesa', 'card'. Null when the
  /// shop sold nothing in the window — inventing 'cash' would claim a fact that
  /// is not in the data.
  final String? topPaymentMethod;

  /// Shifts counted in the window, and any still open right now.
  ///
  /// A shop's shift is where the cash is reconciled, so "how are my shops
  /// doing" cannot honestly answer with takings alone: a busy shop and a shop
  /// whose drawer has been short for three days look identical on revenue.
  final int shiftsClosed;
  final int shiftsOpen;

  /// Counted cash minus expected cash across the closed shifts. Negative
  /// means the drawer came up short.
  final Money cashVariance;

  /// The average basket, derived from this shop's own totals.
  ///
  /// Computed on read rather than stored, so it cannot drift from the revenue
  /// and the count it is derived from. Zero rather than a division by zero: an
  /// empty shop has a zero average, not a NaN.
  ///
  /// Divided in INTEGER minor units, through the same half-up rule the money
  /// core uses everywhere else. A `double` round trip through `asMajor` is the
  /// pattern `vatComponentOf` exists to avoid: 0.29 over 2 baskets lands at
  /// 14.499999999999998 cents and rounds DOWN to 14, where the exact half-up
  /// answer is 15.
  Money get averageBasket => Money.fromMinor(divideMoneyHalfUp(
        revenue.minorUnits,
        transactions,
      ));

  factory ShopKpi.fromJson(Map<String, dynamic> json) => ShopKpi(
        tenantId: json['tenantId'] as String? ?? '',
        shopName: json['shopName'] as String? ?? '',
        role: json['role'] as String?,
        revenue: Money.fromMinor(_intOf(json['revenue'])),
        profit: Money.fromMinor(_intOf(json['profit'])),
        transactions: _intOf(json['transactions']),
        topPaymentMethod: json['topPaymentMethod'] as String?,
        shiftsClosed: _intOf(json['shiftsClosed']),
        shiftsOpen: _intOf(json['shiftsOpen']),
        cashVariance: Money.fromMinor(_intOf(json['cashVariance'])),
      );
}

/// Every shop the account runs, plus the whole they divide.
class PortfolioKpis {
  const PortfolioKpis({
    required this.shops,
    required this.windowStart,
    required this.windowEnd,
  });

  /// No shops and no figures — a cashier in every shop, or a new account.
  const PortfolioKpis.empty()
      : shops = const <ShopKpi>[],
        windowStart = null,
        windowEnd = null;

  final List<ShopKpi> shops;
  final DateTime? windowStart;
  final DateTime? windowEnd;

  bool get isEmpty => shops.isEmpty;

  /// Every shop's revenue added, in minor units before it is Money.
  ///
  /// Downward-only in money, so the sum never crosses a `num`: each shop's is
  /// an integer of minor units, and the total is the same type as its parts.
  Money get totalRevenue => Money.fromMinor(
      shops.fold<int>(0, (int sum, ShopKpi s) => sum + s.revenue.minorUnits));

  Money get totalProfit => Money.fromMinor(
      shops.fold<int>(0, (int sum, ShopKpi s) => sum + s.profit.minorUnits));

  int get totalTransactions =>
      shops.fold<int>(0, (int sum, ShopKpi s) => sum + s.transactions);

  /// The portfolio's average basket, recomputed from the totals.
  ///
  /// NOT the average of the shops' averages: a shop that sold ten KSh 100
  /// baskets and a shop that sold one KSh 10,000 basket average KSh 5,050 each,
  /// while the portfolio actually averages KSh 1,000 per basket.
  Money get averageBasket => Money.fromMinor(divideMoneyHalfUp(
        totalRevenue.minorUnits,
        totalTransactions,
      ));

  /// The busiest shop by revenue, or null when there is nothing to rank.
  ///
  /// The one shop a manager opens first when they have several: the figure at
  /// the top of the list explains the total better than the total does.
  ShopKpi? get topShopByRevenue {
    if (shops.isEmpty) return null;
    return shops.reduce((ShopKpi a, ShopKpi b) =>
        b.revenue.minorUnits > a.revenue.minorUnits ? b : a);
  }

  /// Shops ranked by revenue, busiest first.
  ///
  /// Ordered here rather than in the widget so a list, a chart and a "best
  /// performer" line all rank identically.
  List<ShopKpi> get shopsByRevenue {
    final List<ShopKpi> ranked = List<ShopKpi>.of(shops)
      ..sort((ShopKpi a, ShopKpi b) =>
          b.revenue.minorUnits.compareTo(a.revenue.minorUnits));
    return ranked;
  }

  factory PortfolioKpis.fromJson(Map<String, dynamic> json) {
    final rawShops = (json['shops'] as List? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>();
    return PortfolioKpis(
      shops: rawShops.map(ShopKpi.fromJson).toList(),
      windowStart: DateTime.tryParse(json['from'] as String? ?? ''),
      windowEnd: DateTime.tryParse(json['to'] as String? ?? ''),
    );
  }
}

/// Reads a JSON number as an integer of minor units.
///
/// The backend sends `Number(...)` from SQL, so a value can arrive as a double
/// (`13000`) or, if a column is nullable, as null. Both are 0 here rather than
/// a crash: a missing figure in a KPI is a zero, not a reason to lose the whole
/// portfolio view.
int _intOf(Object? value) => switch (value) {
      final int v => v,
      final double v => v.round(),
      final String v => int.tryParse(v) ?? 0,
      _ => 0,
    };
