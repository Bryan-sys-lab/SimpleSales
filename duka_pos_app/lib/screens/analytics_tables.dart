import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/analytics.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/controls.dart';
import '../ui/components/status.dart';
import '../ui/components/surface.dart';
import '../utils/money.dart';
import '../widgets/chart.dart';
import 'analytics_screen.dart';

/// Below this width five columns of figures stop being readable and the table
/// turns into two lines per product.
///
/// A layout decision measured against a width, not a device: the same fallback
/// fires on a 360dp phone and on a 380dp window on a desktop.
const double kProductTableWideWidth = 560;

/// A quantity, with no decimals it does not need.
///
/// A quantity is not money, so this is not [formatMoney] — but it is still a
/// figure a user compares down a column, so it is rendered with tabular figures.
String _unitsLabel(double units) => units == units.roundToDouble()
    ? units.toStringAsFixed(0)
    : units.toStringAsFixed(2);

/// Stock left, one decimal only when a pack was broken open.
String _stockLabel(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(1);

/// The best sellers, sortable by any column.
///
/// A table rather than another chart: five columns of unrelated magnitudes
/// cannot share one set of bars without one of them being unreadable, and this
/// is the screen where an owner is comparing a product's margin against its
/// revenue.
/// How many rows a collapsed top-products card shows.
///
/// Six, because that is what fits a phone screen without scrolling and still
/// answers "what is selling". The full list is one tap away.
const kProductTableCollapsedRows = 6;

class ProductTableCard extends StatefulWidget {
  const ProductTableCard({
    required this.rows,
    required this.sort,
    required this.ascending,
    this.onSort,
    super.key,
  });

  final List<ProductSalesRow> rows;
  final ProductSort sort;
  final bool ascending;

  /// Null when the screen cannot reorder — a preview rather than a control.
  final ValueChanged<ProductSort>? onSort;

  @override
  State<ProductTableCard> createState() => _ProductTableCardState();
}

class _ProductTableCardState extends State<ProductTableCard> {
  /// Whether every row is showing.
  ///
  /// Collapsed by default, and deliberately: an uncapped "Top products" card
  /// on a shop with a busy month rendered twenty rows and pushed the payment
  /// breakdown and the product list below it off the bottom of the screen. A
  /// section that grows without bound is not a section, it is a page.
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final rows = widget.rows;

    // Collapsed if there is anything to collapse. An empty or short list needs
    // no affordance, and showing "Show all" beside six rows is noise.
    final bool collapsible = rows.length > kProductTableCollapsedRows;
    final List<ProductSalesRow> shown = _expanded || !collapsible
        ? rows
        : rows.sublist(0, kProductTableCollapsedRows);

    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SectionHeader(label: 'Top products'),
          // The count beside the title, so a collapsed card still says how big
          // the real list is rather than implying six is all of it.
          if (collapsible)
            Padding(
              padding: EdgeInsetsDirectional.only(
                start: spacing.md,
                end: spacing.md,
                bottom: spacing.sm,
              ),
              child: Text(
                AppLocalizations.of(context)
                    .analyticsTopProductsCount(rows.length),
                style: AppTypography.of(context).bodySmall?.copyWith(
                      color: colors.onSurfaceMuted,
                    ),
              ),
            ),
          if (shown.isEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(
                spacing.md,
                spacing.sm,
                spacing.md,
                spacing.md,
              ),
              child: Text(
                AppLocalizations.of(context).analyticsTopProductsEmpty,
                style: AppTypography.of(context).bodyMedium?.copyWith(
                      color: colors.onSurfaceMuted,
                    ),
              ),
            )
          else
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final bool wide =
                    constraints.maxWidth >= kProductTableWideWidth;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (wide)
                      _WideSortHeader(
                        sort: widget.sort,
                        ascending: widget.ascending,
                        onSort: widget.onSort,
                      )
                    else
                      Padding(
                        padding: EdgeInsetsDirectional.only(
                          start: spacing.md,
                          end: spacing.md,
                          bottom: spacing.sm,
                        ),
                        child: _NarrowSortControl(
                          sort: widget.sort,
                          ascending: widget.ascending,
                          onSort: widget.onSort,
                        ),
                      ),
                    Divider(height: 1, color: colors.outline),
                    for (final ProductSalesRow row in shown)
                      wide
                          ? _ProductTableRow(
                              row: row,
                              showDivider: row != shown.last,
                            )
                          : _ProductLine(
                              row: row,
                              showDivider: row != shown.last,
                            ),
                    if (collapsible) ...<Widget>[
                      Divider(height: 1, color: colors.outline),
                      _ShowAllRowsButton(
                        expanded: _expanded,
                        hidden: rows.length - shown.length,
                        onToggle: () => setState(() => _expanded = !_expanded),
                      ),
                    ],
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

/// The control that grows the list, and the count it is hiding.
class _ShowAllRowsButton extends StatelessWidget {
  const _ShowAllRowsButton({
    required this.expanded,
    required this.hidden,
    required this.onToggle,
  });

  final bool expanded;
  final int hidden;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TextButton(
      onPressed: onToggle,
      child: Text(expanded
          ? l10n.analyticsTopProductsShowLess
          : l10n.analyticsTopProductsShowMore(hidden)),
    );
  }
}

/// Five tappable column headers, with the sorted one showing an arrow.
class _WideSortHeader extends StatelessWidget {
  const _WideSortHeader({
    required this.sort,
    required this.ascending,
    required this.onSort,
  });

  final ProductSort sort;
  final bool ascending;
  final ValueChanged<ProductSort>? onSort;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: spacing.minTapTarget),
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          start: spacing.md,
          end: spacing.md,
          top: spacing.xs,
          bottom: spacing.xs,
        ),
        child: Row(
          children: <Widget>[
            for (final (ProductSort column, int flex) in _columns)
              Expanded(
                flex: flex,
                child: _SortCell(
                  column: column,
                  active: sort == column,
                  ascending: ascending,
                  onSort: onSort,
                  alignStart: column == ProductSort.name,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

const List<(ProductSort, int)> _columns = <(ProductSort, int)>[
  (ProductSort.name, 4),
  (ProductSort.units, 2),
  (ProductSort.revenue, 3),
  (ProductSort.profit, 3),
  (ProductSort.margin, 2),
];

/// One column header.
///
/// The arrow, not just the weight, says which way. Emphasis and colour alone
/// would leave a screen-reader user with no way to tell ascending from
/// descending, so the state is spelled out in the label too.
class _SortCell extends StatelessWidget {
  const _SortCell({
    required this.column,
    required this.active,
    required this.ascending,
    required this.onSort,
    required this.alignStart,
  });

  final ProductSort column;
  final bool active;
  final bool ascending;
  final ValueChanged<ProductSort>? onSort;
  final bool alignStart;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    // The arrow glyph is not decoration: it is the ONLY thing in the header
    // saying which way the sort runs, and a screen reader gets the words instead.
    // gen-l10n sorts the parameters ALPHABETICALLY — direction, label — which
    // is the reverse of the header's own order "{label}, sorted {direction}".
    final String spoken = active
        ? l10n.analyticsSortedBy(
            ascending
                ? l10n.analyticsSortedAscending
                : l10n.analyticsSortedDescending,
            column.label,
          )
        : l10n.analyticsNotSorted(column.label);

    final Widget label = Text(
      active ? '${column.label} ${ascending ? '↑' : '↓'}' : column.label,
      textAlign: alignStart ? TextAlign.start : TextAlign.end,
      style: (active ? type.labelLarge : type.bodySmall)?.copyWith(
        color: active ? colors.accent : colors.onSurfaceMuted,
      ),
    );

    if (onSort == null) {
      return Semantics(label: spoken, child: ExcludeSemantics(child: label));
    }

    return Semantics(
      button: true,
      selected: active,
      label: spoken,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: () => onSort!(column),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: label,
          ),
        ),
      ),
    );
  }
}

/// The same five sort targets, as a scrolling choice group.
///
/// [SegmentedChoice] scrolls rather than squeezes, which is what makes four
/// segments at 200% text scale survive a 360dp screen — and it names the group,
/// so a screen reader hears "Sort products by" instead of five loose buttons.
class _NarrowSortControl extends StatelessWidget {
  const _NarrowSortControl({
    required this.sort,
    required this.ascending,
    required this.onSort,
  });

  final ProductSort sort;
  final bool ascending;
  final ValueChanged<ProductSort>? onSort;

  @override
  Widget build(BuildContext context) {
    if (onSort == null) {
      return ExcludeSemantics(
        child: Text(
          'Sorted by ${sort.label} ${ascending ? 'ascending' : 'descending'}',
          style: AppTypography.of(context).bodySmall,
        ),
      );
    }
    return SegmentedChoice<ProductSort>(
      value: sort,
      onChanged: onSort!,
      semanticLabel: 'Sort products by ${sort.label}, '
          '${ascending ? 'ascending' : 'descending'}',
      options: <SegmentedOption<ProductSort>>[
        for (final ProductSort column in ProductSort.values)
          SegmentedOption<ProductSort>(
            value: column,
            label: column.label,
            icon: column == sort
                ? (ascending ? Icons.arrow_upward : Icons.arrow_downward)
                : null,
          ),
      ],
    );
  }
}

/// One product, as five aligned columns.
class _ProductTableRow extends StatelessWidget {
  const _ProductTableRow({required this.row, required this.showDivider});

  final ProductSalesRow row;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);

    final Widget content = Padding(
      padding: EdgeInsetsDirectional.only(
        start: spacing.md,
        end: spacing.md,
        top: spacing.sm,
        bottom: spacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(flex: 4, child: Text(row.productName)),
          Expanded(
            flex: 2,
            child: Text(
              _unitsLabel(row.units),
              textAlign: TextAlign.end,
              style: _figureStyle(context),
            ),
          ),
          Expanded(
            flex: 3,
            child: MoneyText(
              amount: formatMoney(row.revenue),
              size: 13,
              textAlign: TextAlign.end,
            ),
          ),
          Expanded(
            flex: 3,
            child: MoneyText(
              amount: formatMoney(row.profit),
              size: 13,
              textAlign: TextAlign.end,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              row.marginLabel,
              textAlign: TextAlign.end,
              style: _figureStyle(context),
            ),
          ),
        ],
      ),
    );

    return Semantics(
      container: true,
      // gen-l10n sorts the parameters ALPHABETICALLY — margin, product, profit,
      // revenue, units — which is not the order the sentence reads them in.
      // Every one was bound to the wrong placeholder, so the whole row was
      // scrambled.
      label: AppLocalizations.of(context).analyticsRowSpokenFull(
        row.marginLabel,
        row.productName,
        formatMoney(row.profit),
        formatMoney(row.revenue),
        _unitsLabel(row.units),
      ),
      excludeSemantics: true,
      child: ExcludeSemantics(
        child: showDivider
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  content,
                  Divider(height: 1, color: colors.outline),
                ],
              )
            : content,
      ),
    );
  }
}

/// One product, as a name with a figure beside it and the rest of the figures
/// under it.
///
/// The narrow form of the same five numbers. Nothing is dropped and nothing is
/// truncated: a product name wraps instead of being ellipsised, because a
/// truncated product name in a report is a defect, not a design.
class _ProductLine extends StatelessWidget {
  const _ProductLine({required this.row, required this.showDivider});

  final ProductSalesRow row;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);

    final Widget content = Padding(
      padding: EdgeInsetsDirectional.only(
        start: spacing.md,
        end: spacing.md,
        top: spacing.sm,
        bottom: spacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: Text(row.productName, style: type.bodyMedium)),
              SizedBox(width: spacing.sm),
              MoneyText(amount: formatMoney(row.revenue), size: 14),
            ],
          ),
          SizedBox(height: spacing.xs),
          Text(
            // gen-l10n sorts these three ALPHABETICALLY — margin, profit,
            // units — so the margin leads even though the units read first.
            AppLocalizations.of(context).analyticsRowSpokenCompact(
                row.marginLabel,
                formatMoney(row.profit),
                _unitsLabel(row.units)),
            style: _tabularSmallStyle(context),
          ),
        ],
      ),
    );

    return showDivider
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              content,
              Divider(height: 1, color: colors.outline),
            ],
          )
        : content;
  }
}

/// A figure that is compared down a column: tabular, small, secondary.
TextStyle _figureStyle(BuildContext context) => AppTypography.money(
      context,
      size: 13,
      weight: FontWeight.w600,
    ).copyWith(color: AppColors.of(context).onSurfaceVariant);

/// The same treatment one step down the scale: body text that still must not
/// reflow, because these figures sit under a number they are read against.
TextStyle _tabularSmallStyle(BuildContext context) =>
    (AppTypography.of(context).bodySmall ?? const TextStyle()).copyWith(
      fontFeatures: AppTypography.tabular,
      color: AppColors.of(context).onSurfaceVariant,
    );

/// How the money came in, by tender.
///
/// The chart carries the shape — which tender dominates — and the rows beneath
/// carry the exact figures, right-aligned with tabular numbers so a manager can
/// compare them down the column. A chart alone cannot be read to the shilling.
/// A payment method's own colour.
///
/// Each tender keeps its identity as a colour where it has one — M-Pesa green,
/// Airtel red, Equitel blue — and takes a neutral tone where it has none, so the
/// ring is a picture of which tenders a shop actually uses rather than five
/// arbitrary hues. The legend underneath names every slice, so the colour is
/// never the only thing identifying a tender.
Color _tenderColor(String method, AppColors colors) => switch (method) {
      'cash' => colors.cashNeutral,
      'mpesa' => colors.mpesaGreen,
      'airtel' => colors.airtelRed,
      'equitel' => colors.equitelBlue,
      'card' => colors.info,
      'bank_transfer' => colors.accent,
      'mobile_money_manual' => colors.warning,
      _ => colors.onSurfaceMuted,
    };

/// How the money came in, by tender.
///
/// A RING and its legend, not a stack of bars: the question a manager opens this
/// card with is "is this shop cash-heavy or mobile-money-heavy" — a share of the
/// whole, which a ring answers at a glance and a list of bars answers only after
/// comparing every row. The rows underneath still carry the exact figures, so
/// nothing is lost by preferring the shape.
class PaymentMixCard extends StatelessWidget {
  const PaymentMixCard({required this.rows, required this.totals, super.key});

  final List<PaymentMixRow> rows;
  final DailyTotals totals;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);

    final slices = <PosPieSlice>[
      for (final row in rows)
        PosPieSlice(
          label: row.label,
          value: row.salesMinor,
          color: _tenderColor(row.method, colors),
          valueLabel: formatMoney(row.sales),
        ),
    ];

    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SectionHeader(label: l10n.analyticsPaymentMethodsSection),
          if (rows.isEmpty)
            Padding(
              padding: EdgeInsetsDirectional.only(
                start: spacing.md,
                end: spacing.md,
                top: spacing.sm,
                bottom: spacing.md,
              ),
              child: Text(
                l10n.analyticsNothingTaken,
                style: AppTypography.of(context).bodyMedium?.copyWith(
                      color: colors.onSurfaceMuted,
                    ),
              ),
            )
          else ...<Widget>[
            Padding(
              padding: EdgeInsetsDirectional.only(
                start: spacing.md,
                end: spacing.md,
              ),
              // The ring's own spoken form is the payment-mix sentence, so a
              // screen reader gets the same share figures the rows below show.
              child: PosPieChart(
                title: '',
                slices: slices,
                semanticsLabel: describePaymentMix(rows, totals.totalMinor),
                centerLabel: l10n.analyticsPaymentMixTotal,
                centerValue: formatMoney(totals.total),
                size: 116,
              ),
            ),
            SizedBox(height: spacing.sm),
            Divider(height: 1, color: colors.outline),
            for (int i = 0; i < rows.length; i++)
              _PaymentMixRow(
                row: rows[i],
                rangeTotalMinor: totals.totalMinor,
                showDivider: i != rows.length - 1,
              ),
          ],
        ],
      ),
    );
  }
}

class _PaymentMixRow extends StatelessWidget {
  const _PaymentMixRow({
    required this.row,
    required this.rangeTotalMinor,
    required this.showDivider,
  });

  final PaymentMixRow row;
  final int rangeTotalMinor;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);

    final String share = '${row.sharePct(rangeTotalMinor).toStringAsFixed(0)}%';

    final Widget content = Padding(
      padding: EdgeInsetsDirectional.only(
        start: spacing.md,
        end: spacing.md,
        top: spacing.sm,
        bottom: spacing.sm,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              row.label,
              style: AppTypography.of(context).bodyMedium,
            ),
          ),
          SizedBox(width: spacing.sm),
          Text(share, style: _figureStyle(context)),
          SizedBox(width: spacing.md),
          MoneyText(amount: formatMoney(row.sales), size: 13),
        ],
      ),
    );

    return Semantics(
      container: true,
      // Alphabetical: gen-l10n orders the generated parameters by name, and
      // l10n.dart documents that these getters are positional by design.
      label: l10n.analyticsPaymentRowSpoken(
        formatMoney(row.sales),
        row.transactions,
        row.label,
        share,
      ),
      excludeSemantics: true,
      child: ExcludeSemantics(
        child: showDivider
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  content,
                  Divider(height: 1, color: colors.outline),
                ],
              )
            : content,
      ),
    );
  }
}

/// Out of stock first, then what is running low.
class StockSection extends StatelessWidget {
  const StockSection({
    required this.outOfStock,
    required this.lowStock,
    super.key,
  });

  static const int shown = 10;

  final List<Product> outOfStock;
  final List<Product> lowStock;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);

    final bool nothingToSay = outOfStock.isEmpty && lowStock.isEmpty;

    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SectionHeader(
              label: AppLocalizations.of(context).inventoryFieldStock),
          if (nothingToSay)
            Padding(
              padding: EdgeInsets.fromLTRB(
                spacing.md,
                spacing.sm,
                spacing.md,
                spacing.md,
              ),
              child: Text(
                'Everything is above its reorder level.',
                style: AppTypography.of(context).bodyMedium?.copyWith(
                      color: colors.onSurfaceMuted,
                    ),
              ),
            )
          else ...<Widget>[
            if (outOfStock.isNotEmpty)
              _StockList(
                tone: StatusTone.danger,
                label: AppLocalizations.of(context).sellOutOfStock,
                products: outOfStock.take(shown).toList(),
                total: outOfStock.length,
                showDivider: lowStock.isNotEmpty,
              ),
            if (lowStock.isNotEmpty)
              _StockList(
                tone: StatusTone.warning,
                label: 'Running low',
                products: lowStock.take(shown).toList(),
                total: lowStock.length,
                showDivider: false,
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                spacing.md,
                spacing.sm,
                spacing.md,
                spacing.md,
              ),
              child: const OpenInventoryAction(),
            ),
          ],
        ],
      ),
    );
  }
}

/// One urgency band, named, counted, and listed.
///
/// The band header carries the state three ways — [StatusTone]'s glyph, its
/// word, and its colour — so "out of stock" is never a row of red text that a
/// colour-blind reader cannot find. The count is on the header rather than
/// behind a list the reader has to count.
class _StockList extends StatelessWidget {
  const _StockList({
    required this.tone,
    required this.label,
    required this.products,
    required this.total,
    required this.showDivider,
  });

  final StatusTone tone;
  final String label;
  final List<Product> products;
  final int total;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);

    final Widget rows = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final Product product in products)
          Padding(
            padding: EdgeInsetsDirectional.only(
              start: spacing.md,
              end: spacing.md,
              top: spacing.xs,
              bottom: spacing.xs,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(child: Text(product.name)),
                SizedBox(width: spacing.sm),
                Text(
                  '${_stockLabel(product.stockQty)} left',
                  style: _figureStyle(context).copyWith(
                    color: tone.color(colors),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        if (total > products.length)
          Padding(
            padding: EdgeInsetsDirectional.only(
              start: spacing.md,
              end: spacing.md,
              top: spacing.xs,
              bottom: spacing.sm,
            ),
            child: Text(
              'and ${total - products.length} more',
              style: AppTypography.of(context).bodySmall,
            ),
          ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: EdgeInsetsDirectional.only(
            start: spacing.md,
            end: spacing.md,
            top: spacing.sm,
            bottom: spacing.sm,
          ),
          child: Row(
            children: <Widget>[
              StatusChip(tone: tone, text: label),
              SizedBox(width: spacing.sm),
              CountBadge(
                count: total,
                noun: total == 1 ? 'product' : 'products',
                tone: tone,
              ),
            ],
          ),
        ),
        rows,
        if (showDivider) Divider(height: 1, color: colors.outline),
      ],
    );
  }
}
