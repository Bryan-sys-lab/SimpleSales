import 'package:flutter/material.dart';

/// The spacing scale and the tap-target floor.
///
/// The shared 4/8-point rhythm for forms, transaction screens and settings.
/// The values are deliberately reusable defaults; text scaling and content
/// length may make a component grow beyond them.
@immutable
class AppSpacing extends ThemeExtension<AppSpacing> {
  const AppSpacing({
    required this.xxs,
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
    required this.spacious,
    required this.primaryButtonHeight,
    required this.textFieldHeight,
    required this.buttonHorizontalPadding,
    required this.formPrimaryActionGap,
    required this.mobilePageGutter,
    required this.largePageGutter,
  });

  /// Fine adjustments and icon-to-label gaps.
  final double xxs;

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

  /// The preferred Android touch target for interactive controls. The WCAG
  /// minimum is lower, but common POS actions use 48dp so they remain easy to
  /// operate quickly and with Switch Access.
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

  /// A large layout break, not ordinary form spacing.
  final double spacious;

  /// Shared interaction dimensions from the SimpleSales design standard.
  final double primaryButtonHeight;
  final double textFieldHeight;
  final double buttonHorizontalPadding;
  final double formPrimaryActionGap;
  final double mobilePageGutter;
  final double largePageGutter;

  /// The one spacing scale. Both brightnesses share it — spacing is a
  /// structural constant, not a themed value, so it is attached to both
  /// `ThemeData`s identically.
  static const AppSpacing standard = AppSpacing(
    xxs: 4,
    hairline: 1,
    xs: 8,
    sm: 12,
    md: 16,
    lg: 24,
    xl: 32,
    xxl: 40,
    section: 48,
    minTapTarget: 48,
    rowHeight: 48,
    controlHeight: 48,
    readableMaxWidth: 640,
    spacious: 64,
    primaryButtonHeight: 48,
    textFieldHeight: 56,
    buttonHorizontalPadding: 16,
    formPrimaryActionGap: 32,
    mobilePageGutter: 16,
    largePageGutter: 24,
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
    double? xxs,
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
    double? spacious,
    double? primaryButtonHeight,
    double? textFieldHeight,
    double? buttonHorizontalPadding,
    double? formPrimaryActionGap,
    double? mobilePageGutter,
    double? largePageGutter,
  }) {
    return AppSpacing(
      xxs: xxs ?? this.xxs,
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
      spacious: spacious ?? this.spacious,
      primaryButtonHeight: primaryButtonHeight ?? this.primaryButtonHeight,
      textFieldHeight: textFieldHeight ?? this.textFieldHeight,
      buttonHorizontalPadding:
          buttonHorizontalPadding ?? this.buttonHorizontalPadding,
      formPrimaryActionGap: formPrimaryActionGap ?? this.formPrimaryActionGap,
      mobilePageGutter: mobilePageGutter ?? this.mobilePageGutter,
      largePageGutter: largePageGutter ?? this.largePageGutter,
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
          other.xxs == xxs &&
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
          other.readableMaxWidth == readableMaxWidth &&
          other.spacious == spacious &&
          other.primaryButtonHeight == primaryButtonHeight &&
          other.textFieldHeight == textFieldHeight &&
          other.buttonHorizontalPadding == buttonHorizontalPadding &&
          other.formPrimaryActionGap == formPrimaryActionGap &&
          other.mobilePageGutter == mobilePageGutter &&
          other.largePageGutter == largePageGutter;

  @override
  int get hashCode => Object.hash(
        hairline,
        xxs,
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
        spacious,
        primaryButtonHeight,
        textFieldHeight,
        buttonHorizontalPadding,
        formPrimaryActionGap,
        mobilePageGutter,
        largePageGutter,
      );
}
