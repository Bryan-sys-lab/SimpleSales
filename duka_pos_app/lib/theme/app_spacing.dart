import 'package:flutter/material.dart';

/// The spacing scale and the tap-target floor.
///
/// Deliberately tighter than a marketing layout: this is an Operate surface
/// (dials VARIANCE 3 / MOTION 3 / DENSITY 8), so the scale starts at 2 and
/// spends its steps on data rows rather than on breathing room. Every value is
/// a multiple of 2 from a 4px base, which is what lets a dense table and a
/// settings form share one rhythm.
@immutable
class AppSpacing extends ThemeExtension<AppSpacing> {
  const AppSpacing({
    required this.hairline,
    required this.xs,
    required this.sm,
    required this.md,
    required this.lg,
    required this.xl,
    required this.xxl,
    required this.section,
    required this.minTapTarget,
    required this.rowHeight,
    required this.controlHeight,
    required this.readableMaxWidth,
  });

  /// A 1px rule. Drawn with a `BoxBorder` or a `Divider`, never as a padded
  /// `Container`, so it stays hairline-thin at any text scale.
  final double hairline;

  /// Inside a chip, between an icon and its label.
  final double xs;

  /// Between tightly related elements (label to value in a table row).
  final double sm;

  /// The default gutter inside a card or a list row.
  final double md;

  /// Between blocks inside a screen.
  final double lg;

  /// Between major sections.
  final double xl;

  /// Above a screen's primary action.
  final double xxl;

  /// The block rhythm of a form or a settings group.
  final double section;

  /// The accessibility floor for any interactive target. WCAG 2.2 SC 2.5.8 and
  /// every platform's HIG agree on 44; a dense layout may make targets *wider*
  /// than tall, never shorter than this.
  final double minTapTarget;

  /// The resting height of a data row. A *minimum*, never a fixed height: a
  /// pinned `SizedBox(height: …)` is what clips a row at 200% text scale, so
  /// every row in this app is a `ConstrainedBox` with this as `minHeight`.
  final double rowHeight;

  /// The resting height of a button or a text field.
  final double controlHeight;

  /// The measure cap for prose. A settings paragraph at full width on a tablet
  /// is 140 characters per line and unreadable; this holds it near 70.
  final double readableMaxWidth;

  /// The one spacing scale. Both brightnesses share it — spacing is a
  /// structural constant, not a themed value, so it is attached to both
  /// `ThemeData`s identically.
  static const AppSpacing standard = AppSpacing(
    hairline: 1,
    xs: 2,
    sm: 4,
    md: 8,
    lg: 12,
    xl: 16,
    xxl: 24,
    section: 20,
    minTapTarget: 44,
    rowHeight: 44,
    controlHeight: 44,
    readableMaxWidth: 680,
  );

  /// Reads the scale for the ambient theme.
  ///
  /// [standard] is a genuine constant rather than an unverified fallback: it is
  /// the same value in both `ThemeData`s and is asserted in
  /// `theme_token_test.dart`.
  static AppSpacing of(BuildContext context) =>
      Theme.of(context).extension<AppSpacing>() ?? standard;

  @override
  AppSpacing copyWith({
    double? hairline,
    double? xs,
    double? sm,
    double? md,
    double? lg,
    double? xl,
    double? xxl,
    double? section,
    double? minTapTarget,
    double? rowHeight,
    double? controlHeight,
    double? readableMaxWidth,
  }) {
    return AppSpacing(
      hairline: hairline ?? this.hairline,
      xs: xs ?? this.xs,
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
      xl: xl ?? this.xl,
      xxl: xxl ?? this.xxl,
      section: section ?? this.section,
      minTapTarget: minTapTarget ?? this.minTapTarget,
      rowHeight: rowHeight ?? this.rowHeight,
      controlHeight: controlHeight ?? this.controlHeight,
      readableMaxWidth: readableMaxWidth ?? this.readableMaxWidth,
    );
  }

  /// Snaps rather than interpolates: a spacing scale is discrete, and
  /// interpolating it produces rows that are 11.3px tall on the way to a theme
  /// change, which is a value no screen was laid out for.
  @override
  AppSpacing lerp(ThemeExtension<AppSpacing>? other, double t) =>
      t < 0.5 ? this : (other is AppSpacing ? other : this);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSpacing &&
          other.hairline == hairline &&
          other.xs == xs &&
          other.sm == sm &&
          other.md == md &&
          other.lg == lg &&
          other.xl == xl &&
          other.xxl == xxl &&
          other.section == section &&
          other.minTapTarget == minTapTarget &&
          other.rowHeight == rowHeight &&
          other.controlHeight == controlHeight &&
          other.readableMaxWidth == readableMaxWidth;

  @override
  int get hashCode => Object.hash(
        hairline,
        xs,
        sm,
        md,
        lg,
        xl,
        xxl,
        section,
        minTapTarget,
        rowHeight,
        controlHeight,
        readableMaxWidth,
      );
}
