import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Corner silhouettes and elevation, kept off the widgets.
///
/// A widget asks for `AppShapes.of(context).card` — a *silhouette* — instead of
/// composing `BorderRadius.circular(12)` from a number it invented. That is what
/// makes a radius change a one-file diff, and what stops the same control
/// picking up three different radii in three screens.
///
/// One radius system per app. Cards sit at 16: a card is a surface you point at
/// across a counter, and a soft silhouette reads as a panel rather than as a
/// row of data. Sheets sit one step rounder still, because a sheet is a layer
/// ABOVE the page and should not be confused with the cards on it.
@immutable
class AppShapes extends ThemeExtension<AppShapes> {
  const AppShapes({
    required this.xs,
    required this.sm,
    required this.md,
    required this.lg,
    required this.xl,
    required this.pill,
    required this.raisedShadow,
    required this.floatingShadow,
  });

  /// 4 — the inside of a chip, a small badge.
  final double xs;

  /// 8 — a table cell's well, a segmented-control segment.
  final double sm;

  /// 12 — a text field, a button.
  final double md;

  /// 16 — a card.
  final double lg;

  /// 24 — a sheet, a dialog. A layer above the page.
  final double xl;

  /// Fully rounded, for a chip or an avatar. The only value that is a shape
  /// category rather than a design decision.
  final double pill;

  /// Resting elevation: a card on the canvas. Low and ink-hued, so it reads as
  /// paper sitting on the page rather than as a grey smudge.
  final List<BoxShadow> raisedShadow;

  /// Transient elevation: a dialog, a menu, a snackbar. Twice the offset.
  final List<BoxShadow> floatingShadow;

  /// A page card.
  BorderRadius get cardRadius => BorderRadius.circular(lg);

  /// A button or a text field.
  BorderRadius get controlRadius => BorderRadius.circular(md);

  /// A sheet or a dialog — rounder than a card so it reads as a layer above it.
  BorderRadius get sheetRadius => BorderRadius.circular(xl);

  /// A chip or a badge.
  BorderRadius get chipRadius => BorderRadius.circular(pill);

  /// A thin placeholder bar: a skeleton's line, a progress track. `xs`, because
  /// a bar's radius is measured in hairline turns rather than in corners.
  BorderRadius get barRadius => BorderRadius.circular(xs);

  /// The card silhouette. Pass the ambient colours when the card needs an edge,
  /// which on a near-black canvas is the default: a shadow alone is too soft to
  /// separate one surface from another.
  RoundedRectangleBorder card(AppColors colors, {bool outlined = true}) =>
      RoundedRectangleBorder(
        borderRadius: cardRadius,
        side: outlined
            ? BorderSide(color: colors.outline, width: 1)
            : BorderSide.none,
      );

  /// A transient layer: a dialog, a menu, a sheet.
  RoundedRectangleBorder surface(AppColors colors) => RoundedRectangleBorder(
        borderRadius: sheetRadius,
        side: BorderSide(color: colors.outline, width: 1),
      );

  /// Reads the silhouettes for the ambient theme.
  ///
  /// The fallback here is the same value both `ThemeData`s carry, and
  /// `theme_token_test.dart` asserts that, so it is a constant rather than an
  /// unverified palette.
  static AppShapes of(BuildContext context) =>
      Theme.of(context).extension<AppShapes>() ?? _standardLight;

  static final AppShapes _standardLight =
      buildAppShapes(const AppColors.light());

  @override
  AppShapes copyWith({
    double? xs,
    double? sm,
    double? md,
    double? lg,
    double? xl,
    double? pill,
    List<BoxShadow>? raisedShadow,
    List<BoxShadow>? floatingShadow,
  }) {
    return AppShapes(
      xs: xs ?? this.xs,
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
      xl: xl ?? this.xl,
      pill: pill ?? this.pill,
      raisedShadow: raisedShadow ?? this.raisedShadow,
      floatingShadow: floatingShadow ?? this.floatingShadow,
    );
  }

  /// Snaps. A `ShapeBorder` is not meaningfully interpolable, and the honest
  /// options are a hard switch or nothing; this app bans theme animation, so
  /// the switch never runs.
  @override
  AppShapes lerp(ThemeExtension<AppShapes>? other, double t) =>
      t < 0.5 ? this : (other is AppShapes ? other : this);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppShapes &&
          other.xs == xs &&
          other.sm == sm &&
          other.md == md &&
          other.lg == lg &&
          other.xl == xl &&
          other.pill == pill &&
          other.raisedShadow == raisedShadow &&
          other.floatingShadow == floatingShadow;

  @override
  int get hashCode => Object.hash(
        xs,
        sm,
        md,
        lg,
        xl,
        pill,
        raisedShadow,
        floatingShadow,
      );
}

/// The single shape scale. Only the shadow colour follows the theme — a
/// silhouette is a structural constant and must not drift between brightnesses.
AppShapes buildAppShapes(AppColors colors) => AppShapes(
      xs: 4,
      sm: 8,
      md: 12,
      lg: 16,
      xl: 24,
      pill: 999,
      raisedShadow: <BoxShadow>[
        BoxShadow(
          color: colors.shadow,
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
      ],
      floatingShadow: <BoxShadow>[
        BoxShadow(
          color: colors.shadow,
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    );
