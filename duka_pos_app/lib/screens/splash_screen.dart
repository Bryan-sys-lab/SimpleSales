import 'package:flutter/material.dart';

import '../app_brand.dart';
import '../theme/app_theme.dart';

/// The startup page.
///
/// Shown while the till reads its own state — opening the database, resolving
/// which workspace is active, finding out whether a shop exists. It exists so
/// that first launch is a deliberate moment showing the product's own identity
/// rather than a spinner on a blank background, and so the first frame the
/// merchant sees is branded.
///
/// It deliberately shows no shop name, no data and no controls: at this point
/// the app does not yet know who is signed in, and a splash that renders
/// something is a splash that can leak something.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DukaColors.ink,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The mark, drawn rather than loaded, so it is correct on the first
            // frame and cannot flash unstyled while a PNG decodes.
            const SimplePosMark(size: 88),
            const SizedBox(height: 20),
            Text(
              SimplePosBrand.appName,
              style: const TextStyle(
                color: DukaColors.surface,
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Point of sale, built for the till it runs on',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: DukaColors.surface.withValues(alpha: 0.7),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 28),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: DukaColors.primary),
            ),
            const SizedBox(height: 40),
            Text(
              SimplePosBrand.poweredByTag,
              style: TextStyle(
                color: DukaColors.surface.withValues(alpha: 0.55),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Simple POS mark, drawn.
///
/// A `CustomPainter` rather than an asset for one reason that matters here: the
/// splash is the very first frame on a cold boot, and an image that has not
/// decoded yet renders as nothing on some devices. A mark described by code is
/// correct immediately, at any pixel ratio, and stays crisp.
///
/// The shape is a receipt with a torn bottom edge. Flat, solid, and readable as
/// a silhouette at launcher-icon size — Android applies a themed icon mask and
/// may tint it, so fine interior detail would be lost.
class SimplePosMark extends StatelessWidget {
  const SimplePosMark({super.key, this.size = 64});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _MarkPainter()),
    );
  }
}

class _MarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Rounded-square background.
    final bg = Paint()..color = DukaColors.primary;
    final radius = w * 0.22;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      bg,
    );

    // The receipt body, inset.
    final pad = w * 0.26;
    final body = Rect.fromLTWH(pad, pad * 0.82, w - pad * 2, h - pad * 1.7);
    final receipt = Paint()..color = DukaColors.ink;

    // Torn bottom edge: a zigzag of triangles, which is what makes it read as
    // a receipt rather than a document. Drawn as one path so there is no seam.
    final zigzag = Path()..addRRect(RRect.fromRectAndRadius(body, Radius.circular(w * 0.05)));
    final teeth = 4;
    final toothWidth = body.width / teeth;
    final toothDepth = body.height * 0.09;
    final baseY = body.bottom;
    for (var i = 0; i < teeth; i++) {
      final x = body.left + toothWidth * i;
      zigzag.lineTo(x + toothWidth / 2, baseY + toothDepth);
      zigzag.lineTo(x + toothWidth, baseY);
    }
    zigzag.close();
    canvas.drawPath(zigzag, receipt);

    // Three lines standing in for text. Wide and few, so they survive being
    // scaled down to a launcher icon.
    final line = Paint()
      ..color = DukaColors.primary
      ..strokeWidth = h * 0.045
      ..strokeCap = StrokeCap.round;
    final left = body.left + body.width * 0.18;
    canvas.drawLine(Offset(left, body.top + body.height * 0.26),
        Offset(body.right - body.width * 0.18, body.top + body.height * 0.26), line);
    canvas.drawLine(Offset(left, body.top + body.height * 0.48),
        Offset(body.right - body.width * 0.45, body.top + body.height * 0.48), line);
    canvas.drawLine(Offset(left, body.top + body.height * 0.70),
        Offset(body.right - body.width * 0.60, body.top + body.height * 0.70), line);
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) => false;
}