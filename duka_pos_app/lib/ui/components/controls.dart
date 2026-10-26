import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_shapes.dart';
import '../../theme/app_spacing.dart';
import '../../theme/typography.dart';
import 'status.dart';
import 'surface.dart';

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
///
/// The field is a WELL, not a box drawn around a hole: the theme's input
/// decoration fills it with the sunken surface, so the field reads as pressed
/// INTO the page rather than as a heavy outline laid over it.
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
    final AppShapes shapes = AppShapes.of(context);

    return ConstrainedBox(
      // A minimum, never a maximum: this must never be the thing that overflows.
      constraints: BoxConstraints(minHeight: spacing.textFieldHeight),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        autofocus: autofocus,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: hintText,
          prefixIcon: const Icon(Icons.search, size: 20),
          isDense: true,
          constraints: BoxConstraints(minHeight: spacing.textFieldHeight),
          contentPadding: EdgeInsets.symmetric(vertical: spacing.md),
          // The theme's own border is a meaningful boundary (3:1); this keeps
          // that edge and only replaces the silhouette.
          border: OutlineInputBorder(
            borderRadius: shapes.controlRadius,
            borderSide: BorderSide(color: AppColors.of(context).outlineStrong),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: shapes.controlRadius,
            borderSide: BorderSide(color: AppColors.of(context).outlineStrong),
          ),
        ),
      ),
    );
  }
}

/// A filter pill: the shape a filter row is made of.
///
/// SELECTED is a solid accent fill with the accent's own ink on top. A tonal
/// wash of the same hue is what Material ships, and it reads as "slightly on"
/// rather than "this is the filter you have applied" — which on a till
/// filtering the day's takings is the difference between a filter and a
/// decoration.
///
/// Unselected is a sunken well with a hairline edge, so the row of pills reads
/// as a set of options rather than as one highlighted pill floating in space.
class SelectablePill extends StatelessWidget {
  const SelectablePill({
    required this.label,
    required this.selected,
    this.onTap,
    this.icon,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final AppShapes shapes = AppShapes.of(context);
    final TextTheme type = AppTypography.of(context);

    final Color fill = selected ? colors.accent : colors.surfaceSunken;
    final Color ink = selected ? colors.onAccent : colors.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: ExcludeSemantics(
        child: Material(
          color: fill,
          borderRadius: shapes.chipRadius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 32),
              padding: EdgeInsets.symmetric(
                horizontal: spacing.md,
                vertical: spacing.xs,
              ),
              decoration: BoxDecoration(
                borderRadius: shapes.chipRadius,
                border: Border.all(
                  color: selected ? colors.accent : colors.outline,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (icon != null) ...<Widget>[
                    Icon(icon, size: 14, color: ink),
                    SizedBox(width: spacing.xs),
                  ],
                  Text(
                    label,
                    style: type.labelMedium?.copyWith(
                      color: ink,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
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
                  ? colors.onAccent
                  : colors.onSurfaceVariant,
            ),
            backgroundColor: WidgetStateProperty.resolveWith<Color?>(
              (Set<WidgetState> states) => states.contains(WidgetState.selected)
                  ? colors.accent
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

enum AppNoticeTone { success, error, info, warning }

/// The app's single floating toast surface. It remains a SnackBar under the
/// hood so Flutter announces it correctly on every supported platform.
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
  AppNoticeTone tone = AppNoticeTone.info,
}) {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final bool slow = MediaQuery.accessibleNavigationOf(context);
  final AppMotion motion = AppMotion.of(context);
  final AppColors colors = AppColors.of(context);
  final Color toneColor = switch (tone) {
    AppNoticeTone.success => colors.accent,
    AppNoticeTone.error => colors.danger,
    AppNoticeTone.info => colors.onSurface,
    AppNoticeTone.warning => colors.warning,
  };
  final IconData toneIcon = switch (tone) {
    AppNoticeTone.success => Icons.check_circle_outline,
    AppNoticeTone.error => Icons.error_outline,
    AppNoticeTone.info => Icons.info_outline,
    AppNoticeTone.warning => Icons.warning_amber_outlined,
  };

  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
      backgroundColor: colors.surface,
      content: Row(
        children: <Widget>[
          Icon(toneIcon, color: toneColor),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
        ],
      ),
      duration: slow ? motion.feedbackExtended : motion.feedbackBrief,
      action: (actionLabel != null && onAction != null)
          ? SnackBarAction(label: actionLabel, onPressed: onAction)
          : null,
    ),
  );
}

// ---------------------------------------------------------------------------
// Settings rows
//
// The rows a settings screen is made of. Shared rather than private because
// Settings and Tax settings render the same three shapes, and a copy in each
// file is two copies to fix.
//
// All three take a `Material` ancestor as a given: they draw ink, and a
// card of rows has to supply it — see SurfaceCard.
// ---------------------------------------------------------------------------
/// A row that reads out a fact: an icon, a title, an optional subtitle, and an
/// optional trailing label. Nothing to do, so nothing to tap.
///
/// The rows of Settings and Tax settings are made of this, and it deliberately
/// carries no semantics of its own: an unlabelled `Icon` is invisible to a
/// screen reader, so the icon is excluded and the TEXT is what gets announced.
class SettingsInfoRow extends StatelessWidget {
  const SettingsInfoRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Padding(
      padding: EdgeInsetsDirectional.only(
        top: AppSpacing.of(context).sm,
        bottom: AppSpacing.of(context).sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          IconBadge(icon: icon),
          SizedBox(width: AppSpacing.of(context).md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: AppTypography.of(context).bodyLarge),
                if (subtitle != null) ...<Widget>[
                  SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: AppTypography.of(context)
                        .bodySmall
                        ?.copyWith(color: colors.onSurfaceMuted),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...<Widget>[
            SizedBox(width: AppSpacing.of(context).md),
            Text(
              trailing!,
              style: AppTypography.of(context)
                  .labelLarge
                  ?.copyWith(color: colors.onSurfaceMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// A row that navigates: one target, the display label as its semantic label.
///
/// The tap target is the whole row, never just the chevron, and the minimum
/// height is enforced HERE rather than left to each caller — the row that
/// forgets is invisible in review.
class SettingsNavRow extends StatelessWidget {
  const SettingsNavRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailing,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// Null while the action is unavailable — mid-save, or before the row has
  /// anything to act on. The row dims itself rather than losing its height, so
  /// the layout does not jump between idle and busy.
  final VoidCallback? onTap;

  /// Replaces the chevron with a label ("Change") where the destination acts on
  /// the row rather than opening a detail screen. The chevron says "there is
  /// more"; a verb says what tapping will do, and a shopkeeper setting a till
  /// code needs the verb.
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Semantics(
      button: true,
      label: title,
      child: Opacity(
        // Dimmed with the control: a row at full strength with no tap is a row
        // that reads as broken rather than busy.
        opacity: onTap == null ? 0.5 : 1,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsetsDirectional.only(
              top: AppSpacing.of(context).sm,
              bottom: AppSpacing.of(context).sm,
            ),
            child: ConstrainedBox(
              // The floor is on the row, not on the label: the tap target
              // stays legal when the subtitle wraps to three lines at 200%
              // text.
              constraints: const BoxConstraints(minHeight: 48),
              child: Row(
                children: <Widget>[
                  IconBadge(icon: icon),
                  SizedBox(width: AppSpacing.of(context).md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(title, style: AppTypography.of(context).bodyLarge),
                        if (subtitle != null) ...<Widget>[
                          SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: AppTypography.of(context)
                                .bodySmall
                                ?.copyWith(color: colors.onSurfaceMuted),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...<Widget>[
                    SizedBox(width: AppSpacing.of(context).sm),
                    Text(
                      trailing!,
                      style: AppTypography.of(context)
                          .labelLarge
                          ?.copyWith(color: colors.onSurfaceMuted),
                    ),
                  ] else ...<Widget>[
                    SizedBox(width: AppSpacing.of(context).sm),
                    ExcludeSemantics(
                      child: Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: colors.onSurfaceMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A row that toggles. The switch is the whole row's target, because a
/// switch-sized switch at the end of a full-width row is a target nobody hits
/// first try.
///
/// [enabled] false dims the icon and the title with the switch: a control at
/// full strength beside a switch that cannot move reads as one that can.
class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return InkWell(
      onTap: enabled ? () => onChanged(!value) : null,
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          top: AppSpacing.of(context).sm,
          bottom: AppSpacing.of(context).sm,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: <Widget>[
              Opacity(
                // Dimmed with the control: a badge at full strength beside a
                // switch that cannot move reads as a switch that can.
                opacity: enabled ? 1 : 0.5,
                child: IconBadge(icon: icon),
              ),
              SizedBox(width: AppSpacing.of(context).md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: AppTypography.of(context).bodyLarge?.copyWith(
                          color: enabled
                              ? colors.onSurface
                              : colors.onSurfaceMuted),
                    ),
                    if (subtitle != null) ...<Widget>[
                      SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: AppTypography.of(context)
                            .bodySmall
                            ?.copyWith(color: colors.onSurfaceMuted),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(width: AppSpacing.of(context).md),
              Switch(
                value: value,
                onChanged: enabled ? onChanged : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
