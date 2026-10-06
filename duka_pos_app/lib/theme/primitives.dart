import 'dart:ui' show Color;

/// Tier 1 of the token system: raw measured values.
///
/// This is the ONLY file in `lib/` permitted a colour literal. Every name here
/// is the value it holds, never a rank (`grey700`), an appearance
/// (`darkGrey`) or a brand role (`brandPrimary`) — those all die the moment a
/// second brightness or a hue shift arrives, and an appearance name inverts
/// catastrophically under one.
///
/// Neutrals are OKLCH lightness x100 at hue 25 (warm, chroma 1.8-3.4), which is
/// the measured hue of the brand's own greys. The accent ramp is OKLCH hue 8.1,
/// anchored so that `wine38` is byte-identical to the shipped brand primary
/// `#6E2638`.
///
/// Widgets never import this file. They read the semantic tier in
/// `app_colors.dart` through an asserting `AppColors.of(context)`.
///
/// Regenerating a ramp after a brand change: the recipe is
/// `oklch(L / 100, chroma, hue)` with the anchors pinned below verified against
/// the shipped artwork rather than derived, because four of these values are
/// contract — changing them changes the launcher icon, the Android
/// `colors.xml`, and `test/app_brand_test.dart` together.
abstract final class Primitives {
  const Primitives._();

  // ---------------------------------------------------------------- neutrals
  /// Near-black with a trace of warmth. Darks below this exist only so a
  /// hairline is drawable on [neutral06].
  static const neutral06 = Color(0xFF0D0B0B);

  /// Darkest surface in the dark theme.
  static const neutral10 = Color(0xFF131011);

  /// Dark-theme canvas — one step above [neutral06] so a raised card reads.
  static const neutral14 = Color(0xFF1D181A);

  /// Dark-theme raised surface (cards, sheets, menus).
  static const neutral20 = Color(0xFF262022);

  /// Dark-theme surface for a control sitting on a card.
  static const neutral25 = Color(0xFF302A2C);

  /// Dark-theme hairline. Decorative only: 1.41:1 on [neutral14], so it must
  /// never be the only boundary of a meaningful control. Use
  /// `AppColors.outlineStrong` for that.
  static const neutral32 = Color(0xFF3A3234);

  /// Dark-theme meaningful boundary: 3.08:1 on [neutral14], clearing WCAG
  /// 1.4.11 for a control edge.
  static const neutral45 = Color(0xFF6F6467);

  /// Dark-theme muted text: 6.08:1 on [neutral14].
  static const neutral63 = Color(0xFFA29597);

  /// Dark-theme secondary text: 9.61:1 on [neutral14].
  static const neutral79 = Color(0xFFC9BDBE);

  /// Dark-theme body text: 15.11:1 on [neutral14].
  static const neutral95 = Color(0xFFF5ECED);

  /// Body ink. PINNED — brand `#251A1D`, also the launcher icon's background
  /// and the Android `brand_ink` colour resource. 16.88:1 on paper.
  static const neutral23 = Color(0xFF251A1D);

  /// Tertiary body text. PINNED — brand `#66575B`. 6.82:1 on paper.
  static const neutral47 = Color(0xFF66575B);

  /// Secondary body text: 9.94:1 on paper.
  static const neutral34 = Color(0xFF4E3F42);

  /// Light-theme meaningful boundary: 5.06:1 on paper.
  static const neutral54 = Color(0xFF746D6C);

  /// Light-theme hairline. Decorative only: 1.61:1 on paper.
  static const neutral84 = Color(0xFFD6C9C4);

  /// Sunken wells, chips, table stripes. PINNED — brand `#F1EAE5`.
  static const neutral94 = Color(0xFFF1EAE5);

  /// App canvas behind cards. PINNED — brand `#F8F5F1`.
  static const neutral97 = Color(0xFFF8F5F1);

  /// Card and sheet surface. PINNED — brand `#FFFFFF`.
  static const neutral100 = Color(0xFFFFFFFF);

  // -------------------------------------------------------------------- wine
  /// Deepest accent. Dark-theme primary-container fill.
  static const wine26 = Color(0xFF440A1C);

  /// PINNED — brand `primaryDark` `#4B1725`, the shade the wine mark sits on in
  /// the launcher artwork.
  static const wine29 = Color(0xFF4B1725);

  /// PINNED — brand `primary` `#6E2638`. 10.51:1 on paper, 9.67:1 on canvas.
  static const wine38 = Color(0xFF6E2638);

  /// Mid accent for hover/pressed fills in light mode.
  static const wine44 = Color(0xFF8C2944);

  /// Dark-theme accent: 5.64:1 as text on [neutral14], and 5.43:1 against
  /// [neutral23] as a button fill carrying [neutral23] text.
  static const wine68 = Color(0xFFE86885);

  /// Dark-theme on-primary-container text: 9.91:1 on [wine26].
  static const wine90 = Color(0xFFFFB7D1);

  /// Light-theme primary-container fill.
  static const wine96 = Color(0xFFF6E7EA);

  // ------------------------------------------------------------------ status
  // Each status is three values, not one: a text tone that clears 4.5:1 on the
  // surface it is read from, a low-chroma container to sit on, and an on-
  // container tone for text inside that container. Colour is never the only
  // channel — see `StatusTone` in lib/ui/ for the glyph + word that ride along.

  /// Light-theme success text. PINNED — brand `#176B4D`. 6.47:1 on paper.
  static const green47Light = Color(0xFF176B4D);

  /// Light-theme success container.
  static const green95Light = Color(0xFFE7F2EC);

  /// Text on [green95Light]: 8.21:1.
  static const green35Light = Color(0xFF10503A);

  /// Dark-theme success text: 5.91:1 on [neutral14].
  static const green66 = Color(0xFF44A780);

  /// Dark-theme success container.
  static const green18Dark = Color(0xFF0E2A20);

  /// Text on [green18Dark]: 11.86:1.
  static const green90Dark = Color(0xFF8CF7C9);

  /// Light-theme warning text. PINNED — brand `#9A5B00`. 5.43:1 on paper.
  static const amber53Light = Color(0xFF9A5B00);

  /// Light-theme warning container.
  static const amber93Light = Color(0xFFF7EEDD);

  /// Text on [amber93Light]: 6.62:1.
  static const amber45Light = Color(0xFF7A4800);

  /// Dark-theme warning text: 6.85:1 on [neutral14].
  static const amber72 = Color(0xFFDF9044);

  /// Dark-theme warning container.
  static const amber22Dark = Color(0xFF33220D);

  /// Text on [amber22Dark]: 10.84:1.
  static const amber93Dark = Color(0xFFFFD386);

  /// Light-theme danger text. PINNED — brand `#B3261E`. 6.54:1 on paper.
  static const red50Light = Color(0xFFB3261E);

  /// Light-theme danger container.
  static const red95Light = Color(0xFFFBE9E7);

  /// Text on [red95Light]: 7.11:1.
  static const red42Light = Color(0xFF96201A);

  /// Dark-theme danger text: 5.65:1 on [neutral14].
  static const red68 = Color(0xFFEE685D);

  /// Dark-theme danger container.
  static const red22Dark = Color(0xFF331512);

  /// Text on [red22Dark]: 9.33:1.
  static const red92Dark = Color(0xFFFFAD9E);
}
