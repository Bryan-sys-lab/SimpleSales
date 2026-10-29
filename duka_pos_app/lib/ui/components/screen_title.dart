// The large title a screen opens with.
//
// ## WHY A TITLE IS NOT AN APP BAR
//
// A coloured app bar across the top of every screen spends the app's only
// accent on chrome. Once the top of the screen is a saturated green band, the
// eye reads that band as "important" and stops looking for the thing the
// screen actually wants pressed — which is the whole job of a till.
//
// So the title sits DIRECTLY on the canvas: a large, left-aligned, semibold
// line with the supporting line under it and the screen's one action to the
// side. It is the same shape as an iOS large title, and for the same reason:
// a screen should name itself in the space it is actually using.
//
// ## WHY IT IS ITS OWN COMPONENT
//
// Eleven screens open with a title and a trailing action. Written eleven
// times, they are eleven chances to drift: a 22px title on one screen and a
// 26px title on the next, a subtitle in bodyMedium on one and bodySmall on
// another. One component makes the size, the weight, the gap and the colour a
// single decision.

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/typography.dart';

/// A screen's title block: an optional eyebrow, the title, an optional
/// supporting line, and an optional action on the trailing side.
///
/// The title is a [Semantics] header, so a screen-reader user can jump
/// between screens by heading rather than reading each one from the top.
class ScreenTitle extends StatelessWidget {
  const ScreenTitle({
    required this.title,
    this.subtitle,
    this.eyebrow,
    this.trailing,
    this.padding,
    super.key,
  });

  /// What this screen is. One line; it wraps rather than truncating.
  final String title;

  /// The line under the title: the shop, the date, the session.
  final String? subtitle;

  /// A small uppercase label ABOVE the title: a category, not a tagline.
  final String? eyebrow;

  /// The screen's one action, on the trailing side — a notification bell, a
  /// filter, a sign-out. At most one, so it reads as THE action.
  final Widget? trailing;

  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);

    final Widget text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (eyebrow != null) ...<Widget>[
          Text(
            eyebrow!.toUpperCase(),
            style: type.labelSmall?.copyWith(
              color: colors.onSurfaceMuted,
              letterSpacing: 0.6,
            ),
          ),
          SizedBox(height: spacing.xs),
        ],
        Semantics(
          header: true,
          child: Text(
            title,
            style: type.headlineMedium?.copyWith(color: colors.onSurface),
          ),
        ),
        if (subtitle != null) ...<Widget>[
          SizedBox(height: spacing.xs),
          Text(
            subtitle!,
            style: type.bodyMedium?.copyWith(color: colors.onSurfaceMuted),
          ),
        ],
      ],
    );

    return Padding(
      padding: padding ??
          EdgeInsetsDirectional.only(
            start: spacing.lg,
            top: spacing.sm,
            end: spacing.lg,
            bottom: spacing.md,
          ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(child: text),
          if (trailing != null) ...<Widget>[
            SizedBox(width: spacing.md),
            Flexible(
              fit: FlexFit.loose,
              child: trailing!,
            ),
          ],
        ],
      ),
    );
  }
}
