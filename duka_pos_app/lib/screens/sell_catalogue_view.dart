// What can be sold, and the two ways to reach it.
//
// Two ways because a till has two hands and two kinds of operator: a thumb on
// tiles, and a hardware scanner wedging keystrokes into the field. The search
// field is deliberately narrow and left alone by the wedge buffer, so typing a
// product name is never mistaken for a scan.
//
// Rows, not a grid. A product name that wraps has to be able to grow its tile,
// and a grid cell cannot: either it clips the name or it needs a fixed height
// that clips it at 200% text scale. A packed row grows, scans as a single
// column of names and prices, and keeps every target at the full 44px.

import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/controls.dart';
import '../ui/components/states.dart';
import '../ui/components/status.dart';

/// What the catalogue pane is showing, resolved once.
///
/// One value, one switch. A pair of `isLoading` and `isEmpty` booleans cannot
/// distinguish "nothing added yet" from "your search matched nothing", and a
/// cashier told they have no products when they mistyped a search stops
/// selling.
enum CataloguePhase {
  loading,
  failed,
  empty,
  filteredEmpty,
  content,
}

/// One product row, resolved before it reaches a widget.
///
/// Every string here is already formatted. `MoneyText` owns how an amount is
/// painted; this owns the text it is given, so no widget below has to decide
/// what a price looks like.
@immutable
class ProductTileData {
  const ProductTileData({
    required this.productId,
    required this.name,
    required this.category,
    required this.price,
    required this.priceSpoken,
    required this.stockLabel,
    required this.stockTone,
    required this.canAdd,
    required this.semanticLabel,
    required this.inCartLines,
    required this.inCartUnits,
    required this.variantCount,
  });

  /// Stable identity, so a tap resolves a product rather than whatever happened
  /// to be at that position after the list rebuilt.
  final int productId;

  final String name;
  final String category;

  /// "KSh 120", or "From KSh 60" for a product only sold as variants.
  final String price;

  /// The same figure without the "From", for the composed announcement.
  final String priceSpoken;

  /// "12 in stock", "Low · 4 left", "Out of stock".
  final String stockLabel;

  final StatusTone stockTone;

  /// False only when the product is genuinely unsellable right now. A variant
  /// product stays tappable even at zero parent stock, because its own variants
  /// may hold stock.
  final bool canAdd;

  /// The whole row as one phrase: name, price, stock, and what is in the cart.
  final String semanticLabel;

  final int inCartLines;
  final double inCartUnits;

  /// 0 for a product sold in whole, halves and quarters.
  final int variantCount;
}

/// One category in the master column.
@immutable
class CategoryTileData {
  const CategoryTileData({
    required this.label,
    required this.count,
    required this.isAll,
  });

  final String label;
  final int count;

  /// The synthetic "everything" row, which is the way out of the filter.
  final bool isAll;
}

/// The catalogue pane: search, scan, and the list of what can be sold.
class SellCataloguePane extends StatelessWidget {
  const SellCataloguePane({
    required this.phase,
    required this.tiles,
    required this.categories,
    required this.selectedCategory,
    required this.showCategoryMaster,
    required this.searchController,
    required this.query,
    required this.onQueryChanged,
    required this.onClearQuery,
    required this.onProductSelected,
    required this.onCategorySelected,
    required this.onScan,
    required this.onRetry,
    super.key,
  });

  final CataloguePhase phase;
  final List<ProductTileData> tiles;

  /// Null when the master column is not shown.
  final List<CategoryTileData> categories;
  final String? selectedCategory;

  /// Whether there is room for the master column beside the list.
  final bool showCategoryMaster;

  final TextEditingController searchController;
  final String query;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClearQuery;

  /// Resolves a product id. Never a captured product, which a rebuild could
  /// have replaced with a newer copy of.
  final ValueChanged<int> onProductSelected;

  final ValueChanged<String?> onCategorySelected;
  final VoidCallback onScan;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: EdgeInsetsDirectional.only(
            start: spacing.md,
            end: spacing.md,
            top: spacing.sm,
            bottom: spacing.sm,
          ),
          child: SellSearchField(
            controller: searchController,
            query: query,
            onChanged: onQueryChanged,
            onClear: onClearQuery,
          ),
        ),
        Padding(
          padding: EdgeInsetsDirectional.only(
            start: spacing.md,
            end: spacing.md,
            bottom: spacing.sm,
          ),
          // Camera scanning is an explicit action, never an automatic one: a
          // till with a wedge scanner needs nothing from the camera, and a
          // phone held over the counter should not open a camera view by
          // itself.
          child: SellScanButton(onPressed: onScan),
        ),
        Expanded(
          child: switch (phase) {
            CataloguePhase.loading => SkeletonList(
                itemCount: 7,
                itemBuilder: (BuildContext context, int index) =>
                    _CatalogueSkeletonRow(
                  showCategory: !showCategoryMaster,
                ),
              ),
            CataloguePhase.failed => ErrorStateView(
                message:
                    AppLocalizations.of(context).sellCatalogueLoadFailedMessage,
                detail:
                    AppLocalizations.of(context).sellCatalogueLoadFailedDetail,
                retryLabel:
                    AppLocalizations.of(context).sellReloadCatalogueAction,
                onRetry: onRetry,
              ),
            CataloguePhase.empty => EmptyStateView(
                kind: EmptyKind.collection,
                title: AppLocalizations.of(context).sellCatalogueEmptyTitle,
                message: AppLocalizations.of(context).sellCatalogueEmptyMessage,
                secondaryActionLabel:
                    AppLocalizations.of(context).sellReloadCatalogueAction,
                onSecondaryAction: onRetry,
              ),
            CataloguePhase.filteredEmpty => EmptyStateView(
                kind: EmptyKind.filtered,
                title: _noMatchTitle(
                  AppLocalizations.of(context),
                  query,
                  selectedCategory,
                ),
                message: AppLocalizations.of(context).sellNoMatchMessage,
                actionLabel: AppLocalizations.of(context).sellClearFilterAction,
                onAction: onClearQuery,
              ),
            CataloguePhase.content => _CatalogueBody(
                tiles: tiles,
                categories: categories,
                selectedCategory: selectedCategory,
                showCategoryMaster: showCategoryMaster,
                onProductSelected: onProductSelected,
                onCategorySelected: onCategorySelected,
              ),
          },
        ),
      ],
    );
  }
}

/// The list, and the master column it gains room for.
class _CatalogueBody extends StatelessWidget {
  const _CatalogueBody({
    required this.tiles,
    required this.categories,
    required this.selectedCategory,
    required this.showCategoryMaster,
    required this.onProductSelected,
    required this.onCategorySelected,
  });

  final List<ProductTileData> tiles;
  final List<CategoryTileData> categories;
  final String? selectedCategory;
  final bool showCategoryMaster;
  final ValueChanged<int> onProductSelected;
  final ValueChanged<String?> onCategorySelected;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);

    final Widget list = ListView.builder(
      padding: EdgeInsetsDirectional.only(bottom: spacing.md),
      itemCount: tiles.length,
      itemBuilder: (BuildContext context, int index) {
        final ProductTileData tile = tiles[index];
        return ProductRow(
          tile: tile,
          // The category is only worth a line under the name when there is no
          // column saying it already.
          showCategory: !showCategoryMaster,
          onTap: tile.canAdd ? () => onProductSelected(tile.productId) : null,
        );
      },
    );

    if (!showCategoryMaster) return list;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Proportional, then capped. `Flexible` splits the pane against the
        // list by ratio; the cap stops a very wide window from turning the
        // master column into a field of empty space.
        Flexible(
          flex: 2,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: SellCategoryMaster(
              categories: categories,
              selected: selectedCategory,
              onSelected: onCategorySelected,
            ),
          ),
        ),
        VerticalDivider(width: spacing.hairline, color: colors.outline),
        Expanded(flex: 5, child: list),
      ],
    );
  }
}

/// One product: name, category, price, stock, and what is already in the cart.
///
/// Three channels for stock, none of them colour: the chip's glyph shape, the
/// word beside it, and the weight that rises with severity. A tile that cannot
/// be tapped still says so in words rather than only going quiet.
class ProductRow extends StatelessWidget {
  const ProductRow({
    required this.tile,
    required this.showCategory,
    required this.onTap,
    super.key,
  });

  final ProductTileData tile;
  final bool showCategory;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);
    final int inCart = tile.inCartUnits.ceil();

    return Semantics(
      button: onTap != null,
      label: tile.semanticLabel,
      hint: tile.canAdd ? null : AppLocalizations.of(context).sellOutOfStock,
      // One announcement per product. The chips below say the same words
      // visually, so excluding them here loses nothing and saves the listener
      // walking into four separate nodes for one product.
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.outline)),
        ),
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: spacing.minTapTarget),
            child: Padding(
              padding: EdgeInsetsDirectional.only(
                start: spacing.md,
                end: spacing.md,
                top: spacing.md,
                bottom: spacing.md,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        // No maxLines, no ellipsis: a product name the owner set
                        // is the thing a cashier is reading to the customer.
                        // Two lines here are cheaper than a truncated one.
                        Text(
                          tile.name,
                          style: type.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: tile.canAdd
                                ? colors.onSurface
                                : colors.onSurfaceVariant,
                          ),
                        ),
                        if (showCategory && tile.category.isNotEmpty)
                          Padding(
                            padding: EdgeInsets.only(top: spacing.xs),
                            child: Text(
                              tile.category,
                              style: type.labelSmall?.copyWith(
                                color: colors.onSurfaceMuted,
                              ),
                            ),
                          ),
                        Padding(
                          padding: EdgeInsets.only(top: spacing.sm),
                          child: Wrap(
                            spacing: spacing.xs,
                            runSpacing: spacing.xs,
                            children: <Widget>[
                              StatusChip(
                                tone: tile.stockTone,
                                text: tile.stockLabel,
                                dense: true,
                              ),
                              if (inCart > 0)
                                CountBadge(count: inCart, noun: 'in cart'),
                              if (tile.variantCount > 0)
                                StatusChip(
                                  tone: StatusTone.neutral,
                                  text: tile.variantCount == 1
                                      ? '1 variant'
                                      : '${tile.variantCount} variants',
                                  dense: true,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: spacing.md),
                  MoneyText(
                    amount: tile.price,
                    size: type.titleMedium!.fontSize!,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The master column: every category, with its product count.
class SellCategoryMaster extends StatelessWidget {
  const SellCategoryMaster({
    required this.categories,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final List<CategoryTileData> categories;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);

    return ListView.builder(
      padding: EdgeInsetsDirectional.only(
        start: spacing.xs,
        end: spacing.xs,
        bottom: spacing.md,
      ),
      itemCount: categories.length,
      itemBuilder: (BuildContext context, int index) {
        final CategoryTileData category = categories[index];
        return CategoryRow(
          tile: category,
          isSelected:
              category.isAll ? selected == null : selected == category.label,
          onTap: () => onSelected(category.isAll ? null : category.label),
        );
      },
    );
  }
}

/// One category row.
///
/// Selection rides on three channels so it survives greyscale: the accent
/// container, a check glyph in the leading slot, and a heavier word. `selected`
/// is exposed as a value as well, because "which category am I in" is the one
/// question a screen-reader user cannot answer from a colour.
class CategoryRow extends StatelessWidget {
  const CategoryRow({
    required this.tile,
    required this.isSelected,
    required this.onTap,
    super.key,
  });

  final CategoryTileData tile;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);
    final int count = tile.count;

    return Semantics(
      button: true,
      selected: isSelected,
      label: AppLocalizations.of(context).sellCategorySpoken(tile.label, count),
      excludeSemantics: true,
      child: Material(
        color: isSelected ? colors.accentContainer : Colors.transparent,
        borderRadius: AppShapes.of(context).controlRadius,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppShapes.of(context).controlRadius,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: spacing.minTapTarget),
            child: Padding(
              padding: EdgeInsetsDirectional.only(
                start: spacing.sm,
                end: spacing.sm,
                top: spacing.sm,
                bottom: spacing.sm,
              ),
              child: Row(
                children: <Widget>[
                  SizedBox.square(
                    dimension: spacing.xl,
                    child: isSelected
                        // Decorative: the word is bold and the row announces
                        // itself as selected.
                        ? ExcludeSemantics(
                            child: Icon(
                              Icons.check,
                              size: spacing.xl,
                              color: colors.onAccentContainer,
                            ),
                          )
                        : null,
                  ),
                  Expanded(
                    child: Text(
                      tile.label,
                      style: type.labelLarge?.copyWith(
                        color: isSelected
                            ? colors.onAccentContainer
                            : colors.onSurface,
                        fontWeight:
                            isSelected ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '$count',
                    style: AppTypography.money(
                      context,
                      size: type.labelMedium!.fontSize!,
                      weight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    ).copyWith(
                      color: isSelected
                          ? colors.onAccentContainer
                          : colors.onSurfaceMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The search field, with a way back out of a filter.
///
/// Not the shared `SearchField`: that one has no suffix, and the clear action is
/// not a nicety at a till. It is the shortest way out of a mistyped search, and
/// the alternative is backspacing thirteen characters with one thumb while a
/// customer waits. The 44px floor and the label-not-placeholder rule are the
/// same as the shared field's.
class SellSearchField extends StatelessWidget {
  const SellSearchField({
    required this.controller,
    required this.query,
    required this.onChanged,
    required this.onClear,
    super.key,
  });

  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: spacing.minTapTarget),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          labelText: AppLocalizations.of(context).sellSearchProducts,
          hintText: AppLocalizations.of(context).sellSearchNameOrCategory,
          prefixIcon: const Icon(Icons.search),
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: spacing.md),
          suffixIcon: query.isEmpty
              ? null
              : IconButton(
                  tooltip: AppLocalizations.of(context).sellClearSearchTooltip,
                  onPressed: onClear,
                  icon: const ExcludeSemantics(child: Icon(Icons.clear)),
                ),
        ),
      ),
    );
  }
}

/// Opens the camera.
///
/// One explicit tap. A till with a wedge scanner never needs it, and the button
/// says which camera it opens so nobody holds a handset over the counter
/// expecting it to work by itself.
class SellScanButton extends StatelessWidget {
  const SellScanButton({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const ExcludeSemantics(child: Icon(Icons.qr_code_scanner)),
        label: Text(AppLocalizations.of(context).sellScanBarcode),
      ),
    );
  }
}

/// A row-shaped placeholder, so nothing jumps when the catalogue lands.
class _CatalogueSkeletonRow extends StatelessWidget {
  const _CatalogueSkeletonRow({required this.showCategory});

  final bool showCategory;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);

    Widget bar(double widthFraction) => FractionallySizedBox(
          alignment: AlignmentDirectional.centerStart,
          widthFactor: widthFraction,
          child: Container(
            height: spacing.lg,
            decoration: BoxDecoration(
              color: colors.surfaceSunken,
              borderRadius: AppShapes.of(context).controlRadius,
            ),
          ),
        );

    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: spacing.md,
        end: spacing.md,
        top: spacing.md,
        bottom: spacing.md,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                bar(0.6),
                if (showCategory) ...<Widget>[
                  SizedBox(height: spacing.sm),
                  bar(0.3),
                ],
                SizedBox(height: spacing.sm),
                bar(0.35),
              ],
            ),
          ),
          SizedBox(width: spacing.md),
          bar(0.18),
        ],
      ),
    );
  }
}

/// The title for "your filter matched nothing", naming which filter it was.
/// Why nothing matched, in the user's terms.
///
/// Four cases rather than one generic sentence, because "no results" for a filter
/// is a different problem from "no results" for a category that has never been
/// stocked, and telling someone to shorten their search when the category is empty
/// sends them the wrong way.
String _noMatchTitle(
  AppLocalizations l10n,
  String query,
  String? category,
) {
  if (query.isNotEmpty && category != null) {
    return l10n.sellNoMatchInCategory(query, category);
  }
  if (category != null) return l10n.sellNothingInCategoryYet(category);
  if (query.isNotEmpty) return l10n.sellNoMatchQuery(query);
  return l10n.sellNoMatchFilter;
}
