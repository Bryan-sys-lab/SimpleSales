import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_shapes.dart';
import '../../theme/app_spacing.dart';
import '../../theme/typography.dart';
import 'status.dart';

/// A money value, rendered as money.
///
/// Every price, total, balance and variance in the app goes through this rather
/// than a `Text` with a currency format. It exists for one reason: the tabular
/// figures. A column of totals that shifts horizontally as the digit count
/// changes is unreadable at a glance, and a total that jitters while it counts up
/// looks broken.
///
/// The amount is already formatted by the caller, which owns the locale and the
/// currency. This widget owns presentation only.
class MoneyText extends StatelessWidget {
  const MoneyText({
    required this.amount,
    this.size = 16,
    this.weight = FontWeight.w700,
    this.color,
    this.textAlign,
    this.semanticLabel,
    super.key,
  });

  /// Already localized and formatted, e.g. `KSh 4,320.00`.
  final String amount;

  final double size;
  final FontWeight weight;
  final Color? color;
  final TextAlign? textAlign;

  /// What a screen reader hears. Defaults to [amount], which is right for most
  /// cases; override when the visual form abbreviates (e.g. `KSh 43.2k` on a
  /// tile, which must still be announced in full).
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final TextStyle style = AppTypography.money(
      context,
      size: size,
      weight: weight,
    ).copyWith(color: color);

    final Widget text = Text(
      amount,
      textAlign: textAlign,
      style: style,
      // No maxLines and no ellipsis: a price that does not fit is a layout bug
      // to fix with a wider cell, not a number to truncate. Truncating a price
      // is the one place where "it will just get clipped" is never acceptable.
    );

    if (semanticLabel == null) return text;

    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: ExcludeSemantics(child: text),
    );
  }
}

/// The bar of actions pinned to the bottom of a screen.
///
/// The sell screen's "Charge KSh 4,320" lives here, and it is the one place in
/// the app where a control must be reachable by thumb while the other hand is on
/// a scanner. It is a real `bottomNavigationBar`, not a `Column` child, so it
/// does not shrink the scroll area when the keyboard opens.
class ActionBar extends StatelessWidget {
  const ActionBar({
    required this.primary,
    this.secondary,
    this.summary,
    super.key,
  });

  /// The committing action. Its label must name the verb and the object —
  /// "Charge KSh 4,320", never "OK".
  final Widget primary;

  /// The way out, or the lower-stakes action. Optional.
  final Widget? secondary;

  /// A line above the buttons: the total, the change due, the item count. The
  /// context a cashier needs before committing.
  final Widget? summary;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          top: BorderSide(color: colors.outline),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsetsDirectional.only(
            start: spacing.md,
            end: spacing.md,
            top: spacing.sm,
            bottom: spacing.sm,
          ),
          child: Row(
            children: <Widget>[
              if (secondary != null) ...<Widget>[
                secondary!,
                SizedBox(width: spacing.sm),
              ],
              // Expanded, not fixed: a long label wraps rather than overflowing,
              // and the button grows instead of the row clipping.
              Expanded(child: primary),
            ],
          ),
        ),
      ),
    );
  }
}

/// A search field.
///
/// `TextField` with a real label, never a placeholder-as-label: a placeholder
/// disappears the moment there is a value, so the user loses the only description
/// of what they are searching.
class SearchField extends StatelessWidget {
  const SearchField({
    required this.controller,
    required this.onChanged,
    this.hintText,
    this.autofocus = false,
    super.key,
  });

  final TextEditingController controller;

  /// Fires on every keystroke. Kept raw here rather than debounced inside the
  /// widget: a debounce is a ViewModel decision (how long, and what happens to
  /// results already on screen), not a rendering one.
  final ValueChanged<String> onChanged;

  final String? hintText;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);

    return ConstrainedBox(
      // A minimum, never a maximum: this must never be the thing that overflows.
      constraints: BoxConstraints(minHeight: spacing.minTapTarget),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        autofocus: autofocus,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: hintText,
          prefixIcon: const Icon(Icons.search, size: 20),
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: spacing.md),
        ),
      ),
    );
  }
}

/// A segmented control for a small, mutually exclusive set.
///
/// For 2-4 options on one axis. Beyond four, this is a menu — a segmented control
/// that wraps to two rows stops reading as one control.
class SegmentedChoice<T> extends StatelessWidget {
  const SegmentedChoice({
    required this.value,
    required this.options,
    required this.onChanged,
    this.semanticLabel,
    super.key,
  });

  final T value;
  final List<SegmentedOption<T>> options;
  final ValueChanged<T> onChanged;

  /// Names the whole group for a screen reader, which otherwise hears a row of
  /// unrelated buttons with no indication they are alternatives.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);

    return Semantics(
      container: true,
      label: semanticLabel,
      child: SingleChildScrollView(
        // Scrolls rather than squeezing: at 200% text scale four segments do not
        // fit a 360dp screen, and shrinking them to fit would defeat the user's
        // setting to buy a scroll.
        scrollDirection: Axis.horizontal,
        child: SegmentedButton<T>(
          segments: <ButtonSegment<T>>[
            for (final SegmentedOption<T> option in options)
              ButtonSegment<T>(
                value: option.value,
                label: Text(option.label),
                icon: option.icon == null ? null : Icon(option.icon, size: 18),
                tooltip: option.tooltip,
              ),
          ],
          selected: <T>{value},
          showSelectedIcon: false,
          onSelectionChanged: (Set<T> selection) => onChanged(selection.first),
          style: ButtonStyle(
            foregroundColor: WidgetStateProperty.resolveWith<Color?>(
              (Set<WidgetState> states) => states.contains(WidgetState.selected)
                  ? colors.onAccentContainer
                  : colors.onSurfaceVariant,
            ),
            backgroundColor: WidgetStateProperty.resolveWith<Color?>(
              (Set<WidgetState> states) => states.contains(WidgetState.selected)
                  ? colors.accentContainer
                  : Colors.transparent,
            ),
            side: WidgetStatePropertyAll<BorderSide>(
              BorderSide(color: colors.outline),
            ),
            padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(
              EdgeInsets.symmetric(horizontal: spacing.md),
            ),
          ),
        ),
      ),
    );
  }
}

class SegmentedOption<T> {
  const SegmentedOption({
    required this.value,
    required this.label,
    this.icon,
    this.tooltip,
  });

  final T value;
  final String label;
  final IconData? icon;
  final String? tooltip;
}

/// What the user decided about an irreversible action.
///
/// `showDialog` returns `Future<T?>`, and `null` means DISMISSED — tapping
/// outside the barrier, or pressing back. That is its own outcome, not a missing
/// value, and collapsing it with `?? ConfirmAccepted()` is how a tap in the wrong
/// place destroys a shift's takings.
sealed class ConfirmOutcome {
  const ConfirmOutcome();
}

final class ConfirmAccepted extends ConfirmOutcome {
  const ConfirmAccepted();
}

final class ConfirmDeclined extends ConfirmOutcome {
  const ConfirmDeclined();
}

final class ConfirmDismissed extends ConfirmOutcome {
  const ConfirmDismissed();
}

/// A confirmation for something that genuinely cannot be undone.
///
/// The rules, all of which exist because "Are you sure?" is useless:
///
/// * The **title names the consequence and the count** — "Delete 12 products
///   permanently".
/// * The **confirming button carries the verb** — "Delete permanently", never
///   "OK".
/// * `barrierDismissible: false`, because a decision that must resolve now
///   should not evaporate.
///
/// For anything reversible, use soft delete plus Undo instead. This dialog should
/// be rare.
class ConfirmDialog extends StatelessWidget {
  const ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.cancelLabel = 'Cancel',
    this.isDestructive = true,
    super.key,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;

  /// Paints the confirming button in the danger tone. Off for a non-destructive
  /// decision that still needs confirming.
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);

    return AlertDialog(
      title: Text(title),
      content: Text(message),
      actionsPadding:
          const EdgeInsetsDirectional.only(start: 8, end: 8, bottom: 8),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(const ConfirmDeclined()),
          child: Text(cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(const ConfirmAccepted()),
          style: isDestructive
              ? FilledButton.styleFrom(
                  backgroundColor: colors.danger,
                  foregroundColor: colors.onAccent,
                )
              : null,
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}

/// Asks [ConfirmDialog] and returns a sealed outcome.
///
/// The convenience wrapper that makes the dismissal case impossible to forget —
/// [showDialog]'s `null` is converted to [ConfirmDismissed] here, once, rather
/// than at each call site.
Future<ConfirmOutcome> confirmIrreversible(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  bool isDestructive = true,
}) async {
  final ConfirmOutcome? outcome = await showDialog<ConfirmOutcome>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) => ConfirmDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      isDestructive: isDestructive,
    ),
  );
  return outcome ?? const ConfirmDismissed();
}

/// A banner for a condition that persists until it is dealt with.
///
/// The surface ABOVE a snackbar in the ladder, and the right one for anything the
/// user must act on: offline, a licence about to expire, a degraded printer. A
/// snackbar auto-dismisses and may never be announced at all, which makes it the
/// wrong home for information that still matters in ten seconds.
class PersistentBanner extends StatelessWidget {
  const PersistentBanner({
    required this.message,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.tone = StatusTone.warning,
    super.key,
  });

  final String message;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppShapes shapes = AppShapes.of(context);
    final AppSpacing spacing = AppSpacing.of(context);

    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        padding: EdgeInsetsDirectional.only(
          start: spacing.md,
          end: spacing.md,
          top: spacing.sm,
          bottom: spacing.sm,
        ),
        decoration: BoxDecoration(
          color: tone.container(colors),
          borderRadius: shapes.controlRadius,
          border: Border.all(color: tone.color(colors)),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon ?? Icons.info_outline,
                size: 18, color: tone.onContainer(colors)),
            SizedBox(width: spacing.sm),
            Expanded(
              child: Text(
                message,
                style: AppTypography.of(context).bodyMedium?.copyWith(
                      color: tone.onContainer(colors),
                    ),
              ),
            ),
            if (onAction != null) ...<Widget>[
              SizedBox(width: spacing.sm),
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: tone.onContainer(colors),
                ),
                child: Text(actionLabel ?? 'Fix'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A snackbar with the screen-reader caveats already handled.
///
/// Two things it does that a bare `SnackBar` does not:
///
/// * **Clears the queue first.** Two snackbars arriving in quick succession
///   otherwise queue, and the user acts on the stale one.
/// * **Lengthens the timeout under `accessibleNavigation`.** Four seconds is
///   invisible to a screen-reader user mid-sentence; thirty is not a punishment,
///   it is the minimum for the announcement to land.
void showAppSnackBar(
  BuildContext context, {
  required String message,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final bool slow = MediaQuery.accessibleNavigationOf(context);
  final AppMotion motion = AppMotion.of(context);

  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: slow ? motion.feedbackExtended : motion.feedbackBrief,
      action: (actionLabel != null && onAction != null)
          ? SnackBarAction(label: actionLabel, onPressed: onAction)
          : null,
    ),
  );
}
