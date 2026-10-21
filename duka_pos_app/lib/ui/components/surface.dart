import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_shapes.dart';
import '../../theme/app_spacing.dart';
import '../../theme/typography.dart';
import 'status.dart';

/// A page card.
///
/// One component for every raised surface in the app, so "what does a panel look
/// like" is answered once. It is a hairline edge on [AppColors.surface], not a
/// shadow: on a near-black canvas a 1px edge draws the boundary, while a shadow
/// alone at this elevation reads as a grey smudge.
///
/// No `elevation` parameter. A card's job in this app is to group; where
/// something genuinely floats above the page it is a dialog or a sheet, and those
/// use [AppShapes.surface] instead. Offering an elevation knob here is how six
/// screens end up at six different elevations.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    required this.child,
    this.padding,
    this.onTap,
    this.semanticLabel,
    this.margin,
    this.color,
    this.clipContent = false,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;

  /// Makes the whole card one target. Resolved from a stable id at the call site,
  /// never from a captured value.
  final VoidCallback? onTap;

  /// What a screen reader announces. Leave null for a card whose contents already
  /// describe themselves — an empty label is worse than none, because it replaces
  /// real content with silence.
  final String? semanticLabel;

  final EdgeInsetsGeometry? margin;
  final Color? color;

  /// Clips the content to the card's radius. For a card whose child paints to its
  /// edge (a chart, a table) — never for one holding text, where clipping at
  /// large scales is how a label disappears.
  final bool clipContent;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppShapes shapes = AppShapes.of(context);
    final AppSpacing spacing = AppSpacing.of(context);

    final Widget body = Padding(
      padding: padding ?? EdgeInsets.all(spacing.lg),
      child: child,
    );

    if (onTap == null) {
      return Padding(
        padding: margin ?? EdgeInsets.zero,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color ?? colors.surface,
            borderRadius: shapes.cardRadius,
            border: Border.all(color: colors.outline),
          ),
          child: clipContent
              ? ClipRRect(borderRadius: shapes.cardRadius, child: body)
              : body,
        ),
      );
    }

    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: Semantics(
        button: true,
        label: semanticLabel,
        container: semanticLabel != null,
        child: Material(
          color: color ?? colors.surface,
          borderRadius: shapes.cardRadius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            // The whole card is the target, so a tap in a corner counts. Without
            // this the ink response covers only the child's bounds and a 12px
            // dead zone appears at every corner.
            //
            // The 44px floor is the COMPONENT's job, not the caller's. A card
            // holding one short line of text lays out at ~36px, and a screen that
            // forgets to pad it out ships a target below the accessibility floor
            // while looking perfectly fine in review.
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: spacing.minTapTarget,
              ),
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: shapes.cardRadius,
                  border: Border.all(color: colors.outline),
                ),
                child: body,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A titled block inside a screen.
///
/// The eyebrow is `labelSmall` in the muted tone with positive tracking — a
/// section marker, not a headline. It is a [Semantics] header so a screen-reader
/// user can jump between sections instead of reading a screen linearly.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.label,
    this.trailing,
    this.padding,
    super.key,
  });

  final String label;

  /// An action on the same line — "Export", "See all". Must be a real control,
  /// never a `TextButton` with no `onPressed`, which is how a screen ends up
  /// advertising a feature it does not have.
  final Widget? trailing;

  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);

    return Padding(
      padding: padding ??
          EdgeInsetsDirectional.only(
            start: spacing.xs,
            top: spacing.lg,
            end: spacing.xs,
            bottom: spacing.sm,
          ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                label.toUpperCase(),
                style: AppTypography.of(context).labelSmall?.copyWith(
                      color: colors.onSurfaceMuted,
                      letterSpacing: 0.6,
                    ),
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// The label/value row this app is mostly made of.
///
/// Named `KeyValueRow`, NOT `DataRow`: Material already exports a `DataRow` from
/// `data_table.dart`, and a same-named component in the design system collides
/// with the framework the moment a screen imports both. That ambiguity is a
/// compile error at best and a silently-wrong-widget at worst.
///
/// Dense by design: a 1px rule between rows rather than a card per row, because a
/// table of forty rows rendered as forty cards is a wall of borders with no
/// scannable alignment. Label muted on the start side, value on the end side,
/// both wrapping rather than truncating.
///
/// The value style is a parameter because a money column and a text column are
/// not the same thing — money needs tabular figures, and passing one through
/// [AppTypography.money] is how that stays true everywhere.
class KeyValueRow extends StatelessWidget {
  const KeyValueRow({
    required this.label,
    required this.value,
    this.valueStyle,
    this.labelStyle,
    this.leading,
    this.trailing,
    this.onTap,
    this.showDivider = true,
    this.dense = true,
    super.key,
  });

  final String label;
  final String value;
  final TextStyle? valueStyle;
  final TextStyle? labelStyle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// False for the last row in a group, or where a rule would double up with the
  /// section header's own spacing.
  final bool showDivider;

  /// Tighter vertical padding. Off for a row whose value wraps to two lines at
  /// large text scales and would otherwise collide with its neighbour's rule.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);

    final Widget content = Padding(
      padding: EdgeInsetsDirectional.only(
        start: spacing.md,
        end: spacing.md,
        top: dense ? spacing.sm : spacing.md,
        bottom: dense ? spacing.sm : spacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (leading != null) ...<Widget>[
            leading!,
            SizedBox(width: spacing.md),
          ],
          Expanded(
            flex: 4,
            child: Text(label, style: labelStyle ?? type.bodyMedium),
          ),
          SizedBox(width: spacing.md),
          Expanded(
            flex: 5,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: valueStyle ??
                  type.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          if (trailing != null) ...<Widget>[
            SizedBox(width: spacing.sm),
            trailing!,
          ],
        ],
      ),
    );

    final Widget ruled = showDivider
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              content,
              Divider(height: 1, color: colors.outline),
            ],
          )
        : content;

    if (onTap == null) return ruled;

    return Semantics(
      button: true,
      // The row's own words, read as one phrase. A screen-reader user stepping
      // through a table should hear "Kenyatta bread, 4, 320" — not the label,
      // then the value, as two stops.
      label: '$label, $value',
      child: InkWell(
        onTap: onTap,
        // A dense row is ~38px tall, which is below the 44px floor. The floor is
        // enforced HERE rather than left to each caller, because every caller
        // would have to remember and the row that forgot is invisible in review.
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: spacing.minTapTarget),
          child: ruled,
        ),
      ),
    );
  }
}

/// A single figure with its label.
///
/// The unit of a dashboard. Tabular figures, because a row of KPIs whose numbers
/// shift horizontally as they load is unreadable.
///
/// The three lines are LABEL / VALUE / DELTA: a muted label, a large figure,
/// and a small change with a direction. The delta is not decoration — it is the
/// third channel that makes a figure mean something ("KSh 12,480" alone is a
/// number; "KSh 12,480, up 18%" is a trend).
///
/// [emphasis] is a MONOTONIC channel independent of colour: the primary figure on
/// a screen is bigger. That is what keeps a KPI legible in greyscale, to a
/// screen-reader user, and under `invertColors`.
class StatTile extends StatelessWidget {
  const StatTile({
    required this.label,
    required this.value,
    this.caption,
    this.delta,
    this.emphasis = StatEmphasis.normal,
    this.onTap,
    super.key,
  });

  final String label;
  final String value;
  final String? caption;

  /// The change, with its direction. Null for a figure with nothing to compare
  /// it against.
  final StatDelta? delta;

  /// Monotonic weight in the visual hierarchy, never a colour-only distinction.
  final StatEmphasis emphasis;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);

    // The two value sizes are STEPS IN THE SCALE, not numbers invented here:
    // `titleLarge` for a figure in a row, `headlineMedium` for the one figure
    // the screen is about.
    final double valueSize = switch (emphasis) {
      StatEmphasis.normal => type.titleLarge?.fontSize ?? 18,
      StatEmphasis.strong => type.headlineMedium?.fontSize ?? 26,
    };

    return Semantics(
      button: onTap != null,
      label: '$label: $value${delta == null ? '' : ', ${delta!.spoken}'}',
      excludeSemantics: caption != null || delta != null,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: AppShapes.of(context).controlRadius,
// See the note in KeyValueRow: the floor belongs to the component.
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: spacing.minTapTarget),
            child: Padding(
              padding: EdgeInsets.all(spacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    label,
                    style: type.labelMedium?.copyWith(
                      color: colors.onSurfaceMuted,
                    ),
                  ),
                  SizedBox(height: spacing.xs),
                  // `maxLines` is NOT set and the tile is in a `Wrap`, not a
                  // `Row`: a value that wraps to two lines at 200% scale grows
                  // the tile rather than truncating the number a user must read.
                  Text(
                    value,
                    style: AppTypography.money(
                      context,
                      size: valueSize,
                      weight: emphasis == StatEmphasis.strong
                          ? FontWeight.w800
                          : FontWeight.w700,
                    ),
                  ),
                  if (delta != null) ...<Widget>[
                    SizedBox(height: spacing.xs),
                    _DeltaLine(delta: delta!),
                  ],
                  if (caption != null) ...<Widget>[
                    SizedBox(height: spacing.xs),
                    Text(caption!, style: type.bodySmall),
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

/// A change, and the direction it went.
///
/// The direction is a GLYPH, not just a colour: an arrow up is still an arrow
/// up with the colour removed, which is what keeps a rise from reading as a
/// fall to a greyscale user or under `invertColors`.
class StatDelta {
  const StatDelta({required this.text, required this.direction});

  /// The change, already formatted — "18%", "-3 orders".
  final String text;

  final DeltaDirection direction;

  /// What a screen reader hears. The direction is a word, because "up 18%" and
  /// "down 18%" are not the same sentence.
  String get spoken =>
      direction == DeltaDirection.up ? 'up $text' : 'down $text';
}

/// Which way a figure moved.
enum DeltaDirection { up, down }

class _DeltaLine extends StatelessWidget {
  const _DeltaLine({required this.delta});

  final StatDelta delta;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);

    // A rise is the success tone and a fall the danger tone, but the GLYPH is
    // what actually carries it.
    final bool up = delta.direction == DeltaDirection.up;
    final Color tone = up ? colors.success : colors.danger;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          up ? Icons.arrow_upward : Icons.arrow_downward,
          size: 14,
          color: tone,
        ),
        SizedBox(width: AppSpacing.of(context).xs),
        Text(
          delta.text,
          style: type.labelMedium?.copyWith(color: tone),
        ),
      ],
    );
  }
}

/// A round badge holding an icon.
///
/// The row pattern of this app: a coloured circle on the leading side, the
/// thing it belongs to next to it, and the value on the trailing side. The
/// badge is TONAL by default — a sunken well with a muted glyph — so the one
/// saturated colour in the app stays the one action. Pass a [StatusTone] to
/// let a row carry a state.
///
/// It is a circle and not a rounded square because a circle reads as a MARKER
/// and a rounded square reads as a FIELD: the eye goes to it, reads it as a
/// glyph, and moves on.
class IconBadge extends StatelessWidget {
  const IconBadge({
    required this.icon,
    this.tone = StatusTone.neutral,
    this.size = 36,
    this.semanticLabel,
    super.key,
  });

  final IconData icon;

  /// The state the badge carries. Neutral is a marker, not a status.
  final StatusTone tone;

  /// The circle's diameter.
  final double size;

  /// What a screen reader hears for the badge alone. Null excludes it — the
  /// row's own text then carries the meaning.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);

    final Widget badge = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tone.container(colors),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(
        icon,
        size: size * 0.5,
        color: tone.onContainer(colors),
      ),
    );

    if (semanticLabel == null) {
      return ExcludeSemantics(child: badge);
    }
    return Semantics(label: semanticLabel, child: badge);
  }
}

enum StatEmphasis { normal, strong }
