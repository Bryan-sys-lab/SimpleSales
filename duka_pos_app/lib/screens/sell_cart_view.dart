// What the customer is actually buying.
//
// The cart pane is the half of the till a cashier reads while talking to
// somebody, so it is packed rows rather than cards: forty lines of cards is a
// wall of borders with nothing to scan, and at 200% text scale the borders are
// all that survives.
//
// Every control here is single-tap and named for what it does to a specific
// line — "increase quantity of Kenyatta bread", never "plus" — because at
// 200% text scale and one-handed use, "plus" is a guess.

import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/controls.dart';
import '../ui/components/states.dart';
import '../ui/components/status.dart';

/// Below this width a cart line stacks its stepper under the name.
///
/// The line needs its name, a 116px stepper and a 44px remove button. Under
/// roughly 300px of total width that leaves the name about three characters per
/// line, so the stepper moves to its own row instead and the name keeps the full
/// width. A computed threshold from the pane's own constraints, not a device
/// check: a split-screen tablet and a landscape phone reach it differently.
const double kCartLineStacksBelow = 300;

/// One cart row, resolved before it reaches a widget.
///
/// Money and quantities arrive as strings because formatting belongs to the
/// state, not to a `build` method: every figure on this screen is money, and
/// every amount of money goes through `MoneyText` for its tabular figures.
@immutable
class CartLineData {
  const CartLineData({
    required this.lineId,
    required this.title,
    required this.sizeLabel,
    required this.lineTotal,
    required this.qtyLabel,
    required this.label,
  });

  /// The line's stable identity, resolved by the callback rather than by list
  /// position, so a removal can never shift a stepper onto its neighbour.
  final int lineId;

  /// "Kenyatta bread · Half", or "AAA Vodka · Shot".
  final String title;

  /// The serving size, empty for something with no size to state.
  final String sizeLabel;

  /// Already formatted.
  final String lineTotal;

  /// The quantity as the owner reads it: no trailing `.0`.
  final String qtyLabel;

  /// The product's own name, for naming the steppers.
  final String label;
}

/// The cart: what is in it, what it costs, and what the operator was last told.
class SellCartPane extends StatelessWidget {
  const SellCartPane({
    required this.lines,
    required this.statusMessage,
    required this.onIncrease,
    required this.onDecrease,
    required this.onRemove,
    required this.onBrowseCatalogue,
    required this.canBrowseCatalogue,
    super.key,
  });

  final List<CartLineData> lines;

  /// The last thing the till said, or null. A live region, because a sale
  /// finishing while the catalogue is on screen is an eye-only change.
  final String? statusMessage;

  final ValueChanged<int> onIncrease;
  final ValueChanged<int> onDecrease;
  final ValueChanged<int> onRemove;

  /// Back to the catalogue. Only offered where the catalogue is not already on
  /// screen beside this pane.
  final VoidCallback onBrowseCatalogue;

  final bool canBrowseCatalogue;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);
    final String? status = statusMessage;

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (status != null)
                Semantics(
                  liveRegion: true,
                  container: true,
                  label: status,
                  child: Padding(
                    padding: EdgeInsetsDirectional.only(bottom: spacing.sm),
                    child: Text(status, style: type.bodySmall),
                  ),
                ),
              Row(
                children: <Widget>[
                  Semantics(
                    header: true,
                    child: Text(
                      AppLocalizations.of(context).sellCartTitle,
                      style: type.titleLarge,
                    ),
                  ),
                  SizedBox(width: spacing.sm),
                  CountBadge(
                    count: lines.length,
                    noun: AppLocalizations.of(context)
                        .sellCartItemCount(lines.length),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: switch (lines.isEmpty) {
            true => EmptyStateView(
                kind: EmptyKind.collection,
                title: AppLocalizations.of(context).sellCartEmptyTitle,
                message: AppLocalizations.of(context).sellCartEmptyMessage,
                actionLabel: canBrowseCatalogue
                    ? AppLocalizations.of(context).sellBrowseProductsAction
                    : null,
                onAction: canBrowseCatalogue ? onBrowseCatalogue : null,
              ),
            false => ListView.builder(
                padding: EdgeInsetsDirectional.only(bottom: spacing.md),
                itemCount: lines.length,
                itemBuilder: (BuildContext context, int index) {
                  final CartLineData line = lines[index];
                  return CartLineRow(
                    line: line,
                    onIncrease: () => onIncrease(line.lineId),
                    onDecrease: () => onDecrease(line.lineId),
                    onRemove: () => onRemove(line.lineId),
                  );
                },
              ),
          },
        ),
      ],
    );
  }
}

/// One cart line: name, serving size, line amount, quantity and a way out.
///
/// The rule below is the pane's only separator, which is what makes forty lines
/// scannable where forty cards are not.
class CartLineRow extends StatelessWidget {
  const CartLineRow({
    required this.line,
    required this.onIncrease,
    required this.onDecrease,
    required this.onRemove,
    super.key,
  });

  final CartLineData line;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool stacked = constraints.maxWidth < kCartLineStacksBelow;

        final Widget heading = Text(line.title, style: type.bodyLarge);
        final Widget detail = _CartLineDetail(
          sizeLabel: line.sizeLabel,
          lineTotal: line.lineTotal,
        );
        final Widget stepper = QuantityStepper(
          qtyLabel: line.qtyLabel,
          label: line.label,
          onIncrease: onIncrease,
          onDecrease: onDecrease,
        );
        final Widget remove = _RemoveLineButton(
          label:
              AppLocalizations.of(context).sellRemoveLineFromCart(line.label),
          onPressed: onRemove,
        );

        return DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: colors.outline),
            ),
          ),
          child: Padding(
            padding: EdgeInsetsDirectional.only(
              start: spacing.md,
              end: spacing.sm,
              top: spacing.md,
              bottom: spacing.md,
            ),
            child: stacked
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      heading,
                      SizedBox(height: spacing.xs),
                      detail,
                      SizedBox(height: spacing.xs),
                      // Right-aligned so the quantity sits under the amount it
                      // changes, and on the thumb side of a one-handed grip.
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[stepper, remove],
                        ),
                      ),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            heading,
                            SizedBox(height: spacing.xs),
                            detail,
                          ],
                        ),
                      ),
                      SizedBox(width: spacing.sm),
                      stepper,
                      remove,
                    ],
                  ),
          ),
        );
      },
    );
  }
}

/// The line under the name: the serving size and what the line costs.
///
/// The amount is a `MoneyText` even though it shares a line with a size, because
/// the whole reason for that class is the tabular figures: a column of line
/// amounts that shifts sideways as the quantity changes is unreadable.
class _CartLineDetail extends StatelessWidget {
  const _CartLineDetail({required this.sizeLabel, required this.lineTotal});

  final String sizeLabel;
  final String lineTotal;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);
    final bool hasSize = sizeLabel.isNotEmpty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (hasSize) ...<Widget>[
          Flexible(
            child: Text(
              sizeLabel,
              style: type.bodySmall?.copyWith(color: colors.onSurfaceMuted),
            ),
          ),
          Text(' · ', style: type.bodySmall),
        ],
        MoneyText(amount: lineTotal, size: type.bodyMedium!.fontSize!),
      ],
    );
  }
}

/// `− 2 +` for one line.
///
/// 44px targets, and each one named for the line it changes. The tooltip IS the
/// accessibility label here: Flutter's `IconButton` exposes it as the button's
/// single semantics node, which a second `Semantics` wrapper would only nest a
/// duplicate inside.
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    required this.qtyLabel,
    required this.label,
    required this.onIncrease,
    required this.onDecrease,
    super.key,
  });

  final String qtyLabel;
  final String label;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconButton(
          // "Decrease quantity of Kenyatta bread", not "minus". At speed, on a
          // crowded screen, an unlabelled glyph is a guess.
          tooltip: AppLocalizations.of(context).sellDecreaseQuantityOf(label),
          onPressed: onDecrease,
          icon: const ExcludeSemantics(child: Icon(Icons.remove)),
        ),
        ConstrainedBox(
          constraints: BoxConstraints(minWidth: spacing.minTapTarget),
          child: Text(
            qtyLabel,
            textAlign: TextAlign.center,
            // Tabular figures: the number sits between two buttons and must not
            // move when it goes from 9 to 10.
            style:
                AppTypography.money(context, size: type.bodyLarge!.fontSize!),
          ),
        ),
        IconButton(
          tooltip: AppLocalizations.of(context).sellIncreaseQuantityOf(label),
          onPressed: onIncrease,
          icon: const ExcludeSemantics(child: Icon(Icons.add)),
        ),
      ],
    );
  }
}

/// Takes the whole line out of the cart.
class _RemoveLineButton extends StatelessWidget {
  const _RemoveLineButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: label,
      onPressed: onPressed,
      icon: const ExcludeSemantics(
        child: Icon(Icons.delete_outline_outlined),
      ),
    );
  }
}
