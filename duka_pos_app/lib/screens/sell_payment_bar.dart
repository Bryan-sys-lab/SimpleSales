// The bar a cashier's thumb lives on.
//
// Three things, in the order a sale actually happens: how they are paying, what
// it comes to, and the one button that commits. They live at the bottom of the
// screen because the hand holding the scanner is the other one.
//
// The whole bar is the screen's `Scaffold.bottomNavigationBar`, which is what
// keeps it out of the keyboard's way: a Scaffold slot is measured outside the
// body, so opening the search field's soft keyboard shrinks the catalogue and
// leaves the charge button exactly where the thumb already is.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/controls.dart';

/// The commit button's resting height.
///
/// 48, not the 44 the tap-target floor asks for. This is the app's most
/// important control, it is pressed in a queue of customers with one hand, and
/// it is the one target where an accidental miss costs a re-keyed basket.
const double kSellCommitButtonHeight = 48;

/// How the customer is paying.
///
/// Three choices, not two, because the offline paths are real paths. A shop with
/// no data cannot send an STK push, and it still has to take the customer's
/// money; collapsing "offline" into "cash" would hide the difference between a
/// recorded cash payment and a manual mobile-money entry the owner has to
/// reconcile later.
enum SellPaymentMethod {
  cash('Cash', 'in cash', Icons.payments_outlined),
  mpesa('M-Pesa', 'by M-Pesa', Icons.smartphone_outlined),
  offline('Offline', 'offline', Icons.receipt_long_outlined);

  const SellPaymentMethod(this.label, this.commitSuffix, this.icon);

  /// The segment's word. Also what a screen reader announces for it.
  final String label;

  /// How the commit button names the method, so its label stays verb + object:
  /// "Charge KSh 4,320 by M-Pesa" rather than a bare "Charge".
  final String commitSuffix;

  final IconData icon;
}

/// How they are paying, plus what it comes to.
///
/// The total is here rather than at the foot of the cart because this bar is the
/// only part of the screen the cashier is guaranteed to be looking at. It is
/// tabular so a changing total does not shift sideways under their finger.
class SellMethodBar extends StatelessWidget {
  const SellMethodBar({
    required this.method,
    required this.total,
    required this.enabled,
    required this.onMethodChanged,
    super.key,
  });

  final SellPaymentMethod method;

  /// Already formatted by the caller, which owns the currency.
  final String total;

  /// False while a payment is in flight: the method cannot change halfway
  /// through a charge.
  final bool enabled;

  final ValueChanged<SellPaymentMethod> onMethodChanged;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);

    return ColoredBox(
      color: colors.surface,
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          start: spacing.md,
          end: spacing.md,
          top: spacing.sm,
          bottom: spacing.xs,
        ),
        child: Row(
          children: <Widget>[
            // Flexible, not fixed: at 200% text scale the three segments are
            // wider than a phone and `SegmentedChoice` scrolls rather than
            // squeezing them.
            Flexible(
              child: IgnorePointer(
                ignoring: !enabled,
                child: Semantics(
                  // Ahead of everything else in the traversal order even though
                  // it is painted at the bottom: on a till this is the first
                  // thing a screen-reader user needs, and the layout order would
                  // make them walk the whole catalogue to reach it.
                  sortKey: const OrdinalSortKey(0),
                  child: SegmentedChoice<SellPaymentMethod>(
                    value: method,
                    semanticLabel:
                        AppLocalizations.of(context).sellPaymentMethodLabel,
                    options: <SegmentedOption<SellPaymentMethod>>[
                      for (final SellPaymentMethod option
                          in SellPaymentMethod.values)
                        SegmentedOption<SellPaymentMethod>(
                          value: option,
                          label: option.label,
                          icon: option.icon,
                          tooltip: AppLocalizations.of(context)
                              .sellPayByMethod(option.label),
                        ),
                    ],
                    onChanged: onMethodChanged,
                  ),
                ),
              ),
            ),
            SizedBox(width: spacing.md),
            MoneyText(
              amount: total,
              size: type.titleLarge!.fontSize!,
              weight: FontWeight.w800,
            ),
          ],
        ),
      ),
    );
  }
}

/// The commit action.
///
/// Verb + object, always: "Charge KSh 4,320 by M-Pesa", never "OK" and never a
/// bare noun. The empty-cart state says why it is disabled rather than showing
/// a total of zero, because "Charge KSh 0" reads as a bug to whoever is looking
/// at it mid-queue.
class SellChargeButton extends StatelessWidget {
  const SellChargeButton({
    required this.method,
    required this.total,
    required this.hasLines,
    required this.busy,
    required this.onPressed,
    super.key,
  });

  final SellPaymentMethod method;
  final String total;
  final bool hasLines;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final bool enabled = hasLines && !busy;

    return Semantics(
      sortKey: const OrdinalSortKey(1),
      child: FilledButton(
        onPressed: enabled ? onPressed : null,
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, kSellCommitButtonHeight),
          // The one place the app says "this commits": filled accent, full
          // width, and nothing competing with it on the bar.
          backgroundColor: colors.accent,
          foregroundColor: colors.onAccent,
          // `minimumSize` alone is not enough at 200% text scale, where the label
          // wraps to two lines; padding on the STYLE lets the button grow instead
          // of clipping the amount. `FilledButton` itself has no `padding`
          // parameter — that is a `ButtonStyle` field, and passing it to the
          // constructor is a compile error rather than a silent no-op.
          padding: EdgeInsets.symmetric(
            horizontal: spacing.lg,
            vertical: spacing.md,
          ),
        ),
        child: busy
            ? _ChargingLabel(total: total)
            : Text(
                hasLines
                    ? 'Charge $total ${method.commitSuffix}'
                    : 'Nothing to charge yet',
                textAlign: TextAlign.center,
              ),
      ),
    );
  }
}

/// The in-flight label.
///
/// A spinner is the acknowledgement, not the message: the words stay, because
/// the amount the customer is being charged is the one thing they must never
/// have to infer from a spinning circle.
class _ChargingLabel extends StatelessWidget {
  const _ChargingLabel({required this.total});

  final String total;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Decorative: "Charging" beside it already says what is happening.
        ExcludeSemantics(
          child: SizedBox.square(
            dimension: spacing.lg,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
        ),
        SizedBox(width: spacing.sm),
        Flexible(
          child: Text(
            AppLocalizations.of(context).sellChargingAmount(total),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
