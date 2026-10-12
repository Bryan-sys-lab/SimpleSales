import 'package:flutter/material.dart';

import 'primitives.dart';

/// Tier 2 of the token system: semantic slots named by ROLE.
///
/// A widget reads these. A widget never imports `primitives.dart` — reaching a
/// primitive means a hardcoded theme, which is exactly the defect this split
/// exists to make greppable. Every slot below is declared for both brightnesses
/// and every foreground/background pair a screen actually composes is listed in
/// `test/theme/contrast_test.dart` as a pure-Dart WCAG check, because a palette
/// that nobody measured is a palette that quietly fails AA on the one
/// background nobody tried it on.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.canvas,
    required this.surface,
    required this.surfaceSunken,
    required this.surfaceRaised,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.onSurfaceMuted,
    required this.outline,
    required this.outlineStrong,
    required this.accent,
    required this.onAccent,
    required this.accentContainer,
    required this.onAccentContainer,
    required this.success,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.danger,
    required this.dangerContainer,
    required this.onDangerContainer,
    required this.info,
    required this.scrim,
    required this.shadow,
    required this.mediaScrim,
    required this.onMediaScrim,
    required this.mediaFrame,
    required this.mpesaGreen,
    required this.airtelRed,
    required this.equitelBlue,
    required this.cashNeutral,
  });

  /// The page behind cards. The largest area on screen, so it is the quietest.
  final Color canvas;

  /// A card, sheet, menu, or input resting on [canvas].
  final Color surface;

  /// A well the user types into or reads from: a table stripe, a chip, a
  /// segmented control's track. One step *away* from [surface], never a shadow.
  final Color surfaceSunken;

  /// A surface resting on another surface: a dialog, a dropdown, a snackbar.
  final Color surfaceRaised;

  /// Body text and meaningful icons.
  final Color onSurface;

  /// Secondary text: a supporting line under a label.
  final Color onSurfaceVariant;

  /// Tertiary text: timestamps, counts, helper captions. Still clears 4.5:1 —
  /// this is not "disabled grey".
  final Color onSurfaceMuted;

  /// A decorative separator. Deliberately below 3:1; never the only boundary of
  /// a control the user must find. See [outlineStrong].
  final Color outline;

  /// A meaningful boundary: an input border, a checkbox edge, a focus ring's
  /// resting state. Clears WCAG 1.4.11 (3:1) in both brightnesses.
  final Color outlineStrong;

  /// The single brand accent: deep botanical green.
  /// One per app, locked — not a seed: every role here is authored.
  final Color accent;

  /// Text and icons on an [accent] fill.
  final Color onAccent;

  /// A low-chroma accent fill for selection and emphasis.
  final Color accentContainer;

  /// Text and icons on [accentContainer].
  final Color onAccentContainer;

  /// Success semantic color.
  final Color success;
  final Color successContainer;
  final Color onSuccessContainer;

  /// Warning semantic color.
  final Color warning;
  final Color warningContainer;
  final Color onWarningContainer;

  /// Error semantic color.
  final Color danger;
  final Color dangerContainer;
  final Color onDangerContainer;

  /// Info semantic color.
  final Color info;

  /// Modal barrier. A scrim, not a colour with meaning.
  final Color scrim;

  /// The backdrop behind text laid over a live camera feed or an image.
  ///
  /// A NEW SLOT rather than a `Colors.black54` at the call site, for a real
  /// reason: text over a camera preview has no theme surface behind it, so it
  /// needs a tone chosen for contrast against whatever the lens happens to see.
  /// That tone is a design decision, which means it belongs here — and it has to
  /// be declared for both brightnesses and measured, because "looks fine over a
  /// dark shop" is not a contrast guarantee over a white shelf.
  final Color mediaScrim;

  /// Text on [mediaScrim]. Pure light in both themes: it sits over a camera feed,
  /// never over a paper card, so it follows the surface rather than the theme.
  final Color onMediaScrim;

  /// The scanning reticle drawn over the feed.
  final Color mediaFrame;

  /// The shadow colour for elevation. Deliberately the ink hue rather than pure
  /// black: a pure-black shadow on warm paper reads as a grey smudge.
  final Color shadow;

  /// M-PESA provider identity green. Not a semantic color.
  final Color mpesaGreen;

  /// Airtel Money provider identity red. Not a semantic color.
  final Color airtelRed;

  /// Equitel provider identity blue. Not a semantic color.
  final Color equitelBlue;

  /// Cash payment neutral.
  final Color cashNeutral;

  /// Reads the slots for the ambient brightness.
  ///
  /// Asserts rather than falling back. A `?? AppColors.fallback()` here would
  /// silently ship a palette no test ever verified; failing loudly in debug and
  /// landing on a blank surface in the field is the better trade.
  static AppColors of(BuildContext context) {
    final AppColors? extension = Theme.of(context).extension<AppColors>();
    assert(
      extension != null,
      'AppColors is missing from this ThemeData. Build both themes with '
      'buildDukaLightTheme() / buildDukaDarkTheme() and attach the '
      'extension to each — a theme built by hand renders unstyled.',
    );
    return extension!;
  }

  /// The light slots. Every pair below is measured in `contrast_test.dart`.
  const AppColors.light()
      : canvas = Primitives.neutral97,
        surface = Primitives.neutral100,
        surfaceSunken = Primitives.neutral94,
        surfaceRaised = Primitives.neutral100,
        onSurface = Primitives.neutral23,
        onSurfaceVariant = Primitives.neutral34,
        onSurfaceMuted = Primitives.neutral47,
        outline = Primitives.neutral84,
        outlineStrong = Primitives.neutral54,
        accent = Primitives.botanical38,
        onAccent = Primitives.neutral100,
        accentContainer = Primitives.botanical96,
        onAccentContainer = Primitives.botanical29,
        success = Primitives.green47Light,
        successContainer = Primitives.green95Light,
        onSuccessContainer = Primitives.green35Light,
        warning = Primitives.amber53Light,
        warningContainer = Primitives.amber93Light,
        onWarningContainer = Primitives.amber45Light,
        danger = Primitives.red50Light,
        dangerContainer = Primitives.red95Light,
        onDangerContainer = Primitives.red42Light,
        info = Primitives.blue47Light,
        scrim = const Color(0x991A1816),
        shadow = const Color(0x1A1A1816),
        mediaScrim = const Color(0xB3000000),
        onMediaScrim = Primitives.neutral100,
        mediaFrame = Primitives.botanical38,
        mpesaGreen = Primitives.mpesaGreen,
        airtelRed = Primitives.airtelRed,
        equitelBlue = Primitives.equitelBlue,
        cashNeutral = Primitives.cashNeutral;

  /// The dark slots, hand-authored rather than flipped.
  const AppColors.dark()
      : canvas = Primitives.neutral10,
        surface = Primitives.neutral14,
        surfaceSunken = Primitives.neutral06,
        surfaceRaised = Primitives.neutral20,
        onSurface = Primitives.neutral95,
        onSurfaceVariant = Primitives.neutral79,
        onSurfaceMuted = Primitives.neutral63,
        outline = Primitives.neutral32,
        outlineStrong = Primitives.neutral45,
        accent = Primitives.botanical58,
        // The brand ink, not the dark canvas: the accent fill inverts to a
        // bright green at night, and the ink that identifies the brand is the
        // value its label is painted in. Contrast on #4ADE7E is 10.9:1.
        onAccent = Primitives.neutral23,
        accentContainer = Primitives.botanical26,
        onAccentContainer = Primitives.botanical90,
        success = Primitives.green66,
        successContainer = Primitives.green18Dark,
        onSuccessContainer = Primitives.green90Dark,
        warning = Primitives.amber72,
        warningContainer = Primitives.amber22Dark,
        onWarningContainer = Primitives.amber93Dark,
        danger = Primitives.red68,
        dangerContainer = Primitives.red22Dark,
        onDangerContainer = Primitives.red92Dark,
        info = Primitives.blue66,
        scrim = const Color(0xB3000000),
        shadow = const Color(0x66000000),
        mediaScrim = const Color(0xB3000000),
        onMediaScrim = Primitives.neutral100,
        mediaFrame = Primitives.botanical58,
        mpesaGreen = Primitives.mpesaGreen,
        airtelRed = Primitives.airtelRed,
        equitelBlue = Primitives.equitelBlue,
        cashNeutral = Primitives.cashNeutral;

  @override
  AppColors copyWith({
    Color? canvas,
    Color? surface,
    Color? surfaceSunken,
    Color? surfaceRaised,
    Color? onSurface,
    Color? onSurfaceVariant,
    Color? onSurfaceMuted,
    Color? outline,
    Color? outlineStrong,
    Color? accent,
    Color? onAccent,
    Color? accentContainer,
    Color? onAccentContainer,
    Color? success,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? danger,
    Color? dangerContainer,
    Color? onDangerContainer,
    Color? info,
    Color? scrim,
    Color? shadow,
    Color? mediaScrim,
    Color? onMediaScrim,
    Color? mediaFrame,
    Color? mpesaGreen,
    Color? airtelRed,
    Color? equitelBlue,
    Color? cashNeutral,
  }) {
    return AppColors(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      onSurface: onSurface ?? this.onSurface,
      onSurfaceVariant: onSurfaceVariant ?? this.onSurfaceVariant,
      onSurfaceMuted: onSurfaceMuted ?? this.onSurfaceMuted,
      outline: outline ?? this.outline,
      outlineStrong: outlineStrong ?? this.outlineStrong,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      accentContainer: accentContainer ?? this.accentContainer,
      onAccentContainer: onAccentContainer ?? this.onAccentContainer,
      success: success ?? this.success,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warning: warning ?? this.warning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      danger: danger ?? this.danger,
      dangerContainer: dangerContainer ?? this.dangerContainer,
      onDangerContainer: onDangerContainer ?? this.onDangerContainer,
      info: info ?? this.info,
      scrim: scrim ?? this.scrim,
      shadow: shadow ?? this.shadow,
      mediaScrim: mediaScrim ?? this.mediaScrim,
      onMediaScrim: onMediaScrim ?? this.onMediaScrim,
      mediaFrame: mediaFrame ?? this.mediaFrame,
      mpesaGreen: mpesaGreen ?? this.mpesaGreen,
      airtelRed: airtelRed ?? this.airtelRed,
      equitelBlue: equitelBlue ?? this.equitelBlue,
      cashNeutral: cashNeutral ?? this.cashNeutral,
    );
  }

  /// Interpolates every colour.
  ///
  /// Theme changes are snapped to zero duration in this app
  /// (`themeAnimationStyle: AnimationStyle.noAnimation`), so `lerp` is here for
  /// correctness of the contract and for any future animated surface — it is not
  /// a step function pretending to be an interpolation.
  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      canvas: mix(canvas, other.canvas),
      surface: mix(surface, other.surface),
      surfaceSunken: mix(surfaceSunken, other.surfaceSunken),
      surfaceRaised: mix(surfaceRaised, other.surfaceRaised),
      onSurface: mix(onSurface, other.onSurface),
      onSurfaceVariant: mix(onSurfaceVariant, other.onSurfaceVariant),
      onSurfaceMuted: mix(onSurfaceMuted, other.onSurfaceMuted),
      outline: mix(outline, other.outline),
      outlineStrong: mix(outlineStrong, other.outlineStrong),
      accent: mix(accent, other.accent),
      onAccent: mix(onAccent, other.onAccent),
      accentContainer: mix(accentContainer, other.accentContainer),
      onAccentContainer: mix(onAccentContainer, other.onAccentContainer),
      success: mix(success, other.success),
      successContainer: mix(successContainer, other.successContainer),
      onSuccessContainer: mix(onSuccessContainer, other.onSuccessContainer),
      warning: mix(warning, other.warning),
      warningContainer: mix(warningContainer, other.warningContainer),
      onWarningContainer: mix(onWarningContainer, other.onWarningContainer),
      danger: mix(danger, other.danger),
      dangerContainer: mix(dangerContainer, other.dangerContainer),
      onDangerContainer: mix(onDangerContainer, other.onDangerContainer),
      info: mix(info, other.info),
      scrim: mix(scrim, other.scrim),
      shadow: mix(shadow, other.shadow),
      mediaScrim: mix(mediaScrim, other.mediaScrim),
      onMediaScrim: mix(onMediaScrim, other.onMediaScrim),
      mediaFrame: mix(mediaFrame, other.mediaFrame),
      mpesaGreen: mix(mpesaGreen, other.mpesaGreen),
      airtelRed: mix(airtelRed, other.airtelRed),
      equitelBlue: mix(equitelBlue, other.equitelBlue),
      cashNeutral: mix(cashNeutral, other.cashNeutral),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppColors &&
          other.canvas == canvas &&
          other.surface == surface &&
          other.surfaceSunken == surfaceSunken &&
          other.surfaceRaised == surfaceRaised &&
          other.onSurface == onSurface &&
          other.onSurfaceVariant == onSurfaceVariant &&
          other.onSurfaceMuted == onSurfaceMuted &&
          other.outline == outline &&
          other.outlineStrong == outlineStrong &&
          other.accent == accent &&
          other.onAccent == onAccent &&
          other.accentContainer == accentContainer &&
          other.onAccentContainer == onAccentContainer &&
          other.success == success &&
          other.successContainer == successContainer &&
          other.onSuccessContainer == onSuccessContainer &&
          other.warning == warning &&
          other.warningContainer == warningContainer &&
          other.onWarningContainer == onWarningContainer &&
          other.danger == danger &&
          other.dangerContainer == dangerContainer &&
          other.onDangerContainer == onDangerContainer &&
          other.info == info &&
          other.scrim == scrim &&
          other.shadow == shadow &&
          other.mediaScrim == mediaScrim &&
          other.onMediaScrim == onMediaScrim &&
          other.mediaFrame == mediaFrame &&
          other.mpesaGreen == mpesaGreen &&
          other.airtelRed == airtelRed &&
          other.equitelBlue == equitelBlue &&
          other.cashNeutral == cashNeutral;

  @override
  int get hashCode => Object.hashAll(<Object?>[
        canvas,
        surface,
        surfaceSunken,
        surfaceRaised,
        onSurface,
        onSurfaceVariant,
        onSurfaceMuted,
        outline,
        outlineStrong,
        accent,
        onAccent,
        accentContainer,
        onAccentContainer,
        success,
        successContainer,
        onSuccessContainer,
        warning,
        warningContainer,
        onWarningContainer,
        danger,
        dangerContainer,
        onDangerContainer,
        info,
        scrim,
        shadow,
        mediaScrim,
        onMediaScrim,
        mediaFrame,
        mpesaGreen,
        airtelRed,
        equitelBlue,
        cashNeutral,
      ]);
}
