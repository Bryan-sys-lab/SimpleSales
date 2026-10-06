import 'package:flutter/material.dart';

import '../../theme/primitives.dart';
import '../../theme/typography.dart';

/// The Simple POS mark, drawn as vectors.
///
/// This is the launcher artwork from
/// `assets/branding/stitch_simple_pos_launcher_icon/` — the ink squircle, the
/// white receipt with its torn edge, the white terminal body, the wine screen —
/// reproduced from the source SVG rather than decoded from a PNG. Three reasons
/// that matters:
///
/// 1. **It was wrong before.** The in-app `SimplePosMark` that shipped in
///    `splash_screen.dart` inverted the brand: wine plate, ink receipt. The
///    launcher icon on the device home screen and the logo inside the app were
///    two different logos.
/// 2. **It is crisp at every size** with no decode, which matters on the splash
///    path where a 1024px PNG decode is the first thing the frame does.
/// 3. **It scales with the theme** — the widget resolves the plate and the
///    screen colours and hands them to the painter, so the same geometry works
///    on paper and on a dark canvas.
///
/// The geometry below is expressed in the SVG's own 512-unit space and scaled by
/// [scale] at paint time. It is duplicated from the source SVG on purpose: a
/// `flutter_svg` dependency to draw four shapes would be a worse trade than one
/// reviewed constant, and the source file stays the reference of record.
enum SimplePosMarkVariant {
  /// Plate + receipt + terminal + screen. The app icon and the splash.
  full,

  /// Receipt + terminal + screen, no plate. For placing the mark on a surface
  /// that is already the plate colour.
  foreground,

  /// Receipt + terminal only, both one colour. For a themed-icon slot
  /// (Android's `monochrome` layer) where the platform tints it.
  monochrome,
}

/// The source SVG's coordinate space. Every dimension below is expressed in it
/// and scaled by `size / kBrandViewBox` at paint time.
const double kBrandViewBox = 512;

/// The brand's own ink. Deliberately NOT read from [AppColors]: a logo keeps its
/// identity in both brightnesses, so the plate is a brand constant and only the
/// screen's wine lifts for a dark surface.
const Color kBrandInk = Primitives.neutral23;

/// The mark's wine. Lifts in dark mode so the terminal screen stays legible
/// against the plate instead of disappearing into it.
const Color kBrandWineLight = Primitives.wine38;
const Color kBrandWineDark = Color(0xFFB04A66);

/// The brand paper — the mark's glyph colour in both brightnesses.
const Color kBrandPaper = Primitives.neutral100;

/// Renders the mark at [size], on the brand plate unless told otherwise.
///
/// The whole widget is one semantics node: a screen reader announcing "image,
/// Simple POS" is correct, and so is announcing nothing at all where the mark is
/// purely decorative next to a wordmark. Pass `decorative: true` in the second
/// case rather than leaving it to chance.
class SimplePosMark extends StatelessWidget {
  const SimplePosMark({
    this.size = 40,
    this.variant = SimplePosMarkVariant.full,
    this.plate,
    this.glyph,
    this.screen,
    this.decorative = false,
    super.key,
  });

  /// The rendered edge length in logical pixels.
  final double size;

  final SimplePosMarkVariant variant;

  /// Overrides the plate. Defaults to the brand ink; pass `null` with
  /// [SimplePosMarkVariant.foreground] to omit it.
  final Color? plate;

  /// Overrides the receipt and terminal colour.
  final Color? glyph;

  /// Overrides the terminal screen colour.
  final Color? screen;

  /// Hides the mark from assistive tech. Use only where the same words appear
  /// as text within the next few characters.
  final bool decorative;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Semantics(
      image: true,
      label: decorative ? null : 'Simple POS',
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: CustomPaint(
            painter: SimplePosMarkPainter(
              variant: variant,
              plate: plate ?? kBrandInk,
              glyph: glyph ?? kBrandPaper,
              screen: screen ?? (isDark ? kBrandWineDark : kBrandWineLight),
              scale: size / kBrandViewBox,
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints [SimplePosMarkVariant] from the launcher artwork.
///
/// A painter snapshots its colours: `paint()` must never reach a
/// `BuildContext`, because it runs on the raster path where an inherited-widget
/// lookup is both wrong and a per-frame cost.
class SimplePosMarkPainter extends CustomPainter {
  const SimplePosMarkPainter({
    required this.variant,
    required this.plate,
    required this.glyph,
    required this.screen,
    required this.scale,
  });

  final SimplePosMarkVariant variant;
  final Color plate;
  final Color glyph;
  final Color screen;

  /// Logical pixels per SVG unit.
  final double scale;

  // Corners and the receipt, in 512-space. Named so a reader can check them
  // against assets/branding/stitch_simple_pos_launcher_icon without arithmetic.
  static const double _squircleRadius = 116;
  static const Rect _terminalBody = Rect.fromLTWH(76.8, 337.92, 358.4, 106.496);
  static const double _terminalRadius = 23.552;
  static const Rect _terminalScreen =
      Rect.fromLTWH(102.4, 337.92, 307.2, 66.56);
  static const double _screenRadius = 10.24;

  /// The receipt: a 512-space path with a rounded top and a torn bottom edge of
  /// four teeth and three notches, the notches reaching up to y=276.48.
  static final Path _receipt = _buildReceipt();

  static Path _buildReceipt() {
    const double left = 171.52;
    const double right = 340.48;
    const double top = 66.56;
    const double bottom = 307.2;
    const double corner = 12.288;
    const double notch = 276.48;

    return Path()
      ..moveTo(183.808, top)
      ..lineTo(328.192, top)
      ..arcToPoint(
        const Offset(340.48, 78.848),
        radius: const Radius.circular(corner),
      )
      ..lineTo(right, bottom)
      // The torn edge, walked right to left: flat, up to a notch, down to a
      // tooth, flat — repeated to the bottom-left corner.
      ..lineTo(322.048, bottom)
      ..lineTo(300.928, notch)
      ..lineTo(279.808, bottom)
      ..lineTo(267.328, bottom)
      ..lineTo(256.0, notch)
      ..lineTo(244.672, bottom)
      ..lineTo(232.192, bottom)
      ..lineTo(211.072, notch)
      ..lineTo(189.952, bottom)
      ..lineTo(left, bottom)
      ..lineTo(left, 78.848)
      ..arcToPoint(
        const Offset(183.808, top),
        radius: const Radius.circular(corner),
      )
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(scale);

    if (variant != SimplePosMarkVariant.foreground) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, kBrandViewBox, kBrandViewBox),
          const Radius.circular(_squircleRadius),
        ),
        Paint()..color = plate,
      );
    }

    canvas.drawPath(_receipt, Paint()..color = glyph);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
          _terminalBody, const Radius.circular(_terminalRadius)),
      Paint()..color = glyph,
    );

    if (variant != SimplePosMarkVariant.monochrome) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          _terminalScreen,
          const Radius.circular(_screenRadius),
        ),
        Paint()..color = screen,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(SimplePosMarkPainter old) =>
      old.variant != variant ||
      old.plate != plate ||
      old.glyph != glyph ||
      old.screen != screen ||
      old.scale != scale;
}

/// The wordmark: "Simple POS" in the brand face.
///
/// A separate widget rather than a `Text` at each call site so the tracking and
/// the weight are one decision. Tracking is positive (0.08em, per the brand
/// hero) because this is a logotype, not a heading — a display style at negative
/// tracking would be the wrong call here.
///
/// [fontSize] is a raw number and this is the one file allowed to carry one: the
/// logotype's size is part of the brand's proportions, not a token a screen
/// picks from a scale, and routing it through `AppTypography` would pretend it
/// is interchangeable with body copy when it is not.
class SimplePosWordmark extends StatelessWidget {
  const SimplePosWordmark({
    this.fontSize = 20,
    this.color,
    this.semanticLabel = 'Simple POS',
    super.key,
  });

  final double fontSize;
  final Color? color;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      child: ExcludeSemantics(
        child: Text(
          'Simple POS',
          style: TextStyle(
            fontFamily: AppTypography.family,
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            letterSpacing: fontSize * 0.08,
            height: 1.1,
            color: color ?? Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}
