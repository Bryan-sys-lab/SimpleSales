import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../utils/money.dart';

/// The shapes an aggregated query returns, and the pure arithmetic that turns
/// them into something a screen can show.
///
/// Deliberately no `sqflite` import: every type here is a *result*, so the SQL
/// that produces it lives in one place (`DatabaseHelper`) and the presentation
/// that consumes it lives somewhere else, with no shared mutable state between
/// them. That also keeps this file testable without a database at all.
///
/// **Money crosses this boundary as `int` minor units, never as a `double`.**
/// The ledger stores integer cents (`sales.total`, `sale_items.unit_price`),
/// and `SUM()` over an INTEGER column is an exact integer. Widening it to a
/// `double` at the SQL boundary would reintroduce the binary-floating-point
/// drift that `utils/money.dart` exists to remove — a day's takings would stop
/// reconciling with the sum of its sales by a fraction of a cent. The
/// `Money.fromMinor` getters below are the only conversion, and they happen at
/// the presentation edge where formatting is allowed.

// ---------------------------------------------------------------------------
// Totals
// ---------------------------------------------------------------------------

/// One row: the whole ledger reduced to five numbers.
///
/// Covers the dashboard's "today" figures and the analytics screen's
/// range figures without either screen ever holding a `List<Sale>`.
@immutable
class DailyTotals {
  const DailyTotals({
    required this.totalMinor,
    required this.profitMinor,
    required this.transactions,
    required this.averageMinor,
  });

  /// What an empty range aggregates to, rather than the NULL that `SUM`
  /// returns over no rows — so a screen can render a real zero instead of
  /// branching on a null.
  static const DailyTotals empty = DailyTotals(
    totalMinor: 0,
    profitMinor: 0,
    transactions: 0,
    averageMinor: 0,
  );

  /// `SUM(total)`. Integer minor units.
  final int totalMinor;

  /// `SUM(profit)`. Integer minor units.
  final int profitMinor;

  /// `COUNT(*)`. Distinct receipts, not distinct line items.
  final int transactions;

  /// `AVG(total)` rounded to a whole minor unit.
  ///
  /// SQLite's `AVG` is necessarily a REAL — a mean of integers is rarely an
  /// integer — so it is rounded once here and handed on as an `int`. Rounding
  /// rather than truncating keeps a basket of KSh 10.005 from reading as
  /// KSh 10.00, which is the direction that hides revenue.
  final int averageMinor;

  Money get total => Money.fromMinor(totalMinor);
  Money get profit => Money.fromMinor(profitMinor);

  /// Mean basket size — "what does a typical customer spend".
  Money get averageBasket => Money.fromMinor(averageMinor);

  /// False for a range with no sales at all. Distinct from a *zero-sales day*,
  /// which has sales of KSh 0 and a positive basket average.
  bool get hasSales => transactions > 0;

  /// Profit as a percentage of takings, for display only. The division to a
  /// `double` is deliberate and terminal — a margin is a ratio, not an amount.
  double get marginPct =>
      totalMinor <= 0 ? 0 : (profitMinor / totalMinor) * 100;
}

// ---------------------------------------------------------------------------
// Per-product
// ---------------------------------------------------------------------------

/// One row of `topProducts`: everything sold under one product id.
@immutable
class ProductSalesRow {
  const ProductSalesRow({
    required this.productId,
    required this.productName,
    required this.units,
    required this.revenueMinor,
    required this.profitMinor,
  });

  final int productId;

  /// The name carried on the sale lines, not a join against `products`.
  ///
  /// A receipt has to keep saying what the customer was actually charged for,
  /// so the line is the historical record; a rename in the catalogue must not
  /// rewrite last month's takings.
  final String productName;

  /// `SUM(qty)`. A `double` because a quantity is not money: half a bottle is
  /// a real thing and `qty` is deliberately a REAL column.
  final double units;

  /// `SUM(unit_price * qty)`. Integer minor units.
  final int revenueMinor;

  /// `SUM((unit_price - unit_cost) * qty)`. Integer minor units.
  final int profitMinor;

  Money get revenue => Money.fromMinor(revenueMinor);
  Money get profit => Money.fromMinor(profitMinor);

  double get marginPct =>
      revenueMinor <= 0 ? 0 : (profitMinor / revenueMinor) * 100;

  /// Margin as the owner reads it: whole percent, or a dash when there is no
  /// revenue to take a share of. Showing "0%" for a freebie would claim it
  /// sold at zero margin rather than that it has no margin to report.
  String get marginLabel =>
      revenueMinor <= 0 ? '—' : '${marginPct.toStringAsFixed(0)}%';
}

// ---------------------------------------------------------------------------
// Buckets
// ---------------------------------------------------------------------------

/// `salesByHour`: one of twenty-four slots for a single day.
@immutable
class TimeBucket {
  const TimeBucket({
    required this.hour,
    required this.salesMinor,
    required this.profitMinor,
    required this.transactions,
  });

  final int hour;
  final int salesMinor;
  final int profitMinor;
  final int transactions;

  Money get sales => Money.fromMinor(salesMinor);
  Money get profit => Money.fromMinor(profitMinor);

  /// "9am", "14:00" — the axis label. 24-hour past midday because a shift that
  /// runs to midnight is ambiguous in 12-hour form and a staffing decision
  /// depends on getting it right.
  String get hourLabel {
    if (hour == 0) return '12am';
    if (hour < 12) return '${hour}am';
    if (hour == 12) return '12pm';
    return '${hour - 12}pm';
  }
}

/// `salesByDay`: one calendar day. `day` is the raw `YYYY-MM-DD` SQLite key,
/// which sorts correctly and parses without guessing; [label] is for humans.
@immutable
class DateBucket {
  const DateBucket({
    required this.day,
    required this.label,
    required this.salesMinor,
    required this.profitMinor,
    required this.transactions,
  });

  final String day;
  final String label;
  final int salesMinor;
  final int profitMinor;
  final int transactions;

  Money get sales => Money.fromMinor(salesMinor);
  Money get profit => Money.fromMinor(profitMinor);

  bool get hasSales => transactions > 0;

  DateTime get date => DateTime.parse(day);

  /// The same day rendered as a chart axis label.
  factory DateBucket.fromDay(String day) {
    final parsed = DateTime.tryParse(day);
    return DateBucket(
      day: day,
      label: parsed == null ? day : DateFormat('d MMM').format(parsed),
      salesMinor: 0,
      profitMinor: 0,
      transactions: 0,
    );
  }
}

/// `salesByPaymentMethod`: one row per tender type.
@immutable
class PaymentMixRow {
  const PaymentMixRow({
    required this.method,
    required this.salesMinor,
    required this.transactions,
  });

  /// The `sales.payment_method` wire value — 'cash', 'mpesa', 'card', …
  final String method;
  final int salesMinor;
  final int transactions;

  Money get sales => Money.fromMinor(salesMinor);

  /// "Mobile money" rather than "mpesa": the column can hold
  /// `mobile_money_manual` too, and a label that only names one of them is
  /// quietly wrong for a shop taking both.
  String get label => switch (method) {
        'cash' => 'Cash',
        'mpesa' => 'M-Pesa',
        'mobile_money_manual' => 'Mobile money',
        'card' => 'Card',
        'bank_transfer' => 'Bank transfer',
        _ => method,
      };

  /// Share of takings, 0–100. Zero rather than a NaN when nothing was taken.
  double sharePct(int rangeTotalMinor) =>
      rangeTotalMinor <= 0 ? 0 : (salesMinor / rangeTotalMinor) * 100;
}

// ---------------------------------------------------------------------------
// Attention
// ---------------------------------------------------------------------------

/// The four things that quietly derail a seller's day, counted.
///
/// Grouped into one value so a screen can decide "is there anything to say?"
/// with a single [isEmpty] check instead of four, and so the zero case is
/// representable rather than being four separate nulls.
@immutable
class AttentionSummary {
  const AttentionSummary({
    required this.pendingEtims,
    required this.rejectedEtims,
    required this.openImportProblems,
    required this.unverifiedPayments,
  });

  static const AttentionSummary empty = AttentionSummary(
    pendingEtims: 0,
    rejectedEtims: 0,
    openImportProblems: 0,
    unverifiedPayments: 0,
  );

  /// Sales recorded locally that KRA has not issued a receipt for yet.
  final int pendingEtims;

  /// KRA has refused and will refuse again until the shop's configuration is
  /// fixed. Distinct from [pendingEtims]: retrying these achieves nothing.
  final int rejectedEtims;

  /// Spreadsheet rows that could not be written and still need re-importing.
  final int openImportProblems;

  /// Sales taken on an offline "Paid" tap whose money has never been matched
  /// to a provider receipt.
  final int unverifiedPayments;

  int get total =>
      pendingEtims + rejectedEtims + openImportProblems + unverifiedPayments;

  bool get isEmpty => total == 0;
}

// ---------------------------------------------------------------------------
// Pure helpers
// ---------------------------------------------------------------------------

/// A `staff_id` that matches no row in `staff`.
///
/// The value used when a cashier's own id cannot be resolved. `null` is NOT
/// used for that: every scoped query treats null as "no filter", so an
/// unresolved cashier would otherwise read the whole shop's takings as their
/// own. `-1` matches nobody, which is the safe answer — an unresolved session
/// sees nothing rather than everything.
///
/// One definition, because the rule is one rule: the id is a query argument,
/// so the places that choose it — `AppState.analyticsStaffId` and the
/// dashboard's own-scoping through [staffIdForCashierOrNobody] — cannot drift
/// into disagreeing about what "unresolved" costs.
const int kUnmatchedStaffId = -1;

/// The `staff.id` a cashier's name resolves to, or null when it resolves to
/// nothing usable.
///
/// The ledger's scoping column is `staff_id`, never `staff_name`: the name is
/// mutable, unindexed, and rewritten wholesale to "Deleted cashier" when a
/// cashier is removed, so scoping by it both scans the table and collapses
/// every former cashier into one bucket.
///
/// Returns null rather than guessing when the name is ambiguous, because an
/// over-broad filter silently under-reports a person's takings, and
/// under-reporting someone's pay is worse than showing nothing.
int? staffIdForCashier(Iterable<Staff> staff, String? name) {
  final wanted = name?.trim() ?? '';
  if (wanted.isEmpty) return null;
  final matches = staff.where((s) => s.name == wanted).toList();
  if (matches.length != 1) return null;
  return matches.first.id;
}

/// The id a cashier's own figures are scoped by, resolving their name.
///
/// The only place `staffIdForCashier`'s null is translated into
/// [kUnmatchedStaffId], and it has to be somewhere: the null it returns means
/// "I could not work out who this is", while the null a scoped query accepts
/// means "every row in the shop". Handing one straight to the other is how a
/// cashier with an unresolvable name ends up reading the whole shop's takings
/// as their own — which is the opposite of what the null was for.
///
/// So an unresolved cashier sees nothing: figures they did not take are not
/// theirs, and showing them a shop total is the worse of the two errors.
int staffIdForCashierOrNobody(Iterable<Staff> staff, String? name) =>
    staffIdForCashier(staff, name) ?? kUnmatchedStaffId;

/// The id a signed-in person's OWN figures are scoped by.
///
/// The session's own id comes first, because `signInAsStaff` carries the local
/// staff row's id — the same id the ledger's `staff_id` column holds — so it
/// is the authoritative answer wherever the session has one. The name lookup
/// is the fallback, for a session restored from a backup that has a name and
/// no id, and it goes through [staffIdForCashierOrNobody] so its "unresolved"
/// still reads as nobody.
///
/// Never null. Null is the one answer a session's own figures must not get,
/// because every scoped query reads it as "every row in the shop".
int ownStaffId({
  required int? sessionStaffId,
  required Iterable<Staff> staff,
  required String? staffName,
}) =>
    sessionStaffId ?? staffIdForCashierOrNobody(staff, staffName);

/// The hour with the most takings, or null when the day has no sales.
///
/// Zero is not a peak: a day where nothing sold must not report "12am was
/// your busiest hour", so ties at zero are treated as no answer.
TimeBucket? busiestHour(List<TimeBucket> buckets) {
  TimeBucket? best;
  for (final bucket in buckets) {
    if (bucket.salesMinor <= 0) continue;
    if (best == null || bucket.salesMinor > best.salesMinor) best = bucket;
  }
  return best;
}

/// Collapses [buckets] to at most [maxBars] by summing consecutive days.
///
/// A ninety-day range is ninety bars wide, which at a phone's width is a
/// grey smear with no readable axis. Merging keeps the *shape* honest — the
/// bar still totals exactly the takings of the days inside it — instead of
/// sampling or silently dropping the middle, either of which would show a
/// trend the ledger does not have.
List<DateBucket> mergeDateBuckets(List<DateBucket> buckets, int maxBars) {
  if (maxBars <= 0 || buckets.length <= maxBars) return buckets;
  final size = (buckets.length / maxBars).ceil();
  final merged = <DateBucket>[];
  for (var start = 0; start < buckets.length; start += size) {
    final end = math.min(start + size, buckets.length);
    final slice = buckets.sublist(start, end);
    var sales = 0;
    var profit = 0;
    var count = 0;
    for (final bucket in slice) {
      sales += bucket.salesMinor;
      profit += bucket.profitMinor;
      count += bucket.transactions;
    }
    merged.add(DateBucket(
      day: slice.first.day,
      label: slice.length == 1
          ? slice.first.label
          : '${slice.first.label} – ${slice.last.label}',
      salesMinor: sales,
      profitMinor: profit,
      transactions: count,
    ));
  }
  return merged;
}

/// The spoken equivalent of a bar chart.
///
/// A painted chart is invisible to a screen reader — it is a canvas of coloured
/// rectangles with no text nodes — so the same figures are handed to
/// `Semantics` as a sentence. This is the whole accessible equivalent, which
/// is why it names the peak and the range rather than just the numbers.
String describeDailyBuckets(String title, List<DateBucket> buckets) {
  if (buckets.isEmpty) return '$title. No sales in this period.';
  var total = 0;
  var salesDays = 0;
  DateBucket? best;
  for (final bucket in buckets) {
    total += bucket.salesMinor;
    if (bucket.transactions > 0) salesDays++;
    if (bucket.transactions > 0 &&
        (best == null || bucket.salesMinor > best.salesMinor)) {
      best = bucket;
    }
  }
  final parts = <String>[
    '$title.',
    'Total ${formatMoney(Money.fromMinor(total))} over ${buckets.length} '
        '${buckets.length == 1 ? 'day' : 'days'}, with sales on $salesDays of them.',
  ];
  if (best != null) {
    parts.add(
        'Best day ${best.label} at ${formatMoney(Money.fromMinor(best.salesMinor))}.');
  }
  return parts.join(' ');
}

/// The spoken equivalent of a product bar chart.
String describeTopProducts(List<ProductSalesRow> rows) {
  if (rows.isEmpty) return 'Top products. Nothing sold in this period.';
  final head = rows
      .take(5)
      .map((row) => '${row.productName}, ${_unitsLabel(row.units)}, '
          '${formatMoney(Money.fromMinor(row.revenueMinor))}')
      .join('; ');
  final tail = rows.length > 5 ? ' and ${rows.length - 5} more' : '';
  return 'Top products. $head$tail.';
}

/// "1 unit" / "2.5 units" / "12 units" — a quantity, so it is pluralised on the
/// number rather than assumed to be two or more.
String _unitsLabel(double units) {
  final rounded = units == units.roundToDouble();
  final text = rounded ? units.toStringAsFixed(0) : units.toStringAsFixed(2);
  return units == 1 ? '$text unit' : '$text units';
}

/// The spoken equivalent of the payment mix.
String describePaymentMix(List<PaymentMixRow> rows, int rangeTotalMinor) {
  if (rows.isEmpty) return 'Payment methods. Nothing taken in this period.';
  final head = rows
      .map((row) =>
          '${row.label} ${formatMoney(Money.fromMinor(row.salesMinor))} '
          'across ${row.transactions} ${row.transactions == 1 ? 'sale' : 'sales'}, '
          '${row.sharePct(rangeTotalMinor).toStringAsFixed(0)} percent')
      .join('; ');
  return 'Payment methods. $head.';
}
