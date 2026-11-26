import 'package:material_ui/material_ui.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_shapes.dart';

class MembershipBackdrop extends StatelessWidget {
  const MembershipBackdrop({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ColoredBox(
      color: colors.canvas,
      child: CustomPaint(
        painter: _MembershipBackdropPainter(colors, isDark: isDark),
        child: child,
      ),
    );
  }
}

class MembershipCard extends StatelessWidget {
  const MembershipCard({
    required this.child,
    this.highlighted = false,
    this.padding = const EdgeInsets.all(16),
    super.key,
  });

  final Widget child;
  final bool highlighted;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final shapes = AppShapes.of(context);
    return Container(
      decoration: BoxDecoration(
        color: highlighted ? colors.accentContainer : colors.surface,
        borderRadius: shapes.cardRadius,
        border: Border.all(
          color: highlighted ? colors.accent : colors.outline,
          width: highlighted ? 1.25 : 1,
        ),
        boxShadow: highlighted
            ? [
                BoxShadow(
                  color: colors.accent.withValues(alpha: 0.12),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _MembershipBackdropPainter extends CustomPainter {
  const _MembershipBackdropPainter(this.colors, {required this.isDark});

  final AppColors colors;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final double greenAlpha = isDark ? 0.34 : 0.16;
    final double coralAlpha = isDark ? 0.55 : 0.28;
    final topSweep = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width * 0.52, 0)
      ..quadraticBezierTo(
        size.width * 0.33,
        size.height * 0.12,
        0,
        size.height * 0.32,
      )
      ..close();
    canvas.drawPath(
      topSweep,
      Paint()..color = colors.accentContainer.withValues(alpha: greenAlpha),
    );

    final bottomSweep = Path()
      ..moveTo(size.width, size.height * 0.74)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width * 0.16, size.height)
      ..quadraticBezierTo(
        size.width * 0.70,
        size.height * 0.91,
        size.width,
        size.height * 0.74,
      )
      ..close();
    canvas.drawPath(
      bottomSweep,
      Paint()..color = colors.successContainer.withValues(alpha: greenAlpha),
    );

    final coralSweep = Path()
      ..moveTo(-size.width * 0.08, size.height * 0.88)
      ..quadraticBezierTo(
        size.width * 0.13,
        size.height * 0.92,
        size.width * 0.28,
        size.height * 1.08,
      );
    canvas.drawPath(
      coralSweep,
      Paint()
        ..color = colors.danger.withValues(alpha: coralAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_MembershipBackdropPainter oldDelegate) =>
      colors != oldDelegate.colors || isDark != oldDelegate.isDark;
}
