// The moment a sale is done.
//
// ## WHY A SCREEN AND NOT A SNACKBAR
//
// A sale is the one moment in a till's day that the cashier and the customer
// both care about. It is the moment the money changed hands, the moment the
// change has to be handed over, and the moment the receipt is either printed
// or not.
//
// A snackbar says "done" and disappears in four seconds. It cannot show the
// amount that changed hands, it cannot show the change to give, and it cannot
// be the thing the cashier reads while they are counting coins out of a
// drawer. And it overlays the till: the cashier is looking at the amount
// they owe, not at a card that appeared in the corner of it.
//
// So the sale ends on a SCREEN, with the amount, the change and the receipt
// state, and one button that starts the next sale.
//
// ## WHY IT IS NOT A ROUTE
//
// It is the end of a transaction, not a place. The cashier taps "Next sale"
// and is back on the till, with the cart empty, in one tap. A route would
// put a back button between the cashier and the next customer.
//
// ## WHY THE AMOUNT IS THE BIGGEST THING
//
// Because it is. The number the customer is owed is the answer to the
// question the whole screen exists for, and everything else on it is
// supporting detail.

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_shapes.dart';
import '../../theme/app_spacing.dart';
import '../../theme/typography.dart';

/// The confirmation that a sale is complete.
class SuccessView extends StatelessWidget {
  const SuccessView({
    required this.title,
    required this.message,
    this.amountLabel,
    this.detail,
    this.detailIcon = Icons.receipt_long_outlined,
    this.onNext,
    this.nextLabel,
    super.key,
  });

  /// What happened, in the app's own words: "Sale recorded".
  final String title;

  /// The supporting line: how it was paid, and what the change was.
  final String message;

  /// The amount, formatted. Null when there is no figure to show.
  final String? amountLabel;

  /// A second fact, beside its own marker: the receipt's state, a reference.
  final String? detail;

  final IconData detailIcon;

  /// The action that moves on. Null when there is nothing to do but look.
  final VoidCallback? onNext;

  final String? nextLabel;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final AppShapes shapes = AppShapes.of(context);
    final TextTheme type = AppTypography.of(context);

    return Semantics(
      container: true,
      child: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(spacing.xl),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: spacing.readableMaxWidth),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // The mark of a thing that worked: a tick in a success circle.
                //
                // A shape AND a colour, so it is still a tick in greyscale.
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: colors.successContainer,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.check_rounded,
                    size: 34,
                    color: colors.onSuccessContainer,
                  ),
                ),
                SizedBox(height: spacing.lg),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: type.headlineSmall,
                ),
                SizedBox(height: spacing.sm),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: type.bodyMedium?.copyWith(
                    color: colors.onSurfaceMuted,
                  ),
                ),
                if (amountLabel != null) ...<Widget>[
                  SizedBox(height: spacing.lg),
                  // THE AMOUNT. The biggest thing on the screen, because it is
                  // the answer to the question the screen exists for.
                  Text(
                    amountLabel!,
                    textAlign: TextAlign.center,
                    style: type.displaySmall?.copyWith(color: colors.onSurface),
                  ),
                ],
                if (detail != null) ...<Widget>[
                  SizedBox(height: spacing.lg),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: spacing.md,
                      vertical: spacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surfaceSunken,
                      borderRadius: shapes.controlRadius,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        ExcludeSemantics(
                          child: Icon(detailIcon,
                              size: 16, color: colors.onSurfaceMuted),
                        ),
                        SizedBox(width: spacing.sm),
                        Flexible(
                          child: Text(
                            detail!,
                            style: type.bodySmall?.copyWith(
                              color: colors.onSurfaceMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (onNext != null) ...<Widget>[
                  SizedBox(height: spacing.xl),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: onNext,
                      style: FilledButton.styleFrom(
                        minimumSize: Size(0, spacing.minTapTarget),
                        shape: RoundedRectangleBorder(
                          borderRadius: shapes.controlRadius,
                        ),
                      ),
                      child: Text(nextLabel ?? ''),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
