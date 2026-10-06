import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_shapes.dart';
import '../../theme/app_spacing.dart';
import '../../theme/typography.dart';

/// A stateful meaning, resolved once and rendered three ways.
///
/// This is the whole point of the enum existing: colour is DERIVED, from the
/// value, as the last step. A status that reads its colour from a literal is a
/// status whose colour drifts out of sync with its glyph the first time the
/// palette is retuned.
///
/// Every status carries at least three independent channels, so it survives
/// greyscale, `invertColors`, and every screen reader:
///
/// 1. **Glyph shape** — the icons below are distinct silhouettes, not one icon in
///    three colours.
/// 2. **The word** — routed through [StatusTone.label], never the colour alone.
/// 3. **Monotonic emphasis** — [StatusTone.emphasis] rises with severity, so the
///    urgent state is the bold one even with no colour at all.
///
/// Colour is decoration on top of those three.
enum StatusTone {
  /// Sold, paid, reconciled, in stock.
  success(Icons.check_circle_outline, 'Paid', 1),

  /// In progress, partially done, needs a second look.
  pending(Icons.schedule_outlined, 'Pending', 2),

  /// Needs attention but not broken: low stock, a variance under tolerance.
  warning(Icons.error_outline_outlined, 'Low', 3),

  /// Refused, failed, out of stock, a destructive state.
  danger(Icons.cancel_outlined, 'Blocked', 4),

  /// No state — a draft, a category label, an unremarkable row.
  neutral(Icons.remove_circle_outline, 'Draft', 0);

  const StatusTone(this.icon, this.label, this.emphasis);

  /// A shape that differs per status. See rule 1 above.
  final IconData icon;

  /// The word. See rule 2.
  final String label;

  /// 0-4, rising with severity. See rule 3.
  final int emphasis;

  /// DERIVED, and last. A function of the value, resolved through a semantic
  /// slot — never a literal, and never the source of the status itself.
  Color color(AppColors colors) => switch (this) {
        StatusTone.success => colors.success,
        StatusTone.pending => colors.warning,
        StatusTone.warning => colors.warning,
        StatusTone.danger => colors.danger,
        StatusTone.neutral => colors.onSurfaceMuted,
      };

  /// The container to sit on.
  Color container(AppColors colors) => switch (this) {
        StatusTone.success => colors.successContainer,
        StatusTone.pending || StatusTone.warning => colors.warningContainer,
        StatusTone.danger => colors.dangerContainer,
        StatusTone.neutral => colors.surfaceSunken,
      };

  /// Text and icon colour inside [container] — a different slot from [color]
  /// because the container is a different luminance.
  Color onContainer(AppColors colors) => switch (this) {
        StatusTone.success => colors.onSuccessContainer,
        StatusTone.pending || StatusTone.warning => colors.onWarningContainer,
        StatusTone.danger => colors.onDangerContainer,
        StatusTone.neutral => colors.onSurfaceVariant,
      };

  /// Whether the chip draws a border as well as a fill. A filled chip and an
  /// outlined chip are different SHAPES, which is a fourth channel for free.
  bool get isFilled => this != StatusTone.neutral;
}

/// A status, rendered with its glyph, its word, and its colour.
///
/// The screen-reader label is composed so the state is spoken as a state:
/// "Low stock" rather than "Low". A user who cannot see the amber chip still
/// hears that something needs attention.
class StatusChip extends StatelessWidget {
  const StatusChip({
    required this.tone,
    this.text,
    this.dense = false,
    super.key,
  });

  final StatusTone tone;

  /// Overrides the status's own word — "Low stock", "M-Pesa", "Over". The tone's
  /// label stays the fallback so a chip is never wordless.
  final String? text;

  /// Drops the horizontal padding for a table cell. Height still clears 24px,
  /// which is the smallest a touch-adjacent indicator may be; anything a user
  /// must TAP is a different component with the 44px floor.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final String label = text ?? tone.label;

    return Semantics(
      // Announced as one node: a screen reader should hear "Low stock", not
      // walk into the icon and the word separately.
      label: label,
      excludeSemantics: true,
      child: ExcludeSemantics(
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: dense ? spacing.xs : spacing.sm,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: tone.isFilled ? tone.container(colors) : Colors.transparent,
            borderRadius: AppShapes.of(context).chipRadius,
            border:
                tone.isFilled ? null : Border.all(color: colors.outlineStrong),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(tone.icon, size: 14, color: tone.onContainer(colors)),
              SizedBox(width: spacing.xs),
              // Weight rises with severity (channel 3), so the urgent chip is the
              // bold one in greyscale too.
              Text(
                label,
                style: AppTypography.of(context).labelSmall?.copyWith(
                      color: tone.onContainer(colors),
                      fontWeight: tone.emphasis >= 3
                          ? FontWeight.w700
                          : FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A count, with its noun.
///
/// Separate from [StatusChip] because a number and a state are different
/// information: "12" needs the word "low" next to it or it means nothing, and
/// "Low" needs the number or it cannot be acted on.
class CountBadge extends StatelessWidget {
  const CountBadge({
    required this.count,
    required this.noun,
    this.tone = StatusTone.neutral,
    super.key,
  });

  final int count;

  /// Already pluralised by the caller, which owns the locale's plural rules.
  final String noun;

  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);

    return Semantics(
      label: '$count $noun',
      excludeSemantics: true,
      child: ExcludeSemantics(
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: spacing.sm,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: tone.container(colors),
            borderRadius: AppShapes.of(context).chipRadius,
          ),
          child: Text(
            '$count $noun',
            style: type.labelSmall?.copyWith(
              color: tone.onContainer(colors),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
