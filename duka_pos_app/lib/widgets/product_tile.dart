// The till's product tile, and the grid that lays it out.
//
// WHY THE GRID SIZES ITS CELLS FROM THE CONTENT
//
// The grid used to fix a cell's shape with `childAspectRatio: 1.2` — a guess
// about how much text a cell holds. A guess is a promise the layout cannot
// keep. At 360dp a two-column cell is 168 wide and 140 tall, and a tile with
// a photograph, a two-line name, a price and a stock line needs closer to
// 190. The name is a `Flexible`, so it is the name that gets squeezed — all
// the way to nothing — and the rest of the column spills over the edge into
// the stripes that mean "this app is broken" to every shopkeeper who has put
// a photograph on their products.
//
// So the cell's height is computed from the text it actually holds, at the
// text scale actually in force. The price and the stock count are MEASURED
// rather than assumed: a price that wraps to two lines at 150% text needs two
// lines of room, and a price is never truncated to make it fit — a clipped
// price is a wrong price.
//
// A grid is a promise about rhythm. If the tiles are not all the same shape,
// the grid is not a grid.
//
// WHY THE MEASUREMENT IS CACHED
//
// Measuring a string means laying it out, and the till grid is rebuilt on
// every keystroke in the search box. A price's width does not change, so it is
// measured once and remembered. The cache key carries the SCALED size,
// because the same price at 200% text is a different width.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/product_photo.dart';
import '../ui/components/status.dart';
import '../ui/components/surface.dart';
import '../ui/layout/page.dart';
import '../utils/money.dart';

/// One product, as the till grid draws it.
///
/// A value rather than a lookup into the screen's state: the grid needs the
/// variant summary, the cart count and the tap rule for every product, and
/// handing the grid the catalogue and the cart and letting it work them out
/// would put the screen's rules in the widget.
@immutable
class ProductTileData {
  const ProductTileData({
    required this.product,
    required this.inCart,
    required this.sellsAsVariants,
    required this.variantCount,
    required this.cheapestPrice,
    required this.canTap,
  });

  final Product product;

  /// How much of this product is already in the cart.
  final double inCart;

  /// Whether the product is sold as variants rather than as itself.
  final bool sellsAsVariants;

  /// How many variants it has.
  final int variantCount;

  /// The cheapest variant's price, when the product is sold as variants.
  final Money? cheapestPrice;

  /// Whether the tile can be tapped at all. An out-of-stock product is still
  /// SHOWN — the cashier needs to see that it exists and that it is out — but
  /// it is not something to tap.
  final bool canTap;

  /// The price line, exactly as the tile shows it.
  ///
  /// Shared with the grid, which measures this string to size the cell. Two
  /// copies of the same sentence would drift, and the drift would show up as a
  /// tile whose text is clipped by a cell sized for a different sentence.
  String priceLine(AppLocalizations l10n) {
    if (!sellsAsVariants) return formatMoney(product.sellPrice);
    final Money? cheapest = cheapestPrice;
    if (cheapest == null) return l10n.sellTileNoVariants;
    return l10n.sellTileFromPrice(formatMoney(cheapest));
  }

  /// The stock line, exactly as the tile shows it.
  String stockLine(AppLocalizations l10n) =>
      l10n.sellTileStockCount(stockText(product.stockQty));

  /// A stock count, as a cashier reads it.
  ///
  /// A bottle sold by weight is 0.4 or 2.5, and `round()` turned 0.4 into "0 in
  /// stock" — on a tile that was still tappable, which is a lie in the one
  /// place the cashier is deciding whether to sell it. And 2.5 read as "3" is
  /// a bottle charged for that was never counted.
  static String stockText(double qty) {
    if (qty % 1 == 0) return qty.toInt().toString();
    return qty.toStringAsFixed(1);
  }
}

/// The height the till grid's cells need.
///
/// Public because the number is a promise the layout makes to the eye, and a
/// promise nobody can check is a promise nobody keeps. A test drives this with
/// the same inputs the grid uses.
@immutable
class ProductTileMetrics {
  const ProductTileMetrics({
    required this.contentWidth,
    required this.nameLineHeight,
    required this.priceLineHeight,
    required this.stockLineHeight,
    required this.photoEdge,
    required this.frameInset,
    required this.gap,
  });

  /// The width the tile's text gets: the cell, less the card's padding and the
  /// tile's own.
  final double contentWidth;

  /// The height of one line of the product's name.
  final double nameLineHeight;

  /// The height of one line of the price.
  final double priceLineHeight;

  /// The height of one line of the stock count.
  final double stockLineHeight;

  /// The square edge of the photograph.
  final double photoEdge;

  /// The padding around the tile's content: the card's own and the tile's.
  final double frameInset;

  /// The space between the tile's blocks.
  final double gap;

  /// The width the stock line's TEXT gets, once the icon beside it has taken
  /// its share.
  double get stockTextWidth =>
      math.max(0, contentWidth - ProductTile.stockIconSize - gap);

  /// The height of a cell holding a tile with these contents.
  ///
  /// The name's budget is fixed at two lines because the name is the one thing
  /// in the tile that is allowed to be cut short, and it says so with an
  /// ellipsis. Everything else is measured.
  double heightFor({
    required bool hasPhoto,
    required int priceLines,
    required int stockLines,
  }) {
    final double photo = hasPhoto ? photoEdge + gap : 0;
    final double name = nameLineHeight * ProductTile.nameLines;
    final double price = priceLineHeight * priceLines;
    final double stock = stockLineHeight * stockLines;
    return frameInset + photo + name + gap + price + gap + stock;
  }

  /// The metrics for a cell of [cellWidth] at the ambient text scale.
  factory ProductTileMetrics.of(
    BuildContext context, {
    required double cellWidth,
  }) {
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);
    final TextScaler scaler = MediaQuery.textScalerOf(context);

    // The card's padding and the tile's own, in the tokens — never as
    // literals, because the tile and the measurement have to agree exactly or
    // the cell is a few pixels short of the text it holds.
    final double cardInset = spacing.md;
    final double tileInset = spacing.sm;
    final double content = cellWidth - cardInset * 2 - tileInset * 2;

    return ProductTileMetrics(
      contentWidth: content,
      nameLineHeight: _lineHeight(type.titleSmall, scaler),
      priceLineHeight: _lineHeight(
        AppTypography.money(
          context,
          size: ProductTile.priceFontSize,
          weight: FontWeight.w700,
        ),
        scaler,
      ),
      stockLineHeight: _lineHeight(type.labelSmall, scaler),
      // The photograph is a THUMBNAIL, not a picture. It is there so the
      // cashier can match a bottle against the shelf, and it is capped so a
      // two-column grid on a 360dp phone is not mostly photograph.
      photoEdge:
          content.clamp(ProductTile.photoMinEdge, ProductTile.photoMaxEdge),
      frameInset: cardInset * 2 + tileInset * 2,
      gap: spacing.xs,
    );
  }

  /// The height of one line of [style] at [scaler].
  ///
  /// A line is the scaled font size times the style's own line height, which
  /// is exactly what the framework lays out. Measuring it here rather than
  /// guessing keeps the cell and the text in step at every text scale.
  static double _lineHeight(TextStyle? style, TextScaler scaler) {
    final TextStyle resolved = style ?? const TextStyle();
    final double size = scaler.scale(resolved.fontSize ?? 14);
    return size * (resolved.height ?? 1.2);
  }
}

/// A product in the till grid.
///
/// One node for the whole tile: a cashier stepping through the grid with
/// TalkBack should hear "Kenyatta bread, KSh 60, 12 in stock, adds it to the
/// cart", not four separate stops for name, price, count and action.
class ProductTile extends StatelessWidget {
  const ProductTile({required this.data, this.onTap, super.key});

  final ProductTileData data;
  final VoidCallback? onTap;

  /// The name's line budget. The name is the one thing in the tile that may be
  /// cut short, and it says so with an ellipsis rather than a hard clip.
  static const int nameLines = 2;

  /// The stock line's line budget.
  static const int stockLines = 2;

  /// The price's size, in the design system's scale.
  static const double priceFontSize = 14;

  /// The edge of the photograph.
  static const double photoMinEdge = 40;
  static const double photoMaxEdge = 56;

  /// The icon beside the stock count.
  static const double stockIconSize = 12;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);

    final String priceLine = data.priceLine(l10n);
    final String stockLine = data.stockLine(l10n);

    final String spoken = data.sellsAsVariants
        ? l10n.sellTileSpokenVariants(
            data.product.name,
            data.cheapestPrice == null
                ? l10n.sellTileNoVariants
                : formatMoney(data.cheapestPrice!),
            l10n.sellVariantCount(data.variantCount),
            stockLine,
          )
        : l10n.sellTileSpokenProduct(
            data.product.name,
            formatMoney(data.product.sellPrice),
            stockLine,
          );

    return Semantics(
      // An out-of-stock tile is STILL a button. It used to be announced as
      // plain text with no action at all, and tapping it did nothing — the
      // cashier pressed a product, the screen ignored them, and the only
      // conclusion available was that the till was broken. A tile that cannot
      // be sold can still EXPLAIN itself, and that is what the tap is for.
      button: true,
      label: spoken,
      // The hint says what the tap DOES, not how to perform it. "Double tap to
      // add" repeats what the platform already announces on every button, and
      // it says nothing about what the tap is FOR.
      hint: !data.canTap
          ? l10n.sellOutOfStockHint
          : data.sellsAsVariants
              ? l10n.sellTileHintChoosesVariant
              : l10n.sellTileHintAddsToCart,
      excludeSemantics: true,
      child: ExcludeSemantics(
        child: SurfaceCard(
          onTap: onTap,
          child: Stack(
            children: <Widget>[
              Padding(
                padding: EdgeInsets.all(spacing.sm),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    // The photograph, when there is one.
                    //
                    // At the till it is the thing a cashier matches against
                    // the shelf, so it is the biggest thing on the tile.
                    //
                    // The row's `updated_at` comes with it: a photograph that
                    // was replaced is written over the file at the SAME path,
                    // and the tile would otherwise go on drawing the old
                    // picture. The row is what says the file is new.
                    if (data.product.imagePath != null) ...<Widget>[
                      LayoutBuilder(
                        builder:
                            (BuildContext context, BoxConstraints constraints) {
                          final double edge = constraints.maxWidth.clamp(
                            photoMinEdge,
                            photoMaxEdge,
                          );
                          return ProductPhoto(
                            imagePath: data.product.imagePath,
                            size: edge,
                            revision: data.product.updatedAt,
                          );
                        },
                      ),
                      SizedBox(height: spacing.xs),
                    ],
                    Flexible(
                      child: Text(
                        data.product.name,
                        textAlign: TextAlign.center,
                        maxLines: nameLines,
                        // Ellipsis, not `visible`.
                        //
                        // `visible` was defended in a comment as "no ellipsis
                        // here, the product would be spelled with a trailing
                        // dot", and it pointed at the overflow matrix as the
                        // guard. But that matrix only exercises
                        // ui/components/ and page.dart — nothing in this file.
                        // So a 120-character name (the editor's own limit,
                        // models.dart) rendered as `maxLines` lines with NO
                        // ellipsis at all: `TextPainter` silently drops lines
                        // past `maxLines`, and a cashier saw a name cut
                        // mid-word with nothing saying text was lost.
                        //
                        // An ellipsis IS the signal. It is read by screen
                        // readers as "text truncated", which is exactly the
                        // truth, and the tile's `Semantics` label above carries
                        // the full name for whoever needs it spoken.
                        overflow: TextOverflow.ellipsis,
                        style: type.titleSmall,
                      ),
                    ),
                    SizedBox(height: spacing.xs),
                    Text(
                      priceLine,
                      textAlign: TextAlign.center,
                      // Tabular figures: a column of prices that shifts
                      // sideways as the digit count changes cannot be scanned.
                      // No `maxLines` and no ellipsis: a price that does not
                      // fit is a layout bug to fix with a taller cell, not a
                      // number to truncate.
                      style: AppTypography.money(
                        context,
                        size: priceFontSize,
                        weight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: spacing.xs),
                    _StockLine(
                      text: stockLine,
                      isLow: data.product.isLow,
                    ),
                  ],
                ),
              ),
              if (data.inCart > 0)
                PositionedDirectional(
                  top: spacing.xs,
                  end: spacing.xs,
                  child: _CartCountPip(count: data.inCart),
                ),
              if (!data.canTap)
                Positioned.fill(
                  child: DecoratedBox(
                    // A scrim rather than a disabled colour on the text: the
                    // contents stay legible so the cashier can still read WHAT
                    // is out of stock, which is the information they need.
                    decoration: BoxDecoration(
                      color: colors.canvas.withValues(alpha: 0.72),
                      borderRadius: AppShapes.of(context).controlRadius,
                    ),
                    child: Center(
                      child: StatusChip(
                        tone: StatusTone.danger,
                        text: AppLocalizations.of(context).sellOutOfStock,
                        dense: true,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The stock line: an icon and the count, as one group.
///
/// The icon carries the tone and the WORD carries the fact, so the line is
/// legible in greyscale, to a deuteranopic cashier, and to a screen reader.
///
/// A Row in its minimum size hands its children UNBOUNDED width, so a stock
/// line wider than the tile is laid out at its full length and clipped
/// mid-word — with no overflow error to catch it, because the clip is silent.
/// The constraint below is what stops that: the text wraps inside the width
/// the tile actually has, and the cell was sized for the wrapped height.
class _StockLine extends StatelessWidget {
  const _StockLine({required this.text, required this.isLow});

  final String text;
  final bool isLow;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double textWidth = math.max(
          0,
          constraints.maxWidth - ProductTile.stockIconSize - spacing.xs,
        );

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              isLow ? StatusTone.warning.icon : StatusTone.success.icon,
              size: ProductTile.stockIconSize,
              color: isLow ? colors.warning : colors.success,
            ),
            SizedBox(width: spacing.xs),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: textWidth),
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: type.labelSmall?.copyWith(
                  color: isLow ? colors.warning : colors.onSurfaceMuted,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The count of this product in the cart, on the tile's corner.
class _CartCountPip extends StatelessWidget {
  const _CartCountPip({required this.count});

  final double count;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String label = count == count.roundToDouble()
        ? '${count.toInt()}'
        : count.toStringAsFixed(1);

    return Semantics(
      label: l10n.sellTileCartCount(label),
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 5),
        decoration: BoxDecoration(
          color: colors.accent,
          shape: BoxShape.circle,
        ),
        child: Text(
          label,
          style: AppTypography.of(context).labelSmall?.copyWith(
                color: colors.onAccent,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
        ),
      ),
    );
  }
}

/// The catalogue grid at the till.
///
/// The cell's height comes from the content (see [ProductTileMetrics]), so the
/// grid never clips a tile — at 360dp with a photograph on the products, at
/// 200% text, or with a price long enough to wrap.
class ProductTileGrid extends StatefulWidget {
  const ProductTileGrid({
    required this.items,
    required this.onTap,
    this.padding,
    super.key,
  });

  final List<ProductTileData> items;

  /// Called with the product that was tapped.
  final void Function(Product product) onTap;

  final EdgeInsetsGeometry? padding;

  @override
  State<ProductTileGrid> createState() => _ProductTileGridState();
}

class _ProductTileGridState extends State<ProductTileGrid> {
  /// The gap between cells, and the padding around the grid.
  static const double _gap = 8;

  /// The narrowest a cell may be before the grid drops a column.
  static const double _minCellWidth = 170;

  /// The most columns a phone-sized grid will ever show.
  static const int _maxColumns = 3;

  /// Measured line counts, keyed by the string, the width it was measured at
  /// and the scaled size it was measured with.
  final Map<String, int> _lineCounts = <String, int>{};

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme type = AppTypography.of(context);
    final TextScaler scaler = MediaQuery.textScalerOf(context);
    final TextStyle priceStyle = AppTypography.money(
      context,
      size: ProductTile.priceFontSize,
      weight: FontWeight.w700,
    );
    final TextStyle stockStyle = type.labelSmall ?? const TextStyle();

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // From the shared breakpoint vocabulary, so the catalogue grid breaks
        // at the SAME widths as the shell's navigation affordance. A local
        // `maxWidth < 480` is how a phone gets three columns while the bottom
        // bar says it is a small phone.
        final int columns = AdaptiveGrid.columnsFor(
          available: constraints.maxWidth,
          gap: _gap,
          minCellWidth: _minCellWidth,
          maxColumns: _maxColumns,
        );

        final double cellWidth =
            (constraints.maxWidth - _gap * 2 - _gap * (columns - 1)) / columns;

        final ProductTileMetrics metrics =
            ProductTileMetrics.of(context, cellWidth: cellWidth);

        // The tallest tile in the grid sets the row height. Every cell is the
        // same height, because a grid whose cells differ is not a grid.
        int priceLines = 1;
        int stockLines = 1;
        bool hasPhoto = false;

        for (final ProductTileData item in widget.items) {
          hasPhoto = hasPhoto || item.product.imagePath != null;
          priceLines = math.max(
            priceLines,
            _linesFor(
              text: item.priceLine(l10n),
              style: priceStyle,
              width: metrics.contentWidth,
              scaler: scaler,
            ),
          );
          stockLines = math.max(
            stockLines,
            _linesFor(
              text: item.stockLine(l10n),
              style: stockStyle,
              width: metrics.stockTextWidth,
              scaler: scaler,
            ),
          );
        }

        final double cellHeight = metrics.heightFor(
          hasPhoto: hasPhoto,
          priceLines: priceLines,
          stockLines: stockLines,
        );

        return GridView.builder(
          padding: const EdgeInsets.all(_gap),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            // The cell's height, from its content. Not a ratio of its width:
            // a ratio is a guess about how much text a cell holds, and a guess
            // is wrong the moment the text scale moves.
            mainAxisExtent: cellHeight,
            crossAxisSpacing: _gap,
            mainAxisSpacing: _gap,
          ),
          itemCount: widget.items.length,
          itemBuilder: (BuildContext context, int index) {
            final ProductTileData item = widget.items[index];
            return ProductTile(
              data: item,
              // Always tappable: see the Semantics note above.
              onTap: () => widget.onTap(item.product),
            );
          },
        );
      },
    );
  }

  /// How many lines [text] takes at [width] in [style].
  ///
  /// Measured, not guessed: a price that wraps to two lines at 150% text
  /// needs two lines of room, and a price is never truncated to make it fit.
  ///
  /// Cached, because measuring means laying the text out and the grid is
  /// rebuilt on every keystroke in the search box. The key carries the scaled
  /// size, because the same string at 200% text is a different width.
  int _linesFor({
    required String text,
    required TextStyle style,
    required double width,
    required TextScaler scaler,
  }) {
    final double scaled = scaler.scale(style.fontSize ?? 14);
    final String key = '$scaled|${width.round()}|${style.fontSize}|$text';

    final int? cached = _lineCounts[key];
    if (cached != null) return cached;

    final TextPainter painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: scaler,
    )..layout(maxWidth: width);
    final int lines = painter.computeLineMetrics().length;
    painter.dispose();

    // A cache that grows without bound is a slow leak; a catalogue's worth of
    // prices is a few hundred entries, so the ceiling is generous and the
    // reset is cheap.
    if (_lineCounts.length > 1024) _lineCounts.clear();
    _lineCounts[key] = lines;
    return lines;
  }
}
