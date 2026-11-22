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
  // The light ramp is warm and quiet; the dark ramp has a subtle green cast.
  // Elevation is read as luminance, while forest, electric green and coral are
  // reserved for brand, positive and attention states.
  //
  // The numbers are lightness steps, not hues: 04 is the deepest value in the
  // app and 100 the lightest. Nothing in `lib/` outside this file names a
  // colour.

  /// The deepest value in the app: a sunken well below the night canvas.
  static const neutral04 = Color(0xFF111812);

  /// The night canvas.
  static const neutral08 = Color(0xFF0C130E);

  /// One step above the night canvas.
  static const neutral12 = Color(0xFF172019);

  /// The night surface: a card, a tile, a panel resting on the canvas.
  static const neutral16 = Color(0xFF172019);

  /// A surface resting on another surface: a dialog, a dropdown, a snackbar.
  static const neutral20 = Color(0xFF202A22);

  /// A control surface: an input field, a chip, a track.
  static const neutral25 = Color(0xFF27332A);

  /// The hairline. Decorative only: below 3:1.
  static const neutral32 = Color(0xFF334438);

  /// A meaningful boundary: an input edge, a focus ring.
  static const neutral45 = Color(0xFF738576);

  /// Muted text on a night surface: clears 4.5:1.
  static const neutral63 = Color(0xFFA0ADA3);

  /// Secondary text on a night surface.
  static const neutral79 = Color(0xFFC4CEC5);

  /// Body text on a night surface. A soft off-white.
  static const neutral95 = Color(0xFFF4F6F2);

  /// Light-theme body ink: the brand ink, and not pure black.
  ///
  /// PINNED. This value is the launcher icon's plate, the Android `brand_ink`
  /// colour resource, the splash background and the mark's ink — see
  /// `assets/branding/generate_launcher_icon.py`. Changing it here without
  /// regenerating those artefacts is how an app ends up with two logos.
  static const neutral23 = Color(0xFF2D2A26);

  /// Light-theme secondary and tertiary body text. The supplied #69766D is
  /// slightly below 4.5:1 on the warm page canvas, so text uses this darker
  /// accessible adjustment.
  static const neutral47 = Color(0xFF667269);

  /// Light-theme meaningful boundary: clears 3:1 on the canvas and on a card.
  static const neutral54 = Color(0xFF69766D);

  /// Light-theme hairline. Decorative only.
  static const neutral84 = Color(0xFFE8ECE7);

  /// Sunken wells, chips, table stripes.
  static const neutral94 = Color(0xFFF1F4F0);

  /// The warm off-white app canvas behind cards.
  static const neutral97 = Color(0xFFF7F8F5);

  /// Card and sheet surface. White.
  static const neutral100 = Color(0xFFFFFFFF);

  /// Body ink from the product palette; distinct from the launcher mark's ink.
  static const textInk = Color(0xFF17231B);

  /// Forest brand color used for primary actions and featured cards.
  static const forest = Color(0xFF174B35);

  /// Lighter forest stop for the primary gradient and dark-theme buttons.
  static const forestLight = Color(0xFF286447);

  /// Slightly lighter forest fill to preserve a visible button boundary in dark
  /// mode while retaining accessible white button text.
  static const forestButtonDark = Color(0xFF3B7755);

  /// Electric-green highlight.
  static const electric = Color(0xFFB7F34A);

  /// Coral accent for attention and secondary emphasis.
  static const coral = Color(0xFFFF806F);

  /// Contrast-safe coral text on soft coral surfaces.
  static const coralInk = Color(0xFF8A2E24);

  /// Warm page, inset, and card borders.
  static const surfacePage = Color(0xFFF7F8F5);
  static const surfaceInset = Color(0xFFF1F4F0);
  static const borderDefault = Color(0xFFE8ECE7);

  /// Soft, restrained brand and accent surfaces.
  static const surfaceGreen = Color(0xFFEAF5E9);
  static const surfaceElectric = Color(0xFFE9F8D9);
  static const surfaceElectricStrong = Color(0xFFD7F2B6);
  static const surfaceCoral = Color(0xFFFFF0EC);
  static const surfaceCoralStrong = Color(0xFFFFDAD2);

  /// Dark-theme counterparts of the soft accent surfaces.
  static const surfaceGreenDark = Color(0xFF183323);
  static const surfaceElectricDark = Color(0xFF1D3826);
  static const surfaceElectricStrongDark = Color(0xFF234A2C);
  static const surfaceCoralDark = Color(0xFF42231F);
  static const surfaceCoralStrongDark = Color(0xFF572F29);

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

  // -------------------------------------------------------------------- supplied brand mark

  /// The light brand green: deep botanical. Clears 4.5:1 on the light canvas.
  ///
  /// PINNED. This value is painted into the launcher icon and the brand hero
  /// artwork — see `assets/branding/generate_launcher_icon.py`.
  static const botanical38 = Color(0xFF1B6B3A);

  // -------------------------------------------------------------------- status semantics
  // Each status is three values: text tone, container, on-container.
  // Colour is never the only channel — see StatusTone for glyph + word.

  /// Light-theme success container.
  static const green95Light = Color(0xFFE9F8D9);

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
