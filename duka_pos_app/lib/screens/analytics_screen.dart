import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/models.dart';
import '../services/analytics.dart';
import '../theme/app_theme.dart';
import '../utils/money.dart';
import '../widgets/chart.dart';

/// The windows the owner thinks in.
///
/// Named as lengths rather than as two dates: "last 7 days" is what someone
/// asks for at the counter, and it includes today. Keeping them as an enum
/// means the query, the label and the bar chart can never disagree about which
/// period is on screen.
enum AnalyticsRange {
  today('Today', 1),
  week('7 days', 7),
  month('30 days', 30),
  quarter('90 days', 90);

  const AnalyticsRange(this.label, this.days);

  final String label;

  /// Days of history the window covers, today included.
  final int days;

  /// Midnight today, and the start of the day [days] ago.
  ///
  /// `salesByDay`/`topProducts` take `since` inclusive, so a seven-day window
  /// starts six days back — seven days *including today*, which is what the
  /// label claims.
  DateTime get since {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return today.subtract(Duration(days: days - 1));
  }
}

/// Which column the product table is ordered by.
enum ProductSort {
  name('Product'),
  units('Units'),
  revenue('Revenue'),
  profit('Profit'),
  margin('Margin');

  const ProductSort(this.label);
  final String label;
}

/// The shop's trading over a chosen window.
///
/// Manager and owner only (the shell adds the tab for `canManageStock`): the
/// figures here are the whole shop's, including every cashier's takings and
/// every product's margin, which is not a cashier's to read. A cashier's own
/// numbers are on their dashboard, scoped by `staff_id`.
///
/// Nothing on this screen sums anything in Dart — each figure is one
/// aggregate query answered by SQLite, so a ninety-day window costs the same
/// as a one-day one.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  AnalyticsRange _range = AnalyticsRange.week;
  ProductSort _sort = ProductSort.revenue;
  bool _ascending = false;

  bool _loading = true;
  String? _error;

  DailyTotals _totals = DailyTotals.empty;
  List<DateBucket> _days = const [];
  List<ProductSalesRow> _products = const [];
  List<PaymentMixRow> _payments = const [];
  List<Product> _lowStock = const [];
  List<Product> _outOfStock = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = DatabaseHelper.instance;
    try {
      final since = _range.since;
      final results = await Future.wait([
        db.salesTotalsFor(since: since),
        db.salesByDay(since: since),
        db.topProducts(since: since, limit: 20),
        db.salesByPaymentMethod(since: since),
        db.getProducts(),
      ]);
      if (!mounted) return;
      final products = results[4] as List<Product>;
      setState(() {
        _totals = results[0] as DailyTotals;
        _days = results[1] as List<DateBucket>;
        _products = results[2] as List<ProductSalesRow>;
        _payments = results[3] as List<PaymentMixRow>;
        // Two lists, not one: "out of stock" and "running low" are different
        // urgencies, and one list that quietly contains both is read as the
        // milder of the two.
        _outOfStock = products.where((p) => p.stockQty <= 0).toList()
          ..sort((a, b) => a.name.compareTo(b.name));
        _lowStock = products
            .where((p) => p.stockQty > 0 && p.isLow)
            .toList()
          ..sort((a, b) => a.stockQty.compareTo(b.stockQty));
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Couldn’t load analytics.';
      });
    }
  }

  void _setRange(AnalyticsRange range) {
    if (range == _range) return;
    setState(() {
      _range = range;
      _loading = true;
    });
    _load();
  }

  void _sortBy(ProductSort column) {
    setState(() {
      // Tapping the active column reverses it; a new column starts descending,
      // because the first thing anyone looks at in a top-sellers list is the
      // top of it.
      if (_sort == column) {
        _ascending = !_ascending;
      } else {
        _sort = column;
        _ascending = column == ProductSort.name;
      }
    });
  }

  /// The order the table is displayed in, derived from the column the header
  /// says is sorted — so the arrow and the rows can never disagree.
  List<ProductSalesRow> get _sortedProducts {
    int compare(ProductSalesRow a, ProductSalesRow b) => switch (_sort) {
          ProductSort.name => a.productName.toLowerCase().compareTo(b.productName.toLowerCase()),
          ProductSort.units => a.units.compareTo(b.units),
          ProductSort.revenue => a.revenueMinor.compareTo(b.revenueMinor),
          ProductSort.profit => a.profitMinor.compareTo(b.profitMinor),
          ProductSort.margin => a.marginPct.compareTo(b.marginPct),
        };
    final sorted = [..._products]..sort(compare);
    return _ascending ? sorted : sorted.reversed.toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
          child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: _load, child: const Text('Try again')),
        ]),
      ));
    }

    // 90 bars is unreadable at any phone width; merging consecutive days keeps
    // every shilling in the bar while making the axis legible.
    final chartDays = mergeDateBuckets(_days, 14);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(DukaSpacing.lg),
        children: [
          _RangeSelector(range: _range, onChanged: _setRange),
          const SizedBox(height: DukaSpacing.lg),
          _RangeKpis(totals: _totals, range: _range),
          const SizedBox(height: DukaSpacing.xl),
          SimplePosChart(
            title: 'Sales by day',
            emphasis: _totals.hasSales
                ? '${formatMoney(_totals.total)} over ${_range.label.toLowerCase()}'
                : null,
            semanticsLabel: describeDailyBuckets('Sales by day', chartDays),
            height: 168,
            bars: [
              for (final day in chartDays)
                PosChartBar(
                  label: day.label,
                  value: day.salesMinor,
                  valueLabel: formatMoney(day.sales),
                ),
            ],
          ),
          const SizedBox(height: DukaSpacing.xl),
          _ProductTable(
            rows: _sortedProducts,
            sort: _sort,
            ascending: _ascending,
            onSort: _sortBy,
          ),
          const SizedBox(height: DukaSpacing.xl),
          _PaymentMix(rows: _payments, rangeTotalMinor: _totals.totalMinor),
          const SizedBox(height: DukaSpacing.xl),
          _StockSection(
            outOfStock: _outOfStock,
            lowStock: _lowStock,
          ),
        ],
      ),
    );
  }
}

/// The range control. A [SegmentedButton] rather than a dropdown because all
/// four windows are equally likely and should cost one tap, not two.
class _RangeSelector extends StatelessWidget {
  const _RangeSelector({required this.range, required this.onChanged});

  final AnalyticsRange range;
  final ValueChanged<AnalyticsRange> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<AnalyticsRange>(
      segments: [
        for (final option in AnalyticsRange.values)
          ButtonSegment<AnalyticsRange>(
            value: option,
            label: Text(option.label),
          ),
      ],
      selected: {range},
      showSelectedIcon: false,
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}

/// The range's headline figures.
class _RangeKpis extends StatelessWidget {
  const _RangeKpis({required this.totals, required this.range});

  final DailyTotals totals;
  final AnalyticsRange range;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      _RangeKpi(
        label: 'Sales',
        value: formatMoney(totals.total),
        caption: range.label,
      ),
      _RangeKpi(
        label: 'Profit',
        value: formatMoney(totals.profit),
        caption: totals.hasSales
            ? '${totals.marginPct.toStringAsFixed(0)}% margin'
            : null,
      ),
      _RangeKpi(
        label: 'Sales',
        value: '${totals.transactions}',
        caption: totals.transactions == 1 ? 'transaction' : 'transactions',
      ),
      _RangeKpi(
        label: 'Avg basket',
        value: formatMoney(totals.averageBasket),
        caption: 'per sale',
      ),
    ];

    return LayoutBuilder(builder: (context, constraints) {
      const spacing = DukaSpacing.md;
      final tileWidth = (constraints.maxWidth - spacing) / 2;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final tile in tiles)
            SizedBox(width: tileWidth, child: tile),
        ],
      );
    });
  }
}

class _RangeKpi extends StatelessWidget {
  const _RangeKpi({required this.label, required this.value, this.caption});

  final String label;
  final String value;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: [label, value, if (caption != null) caption!].join(', '),
      excludeSemantics: true,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(DukaSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 2),
              Text(label, style: theme.textTheme.bodySmall),
              if (caption != null)
                Text(caption!, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

/// The best sellers, sortable by any column.
///
/// A table rather than another chart: five columns of unrelated magnitudes
/// cannot share one set of bars without one of them being unreadable, and this
/// is the screen where an owner is comparing a product's margin against its
/// revenue.
class _ProductTable extends StatelessWidget {
  const _ProductTable({
    required this.rows,
    required this.sort,
    required this.ascending,
    required this.onSort,
  });

  final List<ProductSalesRow> rows;
  final ProductSort sort;
  final bool ascending;
  final ValueChanged<ProductSort> onSort;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          header: true,
          child: Text('Top products', style: theme.textTheme.titleMedium),
        ),
        const SizedBox(height: DukaSpacing.sm),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: DukaSpacing.sm),
            child: Text('Nothing sold in this period.'),
          )
        else
          Card(
            child: Column(
              children: [
                _TableHeader(
                    sort: sort, ascending: ascending, onSort: onSort),
                const Divider(height: 1),
                for (final row in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: DukaSpacing.md, vertical: DukaSpacing.sm),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 4,
                          child: Text(row.productName,
                              style: theme.textTheme.bodyMedium),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(_units(row.units),
                              textAlign: TextAlign.end,
                              style: theme.textTheme.bodySmall),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(formatMoney(row.revenue),
                              textAlign: TextAlign.end,
                              style: theme.textTheme.bodyMedium),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(formatMoney(row.profit),
                              textAlign: TextAlign.end,
                              style: theme.textTheme.bodyMedium),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(row.marginLabel,
                              textAlign: TextAlign.end,
                              style: theme.textTheme.bodySmall),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  static String _units(double units) =>
      units == units.roundToDouble() ? units.toStringAsFixed(0) : units.toStringAsFixed(2);
}

class _TableHeader extends StatelessWidget {
  const _TableHeader({
    required this.sort,
    required this.ascending,
    required this.onSort,
  });

  final ProductSort sort;
  final bool ascending;
  final ValueChanged<ProductSort> onSort;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          DukaSpacing.md, DukaSpacing.sm, DukaSpacing.md, DukaSpacing.sm),
      child: Row(
        children: [
          Expanded(flex: 4, child: _cell(context, ProductSort.name)),
          Expanded(flex: 2, child: _cell(context, ProductSort.units)),
          Expanded(flex: 3, child: _cell(context, ProductSort.revenue)),
          Expanded(flex: 3, child: _cell(context, ProductSort.profit)),
          Expanded(flex: 2, child: _cell(context, ProductSort.margin)),
        ],
      ),
    );
  }

  Widget _cell(BuildContext context, ProductSort column) {
    final theme = Theme.of(context);
    final active = sort == column;
    // The arrow, not just the bold, says which way — colour and weight alone
    // would leave a screen-reader user with no way to tell ascending from
    // descending.
    return Semantics(
      button: true,
      selected: active,
      label: '${column.label} column, '
          '${active ? (ascending ? 'sorted ascending' : 'sorted descending') : 'not sorted'}',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => onSort(column),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: DukaSpacing.xs),
          child: Text(
            active ? '${column.label}${ascending ? ' ↑' : ' ↓'}' : column.label,
            textAlign: column == ProductSort.name
                ? TextAlign.start
                : TextAlign.end,
            style: (active
                    ? theme.textTheme.labelLarge
                    : theme.textTheme.bodySmall)
                ?.copyWith(color: active ? DukaColors.primary : null),
          ),
        ),
      ),
    );
  }
}

/// How the money came in, by tender.
class _PaymentMix extends StatelessWidget {
  const _PaymentMix({required this.rows, required this.rangeTotalMinor});

  final List<PaymentMixRow> rows;
  final int rangeTotalMinor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          header: true,
          child: Text('Payment methods', style: theme.textTheme.titleMedium),
        ),
        const SizedBox(height: DukaSpacing.sm),
        if (rows.isEmpty)
          const Text('Nothing taken in this period.')
        else
          SimplePosChart(
            title: '',
            semanticsLabel: describePaymentMix(rows, rangeTotalMinor),
            axis: PosChartAxis.horizontal,
            bars: [
              for (final row in rows)
                PosChartBar(
                  label: row.label,
                  value: row.salesMinor,
                  valueLabel: formatMoney(row.sales),
                ),
            ],
          ),
      ],
    );
  }
}

/// Out of stock first, then what is running low.
class _StockSection extends StatelessWidget {
  const _StockSection({required this.outOfStock, required this.lowStock});

  final List<Product> outOfStock;
  final List<Product> lowStock;

  static const int shown = 10;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          header: true,
          child: Text('Stock', style: theme.textTheme.titleMedium),
        ),
        const SizedBox(height: DukaSpacing.sm),
        if (outOfStock.isEmpty && lowStock.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: DukaSpacing.sm),
            child: Text('Everything is above its reorder level.'),
          )
        else ...[
          if (outOfStock.isNotEmpty)
            _StockList(
              title: 'Out of stock',
              icon: Icons.remove_shopping_cart_outlined,
              colour: DukaColors.danger,
              products: outOfStock.take(shown).toList(),
              total: outOfStock.length,
            ),
          if (outOfStock.isNotEmpty && lowStock.isNotEmpty)
            const SizedBox(height: DukaSpacing.md),
          if (lowStock.isNotEmpty)
            _StockList(
              title: 'Running low',
              icon: Icons.trending_down,
              colour: DukaColors.warning,
              products: lowStock.take(shown).toList(),
              total: lowStock.length,
            ),
          const SizedBox(height: DukaSpacing.sm),
          Text(
            'Open Inventory from the tab bar to reorder.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _StockList extends StatelessWidget {
  const _StockList({
    required this.title,
    required this.icon,
    required this.colour,
    required this.products,
    required this.total,
  });

  final String title;
  final IconData icon;
  final Color colour;
  final List<Product> products;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            dense: true,
            leading: Icon(icon, color: colour),
            title: Text(title, style: theme.textTheme.titleMedium),
            // The count is the reason the section exists, so it is not hidden
            // behind a list the reader has to count.
            trailing: Text('$total'),
          ),
          for (final product in products)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  DukaSpacing.lg, 0, DukaSpacing.lg, DukaSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Text(product.name, style: theme.textTheme.bodyMedium),
                  ),
                  const SizedBox(width: DukaSpacing.sm),
                  Text(
                    '${_qty(product.stockQty)} left',
                    style: TextStyle(color: colour, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          if (total > products.length)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  DukaSpacing.lg, 0, DukaSpacing.lg, DukaSpacing.md),
              child: Text('and ${total - products.length} more',
                  style: theme.textTheme.bodySmall),
            ),
        ],
      ),
    );
  }

  static String _qty(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
}
