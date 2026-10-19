import 'dart:ui' show Color;

/// Tier 1 of the token system: raw measured values.
///
/// This is the ONLY file in `lib/` permitted a colour literal. Every name here
/// is the value it holds, never a rank (`grey700`), an appearance
/// (`darkGrey`) or a brand role (`brandPrimary`) — those all die the moment a
/// second brightness or a hue shift arrives, and an appearance name inverts
/// catastrophically under one.
///
/// Widgets never import this file. They read the semantic tier in
/// `app_colors.dart` through an asserting `AppColors.of(context)`.
abstract final class Primitives {
  const Primitives._();

  // ---------------------------------------------------------------- neutrals
  /// Near-black with a trace of warmth. Dark theme deepest surface.
  static const neutral06 = Color(0xFF0F0E0D);

  /// Dark-theme canvas — warm charcoal base.
  static const neutral10 = Color(0xFF1A1816);

  /// Dark-theme surface one step above the canvas: the Material container
  /// ladder's middle rung.
  static const neutral12 = Color(0xFF1E1C1A);

  /// Dark-theme raised surface (cards, sheets, menus).
  static const neutral14 = Color(0xFF242220);

  /// Dark-theme elevated surface (dialogs, bottom sheets).
  static const neutral20 = Color(0xFF2E2B28);

  /// Dark-theme control surface (input fields, chips).
  static const neutral25 = Color(0xFF3A3633);

  /// Dark-theme hairline. Decorative only: below 3:1.
  static const neutral32 = Color(0xFF4A4541);

  /// Dark-theme meaningful boundary: clears 3:1 on neutral10.
  static const neutral45 = Color(0xFF7A736D);

  /// Dark-theme muted text: clears 4.5:1.
  static const neutral63 = Color(0xFFAA9F97);

  /// Dark-theme secondary text.
  static const neutral79 = Color(0xFFD4CAC0);

  /// Dark-theme body text: warm off-white.
  static const neutral95 = Color(0xFFF5F0EB);

  /// Light-theme body ink: warm charcoal (not pure black).
  static const neutral23 = Color(0xFF2D2A26);

  /// Light-theme tertiary body text.
  static const neutral47 = Color(0xFF6B635A);

  /// Light-theme secondary body text.
  static const neutral34 = Color(0xFF4A433C);

  /// Light-theme meaningful boundary: clears 3:1.
  static const neutral54 = Color(0xFF8A8075);

  /// Light-theme hairline. Decorative only.
  static const neutral84 = Color(0xFFE8E0D6);

  /// Sunken wells, chips, table stripes. Warm ivory.
  static const neutral94 = Color(0xFFF3EDE6);

  /// App canvas behind cards. Warm cream/ivory.
  static const neutral97 = Color(0xFFFAF6F0);

  /// Card and sheet surface. Soft white.
  static const neutral100 = Color(0xFFFFFFFF);

  // -------------------------------------------------------------------- veils and shadows
  //
  // Alphas over the page. Named for the value they hold — the ink and the
  // alpha — because a scrim has no role of its own: it is the shadow of the
  // sheet over the sheet below it.

  /// A 60% warm-ink veil: the light theme's scrim.
  static const scrimInk60 = Color(0x991A1816);

  /// A 10% warm-ink shadow: the light theme's shadow. Warm ink rather than
  /// pure black, because a black shadow on warm paper reads as a grey smudge.
  static const shadowInk10 = Color(0x1A1A1816);

  /// A 70% black veil: the dark theme's scrim, and the veil over a photograph.
  static const scrimNight70 = Color(0xB3000000);

  /// A 40% black shadow: the dark theme's shadow.
  static const shadowNight40 = Color(0x66000000);

  // -------------------------------------------------------------------- botanical green (primary brand)
  /// Dark-theme primary container fill.
  static const botanical26 = Color(0xFF244A30);

  /// Dark-theme accent green: clears 4.5:1 on neutral10.
  static const botanical58 = Color(0xFF4ADE7E);

  /// Dark-theme on-accent text.
  static const botanical90 = Color(0xFFA8F5C4);

  /// Light-theme brand green: deep botanical. Clears 4.5:1 on neutral97.
  static const botanical38 = Color(0xFF1B6B3A);

  /// Light-theme primary container fill.
  static const botanical96 = Color(0xFFE8F5EC);

  /// Light-theme on-primary-container text.
  static const botanical29 = Color(0xFF0D3D1E);

  // -------------------------------------------------------------------- status semantics
  // Each status is three values: text tone, container, on-container.
  // Colour is never the only channel — see StatusTone for glyph + word.

  /// Light-theme success text. Natural green.
  static const green47Light = Color(0xFF1A7A3A);

  /// Light-theme success container.
  static const green95Light = Color(0xFFE8F5EC);

  /// Text on green95Light.
  static const green35Light = Color(0xFF0D4D1E);

  /// Dark-theme success text.
  static const green66 = Color(0xFF5CE68A);

  /// Dark-theme success container.
  static const green18Dark = Color(0xFF0E2A16);

  /// Text on green18Dark.
  static const green90Dark = Color(0xFFA8F5C4);

  /// Light-theme warning text. Warm amber, darkened to clear 4.5:1 on paper —
  /// a lighter gold fails AA as text on a white card (3.25:1), so the text
  /// tone is this bronze-gold and the container below carries the bright tint.
  static const amber53Light = Color(0xFF8A6508);

  /// Light-theme warning container.
  static const amber93Light = Color(0xFFFFF3E0);

  /// Text on amber93Light.
  static const amber45Light = Color(0xFF7A5A00);

  /// Dark-theme warning text.
  static const amber72 = Color(0xFFFFB84D);

  /// Dark-theme warning container.
  static const amber22Dark = Color(0xFF3D2A0A);

  /// Text on amber22Dark.
  static const amber93Dark = Color(0xFFFFE0A0);

  /// Light-theme error text. Restrained red.
  static const red50Light = Color(0xFFC0392B);

  /// Light-theme error container.
  static const red95Light = Color(0xFFFDEDEA);

  /// Text on red95Light.
  static const red42Light = Color(0xFF8B2518);

  /// Dark-theme error text.
  static const red68 = Color(0xFFFF6B5B);

  /// Dark-theme error container.
  static const red22Dark = Color(0xFF3D1814);

  /// Text on red22Dark.
  static const red92Dark = Color(0xFFFFB3A8);

  /// Light-theme info text. Calm blue.
  static const blue47Light = Color(0xFF1A6BAA);

  /// Dark-theme info text.
  static const blue66 = Color(0xFF6AB0F5);

  // -------------------------------------------------------------------- external payment identities (NOT brand colors)
  //
  // These are the only colours in the app that are somebody else's brand, and
  // they are used to draw the payment-mix RING — a graphical object, which
  // WCAG holds to 3:1 against what is behind it, not the 4.5:1 of text.
  //
  // A provider's identity green is the colour on its logo, and it is not the
  // colour that survives a dark surface: #0066CC is 2.85:1 on the dark
  // surface, which is a ring slice nobody can see the edge of. So each
  // identity has a value per appearance, both holding the identity and both
  // clearing 3:1 on the canvas AND the surface they are drawn on.
  //
  // The legend underneath names every slice, so colour is never the only thing
  // identifying a tender — but "never the only channel" is not a licence to
  // draw a slice in a colour the eye cannot find.

  /// M-PESA / Safaricom green on the light canvas. Provider identity only.
  static const mpesaGreenLight = Color(0xFF009C4E);

  /// M-PESA / Safaricom green on the dark canvas. Provider identity only.
  static const mpesaGreenDark = Color(0xFF00A651);

  /// Airtel Money red. Provider identity only. One value: it clears 3:1 on
  /// both canvases already.
  static const airtelRed = Color(0xFFEC1C24);

  /// Equitel blue on the light canvas. Provider identity only.
  static const equitelBlueLight = Color(0xFF0066CC);

  /// Equitel blue on the dark canvas. Provider identity only.
  static const equitelBlueDark = Color(0xFF3E90E8);

  /// Cash neutral on the light canvas.
  static const cashNeutralLight = Color(0xFF6B635A);

  /// Cash neutral on the dark canvas. The light theme's meaningful boundary:
  /// it clears 3:1 on the dark surface, and a slice of cash that cannot be
  /// found is a slice of cash that cannot be read.
  static const cashNeutralDark = Color(0xFF8A8075);
}
