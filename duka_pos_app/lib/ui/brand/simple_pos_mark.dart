import 'package:flutter/material.dart';

import '../../theme/primitives.dart';
import '../../theme/typography.dart';

/// The SimpleSales mark, drawn as vectors.
///
/// This is the launcher artwork from
/// `assets/branding/stitch_simple_pos_launcher_icon/` — the ink squircle, the
/// white terminal body, the botanical green screen — reproduced from the source
/// SVG rather than decoded from a PNG. The receipt that used to sit above the
/// terminal was removed: it read as paper rather than as a till, and at launcher
/// sizes the torn edge turned into noise. Three reasons the rest matters:
///
/// 1. **It was wrong before.** The in-app `SimplePosMark` that shipped in
///    `splash_screen.dart` inverted the brand: green plate, ink terminal. The
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
/// `flutter_svg` dependency to draw three shapes would be a worse trade than one
/// reviewed constant, and the source file stays the reference of record.
enum SimplePosMarkVariant {
  /// Plate + terminal + screen. The app icon and the splash.
  full,

  /// Terminal + screen, no plate. For placing the mark on a surface that is
  /// already the plate colour.
  foreground,

  /// Terminal only, one colour. For a themed-icon slot (Android's
  /// `monochrome` layer) where the platform tints it.
  monochrome,
}

/// The source SVG's coordinate space. Every dimension below is expressed in it
/// and scaled by `size / kBrandViewBox` at paint time.
const double kBrandViewBox = 512;

/// The mark's own ink. Deliberately NOT read from [AppColors]: a logo keeps its
/// identity in both brightnesses, so the plate is a brand constant and only the
/// screen's green lifts for a dark surface.
const Color kBrandInk = Primitives.neutral23;

/// The mark's screen accent — the brand's deep botanical green. Lifts in dark
/// mode so the terminal screen stays legible against the plate instead of
/// disappearing into it.
const Color kBrandScreenLight = Primitives.botanical38;
const Color kBrandScreenDark = Primitives.botanical58;

/// The brand paper — the mark's glyph colour in both brightnesses.
const Color kBrandPaper = Primitives.neutral100;

/// Renders the mark at [size], on the brand plate unless told otherwise.
///
/// The whole widget is one semantics node: a screen reader announcing "image,
/// SimpleSales" is correct, and so is announcing nothing at all where the mark is
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

  /// Overrides the S stroke's colour.
  final Color? glyph;

  /// Overrides the wine accent's colour.
  final Color? screen;

  /// Hides the mark from assistive tech. Use only where the same words appear
  /// as text within the next few characters.
  final bool decorative;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Semantics(
      image: true,
      label: decorative ? null : 'SimpleSales',
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: CustomPaint(
            painter: SimplePosMarkPainter(
              variant: variant,
              plate: plate ?? kBrandInk,
              glyph: glyph ?? kBrandPaper,
              screen: screen ?? (isDark ? kBrandScreenDark : kBrandScreenLight),
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

  /// The plate's corner radius, in 512-space.
  static const double _squircleRadius = 116;

  /// The "S": a bold geometric stroke matching the wordmark's type.
  ///
  /// Transcribed from `assets/branding/stitch_simple_pos_launcher_icon/
  /// simple_pos_geometric_s_icon/code.html`, which is the same source the
  /// launcher icons are rendered from — so the in-app mark and the icon on the
  /// home screen are finally the same shape, rather than the receipt-and-terminal
  /// composition that used to differ from them.
  static final Path _s = _buildS();

  /// The wine accent, offset from the S's lower bowl.
  static const Rect _accent = Rect.fromLTWH(130, 240, 32, 32);
  static const double _accentRadius = 16;

  static Path _buildS() => Path()
    ..moveTo(345, 130)
    ..cubicTo(370, 130, 388, 142, 396, 162)
    ..lineTo(345, 186)
    ..cubicTo(340, 174, 330, 168, 315, 168)
    ..cubicTo(292, 168, 280, 180, 280, 196)
    ..cubicTo(280, 212, 292, 222, 318, 232)
    ..lineTo(340, 240)
    ..cubicTo(382, 256, 402, 284, 402, 322)
    ..cubicTo(402, 368, 366, 400, 308, 400)
    ..cubicTo(255, 400, 220, 372, 210, 332)
    ..lineTo(262, 312)
    ..cubicTo(268, 335, 285, 352, 310, 352)
    ..cubicTo(334, 352, 348, 340, 348, 322)
    ..cubicTo(348, 304, 335, 294, 306, 282)
    ..lineTo(284, 274)
    ..cubicTo(246, 258, 228, 232, 228, 196)
    ..cubicTo(228, 154, 262, 130, 315, 130)
    ..lineTo(345, 130)
    ..close();

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

    canvas.drawPath(_s, Paint()..color = glyph);

    if (variant != SimplePosMarkVariant.monochrome) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(_accent, const Radius.circular(_accentRadius)),
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

/// The wordmark: "SimpleSales" in the brand face.
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
    this.semanticLabel = 'SimpleSales',
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
          'SimpleSales',
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
