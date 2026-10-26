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
  //
  // A COOL ramp, on purpose. A warm sepia ramp is the single loudest way an app
  // stops reading as an instrument and starts reading as a scrapbook: warm
  // greys pull the eye toward the paper rather than toward the numbers, and they
  // make every saturated colour on screen look dirtier than it is. The night
  // ramp runs from a near-black with a blue cast up to a cool off-white, so
  // elevation is read as LUMINANCE — a surface gets LIGHTER as it comes
  // forward — rather than as a shadow smeared over a dark page.
  //
  // The numbers are lightness steps, not hues: 04 is the deepest value in the
  // app and 100 the lightest. Nothing in `lib/` outside this file names a
  // colour.

  /// The deepest value in the app: a sunken well below the canvas.
  static const neutral04 = Color(0xFF070A0E);

  /// The night canvas. Near-black with a blue cast.
  static const neutral08 = Color(0xFF0B0F14);

  /// One step above the canvas: the Material container ladder's low rung.
  static const neutral12 = Color(0xFF11161D);

  /// The night surface: a card, a tile, a panel resting on the canvas.
  static const neutral16 = Color(0xFF151A21);

  /// A surface resting on another surface: a dialog, a dropdown, a snackbar.
  static const neutral20 = Color(0xFF1C222B);

  /// A control surface: an input field, a chip, a track.
  static const neutral25 = Color(0xFF242C37);

  /// The hairline. Decorative only: below 3:1.
  static const neutral32 = Color(0xFF2E3742);

  /// A meaningful boundary: an input edge, a focus ring. Clears 3:1 on the
  /// night canvas and on the night surface.
  static const neutral45 = Color(0xFF606B7A);

  /// Muted text on a night surface: clears 4.5:1.
  static const neutral63 = Color(0xFF97A3B2);

  /// Secondary text on a night surface.
  static const neutral79 = Color(0xFFC4CDD8);

  /// Body text on a night surface. A cool off-white, never pure white — pure
  /// white on a near-black canvas blooms.
  static const neutral95 = Color(0xFFF2F5F8);

  /// Light-theme body ink: the brand ink, and not pure black.
  ///
  /// PINNED. This value is the launcher icon's plate, the Android `brand_ink`
  /// colour resource, the splash background and the mark's ink — see
  /// `assets/branding/generate_launcher_icon.py`. Changing it here without
  /// regenerating those artefacts is how an app ends up with two logos.
  static const neutral23 = Color(0xFF2D2A26);

  /// Light-theme tertiary body text.
  static const neutral47 = Color(0xFF5C6673);

  /// Light-theme secondary body text.
  static const neutral34 = Color(0xFF414954);

  /// Light-theme meaningful boundary: clears 3:1 on the canvas and on a card.
  static const neutral54 = Color(0xFF6B7480);

  /// Light-theme hairline. Decorative only.
  static const neutral84 = Color(0xFFDCE1E8);

  /// Sunken wells, chips, table stripes.
  static const neutral94 = Color(0xFFE8ECF1);

  /// The app canvas behind cards. A cool near-white, not cream: a tinted
  /// canvas carries a hue through every surface above it, and cream is the
  /// hue that makes a green accent look like moss.
  static const neutral97 = Color(0xFFF2F4F7);

  /// Card and sheet surface. White.
  static const neutral100 = Color(0xFFFFFFFF);

  // -------------------------------------------------------------------- veils and shadows
  //
  // Alphas over the page. Named for the value they hold — the ink and the
  // alpha — because a scrim has no role of its own: it is the shadow of the
  // sheet over the sheet below it.

  /// A 60% cool-ink veil: the light theme's scrim.
  static const scrimInk60 = Color(0x990A0E13);

  /// A 10% cool-ink shadow: the light theme's shadow. Ink rather than pure
  /// black, because a black shadow on a pale canvas reads as a grey smudge.
  static const shadowInk10 = Color(0x1A0A0E13);

  /// A 70% black veil: the dark theme's scrim, and the veil over a photograph.
  static const scrimNight70 = Color(0xB3000000);

  /// A 40% black shadow: the dark theme's shadow.
  static const shadowNight40 = Color(0x66000000);

  // -------------------------------------------------------------------- botanical green (primary brand)
  /// The night accent container: a deep emerald wash. Tonal, never solid —
  /// the SOLID emerald is [botanical58], and having both is what lets a
  /// selected row glow while a selected chip announces itself.
  static const botanical20 = Color(0xFF163A22);

  /// The night accent green: the emerald. Clears 4.5:1 on the night canvas.
  static const botanical58 = Color(0xFF4ADE7E);

  /// The night on-accent-container text.
  static const botanical90 = Color(0xFF9FF0C0);

  /// The light brand green: deep botanical. Clears 4.5:1 on the light canvas.
  ///
  /// PINNED. This value is painted into the launcher icon and the brand hero
  /// artwork — see `assets/branding/generate_launcher_icon.py`.
  static const botanical38 = Color(0xFF1B6B3A);

  /// The light accent container.
  static const botanical96 = Color(0xFFE4F3E9);

  /// The light on-accent-container text.
  static const botanical29 = Color(0xFF0D3D1E);

  // -------------------------------------------------------------------- status semantics
  // Each status is three values: text tone, container, on-container.
  // Colour is never the only channel — see StatusTone for glyph + word.

  /// Light-theme success text. Natural green.
  static const green47Light = Color(0xFF1A7A3A);

  /// Light-theme success container.
  static const green95Light = Color(0xFFE4F3E9);

  /// Text on green95Light.
  static const green35Light = Color(0xFF0D4D1E);

  /// The night success text.
  static const green66 = Color(0xFF5CE68A);

  /// The night success container: a deep green wash, not a near-black one.
  static const green18Dark = Color(0xFF123520);

  /// Text on green18Dark.
  static const green90Dark = Color(0xFF8DE8AE);

  /// Light-theme warning text. Warm amber, darkened to clear 4.5:1 on the
  /// light canvas — a lighter gold fails AA as text on a white card (3.25:1),
  /// so the text tone is this bronze-gold and the container below carries the
  /// bright tint.
  static const amber53Light = Color(0xFF8A6508);

  /// Light-theme warning container.
  static const amber93Light = Color(0xFFFFF3E0);

  /// Text on amber93Light.
  static const amber45Light = Color(0xFF7A5A00);

  /// The night warning text.
  static const amber72 = Color(0xFFFFB84D);

  /// The night warning container.
  static const amber22Dark = Color(0xFF3A2A0C);

  /// Text on amber22Dark.
  static const amber93Dark = Color(0xFFFFE0A0);

  /// Light-theme error text. Restrained red.
  static const red50Light = Color(0xFFC0392B);

  /// Light-theme error container.
  static const red95Light = Color(0xFFFDEDEA);

  /// Text on red95Light.
  static const red42Light = Color(0xFF8B2518);

  /// The night error text.
  static const red68 = Color(0xFFFF6B5B);

  /// The night error container.
  static const red22Dark = Color(0xFF3A1814);

  /// Text on red22Dark.
  static const red92Dark = Color(0xFFFFB3A8);

  /// Light-theme info text. Calm blue.
  static const blue47Light = Color(0xFF1A6BAA);

  /// Light-theme information container.
  static const blue95Light = Color(0xFFE5F2FC);

  /// Text on the light information container.
  static const blue35Light = Color(0xFF0C3B5E);

  /// Dark-theme info text.
  static const blue66 = Color(0xFF6AB0F5);

  /// Dark-theme information container.
  static const blue22Dark = Color(0xFF123047);

  /// Text on the dark information container.
  static const blue90Dark = Color(0xFFB7DEFF);

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
  static const cashNeutralLight = Color(0xFF5F6873);

  /// Cash neutral on the night canvas: the night theme's meaningful boundary,
  /// cooled to sit in the same ramp as everything else around it.
  static const cashNeutralDark = Color(0xFF8E97A3);
}
