import 'package:flutter/material.dart';

import 'app_colors.dart';

/// The type scale, in Plus Jakarta Sans.
///
/// Plus Jakarta Sans is the face named in the brand artwork, bundled as a
/// variable font so one file carries the whole 200-800 axis and `FontWeight`
/// drives `wght` directly. There is no `FontVariation('wght', …)` anywhere: the
/// axis is reached through the property Flutter already maps, and the redundant
/// spelling silently no-ops.
///
/// Three decisions worth stating:
///
/// 1. **Every size here is a token.** `fontSize: 14` in a feature file is a
///    design decision made in the wrong place; the no-raw-values gate rejects
///    it.
/// 2. **Every number uses tabular figures.** A column of prices that shifts
///    horizontally as digits change is unreadable, and a total that jitters while
///    it counts up looks broken. `FontFeature.tabularFigures()` fixes the
///    advance width; that is the single highest-value thing this file does.
/// 3. **[boldTextFor] is applied at read time**, never baked into the scale. A
///    scale that hardcodes `w700` on body text throws the OS accessibility
///    setting away, and hardcoding is exactly what everyone does.
abstract final class AppTypography {
  const AppTypography._();

  /// The brand family. Bundled, never fetched: a runtime font download is a
  /// network dependency in the one code path that must never need one.
  static const String family = 'PlusJakartaSans';

  /// Per-script fallback ending in a known-good face. A future Arabic or
  /// Devanagari locale is a one-line change here plus a font file, not a
  /// tofu-fest across the app.
  static const List<String> fallback = <String>['Roboto', 'Noto Sans'];

  /// Figures that do not reflow. Use on every number a user compares vertically.
  static const List<FontFeature> tabular = <FontFeature>[
    FontFeature.tabularFigures(),
    FontFeature.slashedZero(),
  ];

  /// Builds the scale for one brightness.
  ///
  /// [colors] supplies every colour, so the same scale serves both themes and
  /// no style hardcodes one.
  static TextTheme scaleFor(AppColors colors) {
    final TextStyle body = TextStyle(
      fontFamily: family,
      fontFamilyFallback: fallback,
      color: colors.onSurface,
      decoration: TextDecoration.none,
      // Applied to EVERY role, not just the numeric ones. The cost when a role
      // holds no digits is zero — nobody sees the advance width of a letter — and
      // the benefit is that a number can appear anywhere, including in a button
      // label like "Charge KSh 4,320", without someone remembering to opt in.
      // Per-role opt-in is exactly how one role gets missed.
      fontFeatures: tabular,
    );
    final TextStyle muted = body.copyWith(color: colors.onSurfaceMuted);

    return TextTheme(
      // A POS has no hero image, so the display step is spent on the one number
      // a screen is about: today's take, a total, a variance.
      displaySmall: body.copyWith(
        fontSize: 28,
        height: 1.15,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
      ),
      headlineSmall: body.copyWith(
        fontSize: 22,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      headlineMedium: body.copyWith(
        fontSize: 26,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      titleLarge: body.copyWith(
        fontSize: 18,
        height: 1.25,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      titleMedium: body.copyWith(
        fontSize: 15,
        height: 1.3,
        fontWeight: FontWeight.w700,
      ),
      titleSmall: body.copyWith(
        fontSize: 13,
        height: 1.3,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: body.copyWith(
        fontSize: 15,
        height: 1.45,
        fontWeight: FontWeight.w400,
      ),
      bodyMedium: body.copyWith(
        fontSize: 14,
        height: 1.45,
        fontWeight: FontWeight.w400,
      ),
      bodySmall: muted.copyWith(
        fontSize: 12,
        height: 1.4,
        fontWeight: FontWeight.w400,
      ),
      labelLarge: body.copyWith(
        fontSize: 14,
        height: 1.2,
        fontWeight: FontWeight.w700,
      ),
      labelMedium: body.copyWith(
        fontSize: 13,
        height: 1.2,
        fontWeight: FontWeight.w600,
      ),
      labelSmall: muted.copyWith(
        fontSize: 11,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
    );
  }

  /// A price, a total, a count. Never `bodyMedium` with a bold flag — the
  /// tabular figures are the point.
  static TextStyle money(
    BuildContext context, {
    required double size,
    FontWeight weight = FontWeight.w700,
  }) {
    return TextStyle(
      fontFamily: family,
      fontFamilyFallback: fallback,
      fontSize: size,
      height: 1.2,
      fontWeight: weight,
      color: AppColors.of(context).onSurface,
      fontFeatures: tabular,
      decoration: TextDecoration.none,
    );
  }

  /// Applies the platform's bold-text setting to a designed scale.
  ///
  /// Read at build time from `MediaQuery`, never cached in app state: a scale
  /// pushed through a provider is one frame stale in the one place where being
  /// wrong is a user losing their setting.
  ///
  /// Weights are *raised*, never replaced: `w400 -> w600`, `w500 -> w700`, and
  /// anything already `w600` or heavier is left alone. Mapping 700 to 900 would
  /// request a weight the variable font tops out at, and Flutter silently
  /// renders it as 800 — so a "bolder" heading would come out identical.
  static TextTheme boldTextFor(TextTheme scale, bool boldText) {
    if (!boldText) return scale;

    TextStyle? raise(TextStyle? style) {
      if (style == null) return null;
      final FontWeight raised = switch (style.fontWeight) {
        null || FontWeight.w400 => FontWeight.w600,
        FontWeight.w500 => FontWeight.w700,
        _ => style.fontWeight!,
      };
      return style.fontWeight == raised
          ? style
          : style.copyWith(fontWeight: raised);
    }

    return scale.copyWith(
      displaySmall: raise(scale.displaySmall),
      headlineMedium: raise(scale.headlineMedium),
      headlineSmall: raise(scale.headlineSmall),
      titleLarge: raise(scale.titleLarge),
      titleMedium: raise(scale.titleMedium),
      titleSmall: raise(scale.titleSmall),
      bodyLarge: raise(scale.bodyLarge),
      bodyMedium: raise(scale.bodyMedium),
      bodySmall: raise(scale.bodySmall),
      labelLarge: raise(scale.labelLarge),
      labelMedium: raise(scale.labelMedium),
      labelSmall: raise(scale.labelSmall),
    );
  }

  /// The scale to render with, honouring the OS bold-text setting.
  static TextTheme of(BuildContext context) =>
      boldTextFor(Theme.of(context).textTheme, MediaQuery.boldTextOf(context));
}
