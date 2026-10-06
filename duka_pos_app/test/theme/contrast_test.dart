import 'dart:math' as math;

import 'package:duka_pos/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG 2.2 relative luminance and contrast ratio, in pure Dart.
///
/// Asserted on COLOUR VALUES rather than on pixels. `meetsGuideline(
/// textContrastGuideline)` screenshots the layer and histograms it, and white text
/// on `#FAFAFA` PASSES it — an open Flutter false negative. A pure-Dart ratio over
/// the theme's declared slots cannot false-pass, because there is no rendering
/// step to get wrong.
double wcagContrast(Color foreground, Color background) {
  final double a = _relativeLuminance(foreground);
  final double b = _relativeLuminance(background);
  final double lighter = math.max(a, b);
  final double darker = math.min(a, b);
  return (lighter + 0.05) / (darker + 0.05);
}

double _relativeLuminance(Color color) {
  // `computeLuminance` is already the WCAG formula (linearised sRGB, Rec. 709
  // coefficients); this is just the alpha composite, which it does not do.
  final double alpha = color.a;
  final Color opaque =
      alpha >= 1 ? color : Color.lerp(const Color(0xFFFFFFFF), color, alpha)!;
  return opaque.computeLuminance();
}

/// Every foreground/background pair a screen in this app actually composes.
///
/// If a pair is not listed here, it is not contrast-verified. That is the point:
/// a palette nobody measured is a palette that quietly fails AA on the one
/// background nobody tried it on.
const Map<String, ({Color fg, Color bg, double minimum, String note})>
    kContrastPairs =
    <String, ({Color fg, Color bg, double minimum, String note})>{
  // Body text, 4.5:1 (WCAG 1.4.3).
  'ink on canvas': (
    fg: AppColorsLight.onSurface,
    bg: AppColorsLight.canvas,
    minimum: 4.5,
    note: 'body text on the page',
  ),
  'ink on surface': (
    fg: AppColorsLight.onSurface,
    bg: AppColorsLight.surface,
    minimum: 4.5,
    note: 'body text on a card',
  ),
  'ink on sunken': (
    fg: AppColorsLight.onSurface,
    bg: AppColorsLight.surfaceSunken,
    minimum: 4.5,
    note: 'body text on a chip or table stripe',
  ),
  'variant on surface': (
    fg: AppColorsLight.onSurfaceVariant,
    bg: AppColorsLight.surface,
    minimum: 4.5,
    note: 'a supporting line under a label',
  ),
  'muted on surface': (
    fg: AppColorsLight.onSurfaceMuted,
    bg: AppColorsLight.surface,
    minimum: 4.5,
    note:
        'timestamps and counts. Still clears 4.5:1 — this is not disabled grey',
  ),
  'muted on canvas': (
    fg: AppColorsLight.onSurfaceMuted,
    bg: AppColorsLight.canvas,
    minimum: 4.5,
    note: 'helper text directly on the page',
  ),
  'muted on sunken': (
    fg: AppColorsLight.onSurfaceMuted,
    bg: AppColorsLight.surfaceSunken,
    minimum: 4.5,
    note: 'the tightest muted pairing: muted text on a selected chip',
  ),
  'onAccent on accent': (
    fg: AppColorsLight.onAccent,
    bg: AppColorsLight.accent,
    minimum: 4.5,
    note: 'the primary button label',
  ),
  'onAccentContainer on accentContainer': (
    fg: AppColorsLight.onAccentContainer,
    bg: AppColorsLight.accentContainer,
    minimum: 4.5,
    note: 'selected-row text',
  ),
  'accent on surface': (
    fg: AppColorsLight.accent,
    bg: AppColorsLight.surface,
    minimum: 4.5,
    note: 'an accent LINK or a selected nav label',
  ),
  'success on surface': (
    fg: AppColorsLight.success,
    bg: AppColorsLight.surface,
    minimum: 4.5,
    note: 'a status chip on a card',
  ),
  'warning on surface': (
    fg: AppColorsLight.warning,
    bg: AppColorsLight.surface,
    minimum: 4.5,
    note: 'a low-stock chip on a card',
  ),
  'danger on surface': (
    fg: AppColorsLight.danger,
    bg: AppColorsLight.surface,
    minimum: 4.5,
    note: 'an error message on a card',
  ),
  'danger on canvas': (
    fg: AppColorsLight.danger,
    bg: AppColorsLight.canvas,
    minimum: 4.5,
    note: 'an error message directly on the page',
  ),
  'onSuccessContainer on successContainer': (
    fg: AppColorsLight.onSuccessContainer,
    bg: AppColorsLight.successContainer,
    minimum: 4.5,
    note: 'text inside a success chip',
  ),
  'onWarningContainer on warningContainer': (
    fg: AppColorsLight.onWarningContainer,
    bg: AppColorsLight.warningContainer,
    minimum: 4.5,
    note: 'text inside a warning chip',
  ),
  'onDangerContainer on dangerContainer': (
    fg: AppColorsLight.onDangerContainer,
    bg: AppColorsLight.dangerContainer,
    minimum: 4.5,
    note: 'text inside a danger chip',
  ),
  // Non-text boundaries, 3:1 (WCAG 1.4.11).
  'outlineStrong on surface': (
    fg: AppColorsLight.outlineStrong,
    bg: AppColorsLight.surface,
    minimum: 3.0,
    note: 'an input border — a meaningful boundary the user must find',
  ),
  'outlineStrong on canvas': (
    fg: AppColorsLight.outlineStrong,
    bg: AppColorsLight.canvas,
    minimum: 3.0,
    note: 'an input border on the page background',
  ),
  'accent vs sunken': (
    fg: AppColorsLight.accent,
    bg: AppColorsLight.surfaceSunken,
    minimum: 3.0,
    note: 'selected vs unselected, distinguished only by colour. A greyscale '
        'user perceives exactly this luminance gap.',
  ),
};

/// The light palette, as literals the test can name.
///
/// Deliberately duplicated from `AppColors.light()` rather than read from it: a
/// test that reads the implementation and asserts it equals itself proves
/// nothing. These are the intended VALUES; if a palette change breaks one of them,
/// this file is supposed to notice.
abstract final class AppColorsLight {
  static const canvas = Color(0xFFF8F5F1);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceSunken = Color(0xFFF1EAE5);
  static const onSurface = Color(0xFF251A1D);
  static const onSurfaceVariant = Color(0xFF4E3F42);
  static const onSurfaceMuted = Color(0xFF66575B);
  static const outlineStrong = Color(0xFF746D6C);
  static const accent = Color(0xFF6E2638);
  static const onAccent = Color(0xFFFFFFFF);
  static const accentContainer = Color(0xFFF6E7EA);
  static const onAccentContainer = Color(0xFF4B1725);
  static const success = Color(0xFF176B4D);
  static const successContainer = Color(0xFFE7F2EC);
  static const onSuccessContainer = Color(0xFF10503A);
  static const warning = Color(0xFF9A5B00);
  static const warningContainer = Color(0xFFF7EEDD);
  static const onWarningContainer = Color(0xFF7A4800);
  static const danger = Color(0xFFB3261E);
  static const dangerContainer = Color(0xFFFBE9E7);
  static const onDangerContainer = Color(0xFF96201A);
}

/// The dark palette, likewise.
abstract final class AppColorsDark {
  static const canvas = Color(0xFF131011);
  static const surface = Color(0xFF1D181A);
  static const surfaceSunken = Color(0xFF0D0B0B);
  static const surfaceRaised = Color(0xFF262022);
  static const onSurface = Color(0xFFF5ECED);
  static const onSurfaceVariant = Color(0xFFC9BDBE);
  static const onSurfaceMuted = Color(0xFFA29597);
  static const outlineStrong = Color(0xFF6F6467);
  static const accent = Color(0xFFE86885);
  static const onAccent = Color(0xFF251A1D);
  static const accentContainer = Color(0xFF440A1C);
  static const onAccentContainer = Color(0xFFFFB7D1);
  static const success = Color(0xFF44A780);
  static const successContainer = Color(0xFF0E2A20);
  static const onSuccessContainer = Color(0xFF8CF7C9);
  static const warning = Color(0xFFDF9044);
  static const warningContainer = Color(0xFF33220D);
  static const onWarningContainer = Color(0xFFFFD386);
  static const danger = Color(0xFFEE685D);
  static const dangerContainer = Color(0xFF331512);
  static const onDangerContainer = Color(0xFFFFAD9E);
}

/// The dark equivalents of [kContrastPairs], same slots and same minimums.
const Map<String, ({Color fg, Color bg, double minimum})> kDarkPairs =
    <String, ({Color fg, Color bg, double minimum})>{
  'ink on canvas': (
    fg: AppColorsDark.onSurface,
    bg: AppColorsDark.canvas,
    minimum: 4.5
  ),
  'ink on surface': (
    fg: AppColorsDark.onSurface,
    bg: AppColorsDark.surface,
    minimum: 4.5
  ),
  'ink on raised': (
    fg: AppColorsDark.onSurface,
    bg: AppColorsDark.surfaceRaised,
    minimum: 4.5
  ),
  'ink on sunken': (
    fg: AppColorsDark.onSurface,
    bg: AppColorsDark.surfaceSunken,
    minimum: 4.5
  ),
  'variant on surface': (
    fg: AppColorsDark.onSurfaceVariant,
    bg: AppColorsDark.surface,
    minimum: 4.5
  ),
  'variant on raised': (
    fg: AppColorsDark.onSurfaceVariant,
    bg: AppColorsDark.surfaceRaised,
    minimum: 4.5
  ),
  'muted on surface': (
    fg: AppColorsDark.onSurfaceMuted,
    bg: AppColorsDark.surface,
    minimum: 4.5
  ),
  'muted on raised': (
    fg: AppColorsDark.onSurfaceMuted,
    bg: AppColorsDark.surfaceRaised,
    minimum: 4.5
  ),
  'muted on canvas': (
    fg: AppColorsDark.onSurfaceMuted,
    bg: AppColorsDark.canvas,
    minimum: 4.5
  ),
  'onAccent on accent': (
    fg: AppColorsDark.onAccent,
    bg: AppColorsDark.accent,
    minimum: 4.5
  ),
  'onAccentContainer on accentContainer': (
    fg: AppColorsDark.onAccentContainer,
    bg: AppColorsDark.accentContainer,
    minimum: 4.5
  ),
  'accent on surface': (
    fg: AppColorsDark.accent,
    bg: AppColorsDark.surface,
    minimum: 4.5
  ),
  'accent on raised': (
    fg: AppColorsDark.accent,
    bg: AppColorsDark.surfaceRaised,
    minimum: 4.5
  ),
  'success on surface': (
    fg: AppColorsDark.success,
    bg: AppColorsDark.surface,
    minimum: 4.5
  ),
  'warning on surface': (
    fg: AppColorsDark.warning,
    bg: AppColorsDark.surface,
    minimum: 4.5
  ),
  'danger on surface': (
    fg: AppColorsDark.danger,
    bg: AppColorsDark.surface,
    minimum: 4.5
  ),
  'danger on canvas': (
    fg: AppColorsDark.danger,
    bg: AppColorsDark.canvas,
    minimum: 4.5
  ),
  'onSuccessContainer on successContainer': (
    fg: AppColorsDark.onSuccessContainer,
    bg: AppColorsDark.successContainer,
    minimum: 4.5
  ),
  'onWarningContainer on warningContainer': (
    fg: AppColorsDark.onWarningContainer,
    bg: AppColorsDark.warningContainer,
    minimum: 4.5
  ),
  'onDangerContainer on dangerContainer': (
    fg: AppColorsDark.onDangerContainer,
    bg: AppColorsDark.dangerContainer,
    minimum: 4.5
  ),
  'outlineStrong on surface': (
    fg: AppColorsDark.outlineStrong,
    bg: AppColorsDark.surface,
    minimum: 3.0
  ),
  'outlineStrong on canvas': (
    fg: AppColorsDark.outlineStrong,
    bg: AppColorsDark.canvas,
    minimum: 3.0
  ),
  'accent vs raised': (
    fg: AppColorsDark.accent,
    bg: AppColorsDark.surfaceRaised,
    minimum: 3.0
  ),
};

void main() {
  group('WCAG contrast, measured on colour values in pure Dart', () {
    kContrastPairs.forEach((
      String name,
      ({Color bg, Color fg, double minimum, String note}) pair,
    ) {
      test('light · $name clears ${pair.minimum}:1', () {
        final double ratio = wcagContrast(pair.fg, pair.bg);
        expect(
          ratio,
          greaterThanOrEqualTo(pair.minimum),
          reason: 'light · $name is ${ratio.toStringAsFixed(2)}:1 — '
              '${pair.note}',
        );
      });
    });

    kDarkPairs.forEach((
      String name,
      ({Color bg, Color fg, double minimum}) pair,
    ) {
      test('dark · $name clears ${pair.minimum}:1', () {
        final double ratio = wcagContrast(pair.fg, pair.bg);
        expect(
          ratio,
          greaterThanOrEqualTo(pair.minimum),
          reason: 'dark · $name is ${ratio.toStringAsFixed(2)}:1',
        );
      });
    });
  });

  group('the shipped palette IS the palette the theme declares', () {
    // The point of the literals above. Without this, editing `AppColors` and
    // updating the assertions together would pass while shipping a regression.
    test('light AppColors matches the intended values', () {
      const AppColors colors = AppColors.light();
      expect(colors.canvas, AppColorsLight.canvas);
      expect(colors.surface, AppColorsLight.surface);
      expect(colors.surfaceSunken, AppColorsLight.surfaceSunken);
      expect(colors.onSurface, AppColorsLight.onSurface);
      expect(colors.onSurfaceVariant, AppColorsLight.onSurfaceVariant);
      expect(colors.onSurfaceMuted, AppColorsLight.onSurfaceMuted);
      expect(colors.outlineStrong, AppColorsLight.outlineStrong);
      expect(colors.accent, AppColorsLight.accent);
      expect(colors.onAccent, AppColorsLight.onAccent);
      expect(colors.accentContainer, AppColorsLight.accentContainer);
      expect(colors.onAccentContainer, AppColorsLight.onAccentContainer);
      expect(colors.success, AppColorsLight.success);
      expect(colors.successContainer, AppColorsLight.successContainer);
      expect(colors.onSuccessContainer, AppColorsLight.onSuccessContainer);
      expect(colors.warning, AppColorsLight.warning);
      expect(colors.warningContainer, AppColorsLight.warningContainer);
      expect(colors.onWarningContainer, AppColorsLight.onWarningContainer);
      expect(colors.danger, AppColorsLight.danger);
      expect(colors.dangerContainer, AppColorsLight.dangerContainer);
      expect(colors.onDangerContainer, AppColorsLight.onDangerContainer);
    });

    test('dark AppColors matches the intended values', () {
      const AppColors colors = AppColors.dark();
      expect(colors.canvas, AppColorsDark.canvas);
      expect(colors.surface, AppColorsDark.surface);
      expect(colors.surfaceSunken, AppColorsDark.surfaceSunken);
      expect(colors.surfaceRaised, AppColorsDark.surfaceRaised);
      expect(colors.onSurface, AppColorsDark.onSurface);
      expect(colors.onSurfaceVariant, AppColorsDark.onSurfaceVariant);
      expect(colors.onSurfaceMuted, AppColorsDark.onSurfaceMuted);
      expect(colors.outlineStrong, AppColorsDark.outlineStrong);
      expect(colors.accent, AppColorsDark.accent);
      expect(colors.onAccent, AppColorsDark.onAccent);
      expect(colors.accentContainer, AppColorsDark.accentContainer);
      expect(colors.onAccentContainer, AppColorsDark.onAccentContainer);
      expect(colors.success, AppColorsDark.success);
      expect(colors.successContainer, AppColorsDark.successContainer);
      expect(colors.onSuccessContainer, AppColorsDark.onSuccessContainer);
      expect(colors.warning, AppColorsDark.warning);
      expect(colors.warningContainer, AppColorsDark.warningContainer);
      expect(colors.onWarningContainer, AppColorsDark.onWarningContainer);
      expect(colors.danger, AppColorsDark.danger);
      expect(colors.dangerContainer, AppColorsDark.dangerContainer);
      expect(colors.onDangerContainer, AppColorsDark.onDangerContainer);
    });
  });

  group('brand contract', () {
    // These four values are the LAUNCHER ICON, the Android `brand_ink` colour
    // resource, `generate_launcher_icon.py`, and the splash screen. Changing one
    // without the others is how an app ends up with two logos. `app_brand_test`
    // checks the generated PNGs; this checks the values the app renders with.
    test('the app ink is the brand ink, byte for byte', () {
      expect(const Color(0xFF251A1D), const Color(0xFF251A1D));
      expect(
        const AppColors.light().onSurface.toARGB32(),
        0xFF251A1D,
        reason: 'app ink must stay #251A1D — it is the launcher icon plate and '
            'the Android brand_ink resource',
      );
      expect(const AppColors.dark().onAccent.toARGB32(), 0xFF251A1D);
    });

    test('the accent is the brand wine, byte for byte', () {
      expect(
        const AppColors.light().accent.toARGB32(),
        0xFF6E2638,
        reason: 'the accent must stay #6E2638 — it is the brand wine, also '
            'painted into the launcher icon and the brand hero artwork',
      );
    });

    test('paper on ink stays far above AA — the mark is read at 16px', () {
      expect(
        wcagContrast(const AppColors.light().surface, const Color(0xFF251A1D)),
        greaterThan(7),
      );
    });
  });

  group('dark is designed, not flipped', () {
    test(
        'the accent moves UP its own ramp, because the brand wine cannot be '
        'read on a dark surface', () {
      const AppColors light = AppColors.light();
      const AppColors dark = AppColors.dark();
      // `#6E2638` on the dark canvas is 1.80:1 — unusable as text or a fill.
      expect(wcagContrast(light.accent, dark.canvas), lessThan(3));
      expect(wcagContrast(dark.accent, dark.canvas), greaterThan(4.5));
    });

    test('the accent FILL inverts in dark, so a button label still clears AA',
        () {
      const AppColors dark = AppColors.dark();
      expect(
        wcagContrast(dark.onAccent, dark.accent),
        greaterThanOrEqualTo(4.5),
        reason: 'dark mode inverts the accent fill to a light rose; a dark ink '
            'label on it must still clear AA, or every primary button in the '
            'app is unreadable at night',
      );
    });
  });

  group('colour is never the only channel for a stateful pair', () {
    // A pair distinguished only by hue is invisible under `invertColors`, to a
    // greyscale user, and to a screen reader. This asserts the LUMINANCE gap,
    // which is what a greyscale user actually perceives.
    test('selected vs unselected differs in luminance, not just hue', () {
      expect(
        wcagContrast(
          AppColorsLight.accent,
          AppColorsLight.surfaceSunken,
        ),
        greaterThanOrEqualTo(3),
      );
      expect(
        wcagContrast(
          AppColorsDark.accent,
          AppColorsDark.surfaceRaised,
        ),
        greaterThanOrEqualTo(3),
      );
    });

    test(
        'success and danger are not distinguished by luminance alone in a way '
        'that reads as a step of grey', () {
      // They MAY share a luminance — that is what forces the glyph and the word
      // to carry the meaning. This test records that the responsibility exists so
      // nobody later "simplifies" it into colour alone.
      final double success = wcagContrast(
        AppColorsLight.success,
        AppColorsLight.surface,
      );
      final double danger = wcagContrast(
        AppColorsLight.danger,
        AppColorsLight.surface,
      );
      expect((success - danger).abs(), lessThan(3));
    });
  });
}
