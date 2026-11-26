import 'package:material_ui/material_ui.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

class ShopScreenBackground extends StatelessWidget {
  const ShopScreenBackground({
    required this.child,
    required this.brightness,
    required this.colors,
    this.isShopScreen = true,
    super.key,
  });

  final Widget child;
  final Brightness brightness;
  final AppColors colors;
  final bool isShopScreen;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: colors.canvas,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (isShopScreen)
            IgnorePointer(
              child: CustomPaint(
                painter: _ShopScreenBackgroundPainter(
                  colors: colors,
                  isDark: brightness == Brightness.dark,
                ),
              ),
            ),
          child,
        ],
      ),
    );
  }
}

class _ShopScreenBackgroundPainter extends CustomPainter {
  const _ShopScreenBackgroundPainter({
    required this.colors,
    required this.isDark,
  });

  final AppColors colors;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.canvas, colors.surfaceSunken, colors.canvas],
        ).createShader(bounds),
    );

    final topGlow = Offset(size.width * 0.94, size.height * 0.16);
    final glowBounds = Rect.fromCircle(
      center: topGlow,
      radius: size.width * 0.58,
    );
    canvas.drawCircle(
      topGlow,
      size.width * 0.58,
      Paint()
        ..shader = RadialGradient(
          colors: [
            colors.accent.withValues(alpha: isDark ? 0.16 : 0.08),
            colors.accent.withValues(alpha: 0),
          ],
        ).createShader(glowBounds),
    );

    final topSweep = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width * 0.76, 0)
      ..quadraticBezierTo(
        size.width * 0.45,
        size.height * 0.13,
        0,
        size.height * 0.29,
      )
      ..close();
    canvas.drawPath(
      topSweep,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [colors.accentContainer, colors.canvas],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height * 0.32)),
    );

    final topCurve = Path()
      ..moveTo(size.width * 1.03, size.height * 0.09)
      ..quadraticBezierTo(
        size.width * 0.84,
        size.height * 0.23,
        size.width * 0.70,
        size.height * 0.34,
      );
    canvas.drawPath(
      topCurve,
      Paint()
        ..color = colors.accent.withValues(alpha: isDark ? 0.52 : 0.28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = AppSpacing.standard.hairline * 2,
    );
    _paintCoralCurve(
      canvas,
      Path()
        ..moveTo(size.width * 1.04, size.height * 0.17)
        ..quadraticBezierTo(
          size.width * 0.82,
          size.height * 0.25,
          size.width * 0.70,
          size.height * 0.38,
        ),
      isDark ? 0.82 : 0.38,
    );

    final bottomSweep = Path()
      ..moveTo(size.width, size.height * 0.79)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width * 0.19, size.height)
      ..quadraticBezierTo(
        size.width * 0.72,
        size.height * 0.91,
        size.width,
        size.height * 0.79,
      )
      ..close();
    canvas.drawPath(
      bottomSweep,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [colors.successContainer, colors.canvas],
        ).createShader(
          Rect.fromLTWH(
            0,
            size.height * 0.78,
            size.width,
            size.height * 0.22,
          ),
        ),
    );
    _paintCoralCurve(
      canvas,
      Path()
        ..moveTo(-size.width * 0.08, size.height * 0.89)
        ..quadraticBezierTo(
          size.width * 0.12,
          size.height * 0.94,
          size.width * 0.30,
          size.height * 1.08,
        ),
      isDark ? 1 : 0.28,
    );
  }

  void _paintCoralCurve(Canvas canvas, Path path, double opacity) {
    canvas.drawPath(
      path,
      Paint()
        ..color = colors.warning.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = AppSpacing.standard.xs
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ShopScreenBackgroundPainter oldDelegate) =>
      colors != oldDelegate.colors || isDark != oldDelegate.isDark;
}
