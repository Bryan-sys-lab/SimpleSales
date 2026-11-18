import 'dart:math' as math;
import 'package:flutter/material.dart';


/// Native, full-screen simpleSales startup animation.
///
/// Render this while the app is initializing. Do not use it as a route that
/// navigates by itself. The parent application should decide when startup is
/// complete and when to replace this widget with the authenticated app.
class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    this.onAnimationComplete,
    this.playOnce = true,
  });

  final VoidCallback? onAnimationComplete;
  final bool playOnce;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  late final Animation<double> _borderProgress;
  late final Animation<double> _innerEdgeProgress;
  late final Animation<double> _letterOpacity;
  late final Animation<double> _letterScale;
  late final Animation<double> _dotOpacity;
  late final Animation<double> _wordmarkOpacity;
  late final Animation<Offset> _wordmarkOffset;
  late final Animation<double> _captionOpacity;
  late final Animation<double> _captionLineProgress;
  late final Animation<double> _auraOpacity;

  bool _completionSent = false;

  static const _duration = Duration(milliseconds: 3100);

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: _duration,
    );

    _borderProgress = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.06, 0.48, curve: Curves.easeInOutCubic),
    );

    _innerEdgeProgress = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.25, 0.58, curve: Curves.easeOut),
    );

    _letterOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.34, 0.58, curve: Curves.easeOut),
    );

    _letterScale = Tween<double>(begin: 0.78, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.34, 0.62, curve: Curves.easeOutBack),
      ),
    );

    _dotOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.43, 0.62, curve: Curves.easeOut),
    );

    _wordmarkOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.51, 0.76, curve: Curves.easeOut),
    );

    _wordmarkOffset = Tween<Offset>(
      begin: const Offset(0, 0.22),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.51, 0.76, curve: Curves.easeOutCubic),
      ),
    );

    _captionOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.70, 0.91, curve: Curves.easeOut),
    );

    _captionLineProgress = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.66, 0.88, curve: Curves.easeOutCubic),
    );

    _auraOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.02, 0.48, curve: Curves.easeOut),
    );

    _controller.addStatusListener(_handleStatus);
    _controller.forward();
  }

  void _handleStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      if (!_completionSent) {
        _completionSent = true;
        widget.onAnimationComplete?.call();
      }
      if (!widget.playOnce) {
        _controller.repeat();
      }
    }
  }

  @override
  void didUpdateWidget(covariant SplashScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    _controller
      ..removeStatusListener(_handleStatus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Scaffold(
      backgroundColor: const Color(0xFF020703),
      body: SizedBox.expand(
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: Color(0xFF020703),
            gradient: RadialGradient(
              center: Alignment(0, -0.04),
              radius: 0.82,
              colors: [
                Color(0xFF092514),
                Color(0xFF041109),
                Color(0xFF020703),
              ],
              stops: [0, 0.48, 1],
            ),
          ),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final pulse = 0.5 +
                  0.5 * math.sin(_controller.value * math.pi * 2.0);

              return Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: 0.20 + (pulse * 0.07),
                        child: const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: Alignment(0, -0.03),
                              radius: 0.48,
                              colors: [
                                Color(0x2522E96E),
                                Color(0x0A16A94D),
                                Colors.transparent,
                              ],
                              stops: [0, 0.48, 1],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: Transform.translate(
                      offset: const Offset(0, -8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: _iconSize(size),
                            height: _iconSize(size),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Opacity(
                                  opacity: _auraOpacity.value *
                                      (0.78 + pulse * 0.22),
                                  child: const DecoratedBox(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: RadialGradient(
                                        colors: [
                                          Color(0x5530F477),
                                          Color(0x1A0C9D43),
                                          Colors.transparent,
                                        ],
                                        stops: [0, 0.42, 1],
                                      ),
                                    ),
                                  ),
                                ),
                                CustomPaint(
                                  painter: _SimpleSalesMarkPainter(
                                    borderProgress: _borderProgress.value,
                                    innerEdgeProgress:
                                        _innerEdgeProgress.value,
                                    letterOpacity: _letterOpacity.value,
                                    letterScale: _letterScale.value,
                                    dotOpacity: _dotOpacity.value,
                                    pulse: pulse,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          FadeTransition(
                            opacity: _wordmarkOpacity,
                            child: SlideTransition(
                              position: _wordmarkOffset,
                              child: RichText(
                                textAlign: TextAlign.center,
                                text: const TextSpan(
                                  style: TextStyle(
                                    fontFamily: 'PlusJakartaSans',
                                    fontSize: 54,
                                    height: 1,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -3.8,
                                  ),
                                  children: [
                                    TextSpan(
                                      text: 'simple',
                                      style: TextStyle(
                                        color: Color(0xFFF5F7F5),
                                      ),
                                    ),
                                    TextSpan(
                                      text: 'Sales',
                                      style: TextStyle(
                                        color: Color(0xFF27DF6B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 13),
                          FadeTransition(
                            opacity: _captionOpacity,
                            child: _Caption(
                              lineProgress: _captionLineProgress.value,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  double _iconSize(Size size) {
    final shortest = size.shortestSide;
    final height = size.height;
    if (height < 560) return 112;
    return (shortest * 0.34).clamp(126.0, 190.0);
  }
}

class _Caption extends StatelessWidget {
  const _Caption({required this.lineProgress});

  final double lineProgress;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CaptionRule(progress: lineProgress, left: true),
          const SizedBox(width: 11),
          const Text(
            'sell.manage.grow',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFFB8C9BC),
              fontSize: 13,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.45,
              fontFamily: 'PlusJakartaSans',
            ),
          ),
          const SizedBox(width: 11),
          _CaptionRule(progress: lineProgress, left: false),
        ],
      ),
    );
  }
}

class _CaptionRule extends StatelessWidget {
  const _CaptionRule({required this.progress, required this.left});

  final double progress;
  final bool left;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30 * progress,
      height: 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: left ? Alignment.centerLeft : Alignment.centerRight,
            end: left ? Alignment.centerRight : Alignment.centerLeft,
            colors: const [
              Color(0x0035EF78),
              Color(0xFF1ABF5C),
            ],
          ),
        ),
      ),
    );
  }
}

class _SimpleSalesMarkPainter extends CustomPainter {
  const _SimpleSalesMarkPainter({
    required this.borderProgress,
    required this.innerEdgeProgress,
    required this.letterOpacity,
    required this.letterScale,
    required this.dotOpacity,
    required this.pulse,
  });

  final double borderProgress;
  final double innerEdgeProgress;
  final double letterOpacity;
  final double letterScale;
  final double dotOpacity;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 100;
    canvas.save();
    canvas.scale(scale);

    final rect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(5, 5, 90, 90),
      const Radius.circular(21),
    );

    final borderPath = Path()..addRRect(rect);
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.55
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
        colors: [
          Color(0xFF0B7738),
          Color(0xFF31ED78),
          Color(0xFF8AFFAE),
          Color(0xFF19B957),
        ],
      ).createShader(const Rect.fromLTWH(5, 5, 90, 90))
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        1.0 + pulse * 1.2,
      );

    _drawPathProgress(
      canvas,
      borderPath,
      borderProgress,
      borderPaint,
    );

    final innerPath = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(6.5, 6.5, 87, 87),
          const Radius.circular(19.5),
        ),
      );

    final innerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.65
      ..color = const Color(0xFF9FFFBB).withValues(alpha: 0.32);

    _drawPathProgress(
      canvas,
      innerPath,
      innerEdgeProgress,
      innerPaint,
    );

    if (dotOpacity > 0) {
      final dotPaint = Paint()
        ..color = const Color(0xFF20F477).withValues(alpha: dotOpacity)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          1.0 + pulse * 1.5,
        );

      canvas.drawCircle(
        const Offset(29, 50),
        3.5 * (0.2 + 0.8 * dotOpacity),
        dotPaint,
      );
    }

    if (letterOpacity > 0) {
      canvas.save();
      canvas.translate(62, 51);
      canvas.scale(letterScale);
      final textPainter = TextPainter(
        text: TextSpan(
          text: 'S',
          style: TextStyle(
            color: const Color(0xFFF8FAF8).withValues(alpha: letterOpacity),
            fontSize: 68,
            fontWeight: FontWeight.w800,
            fontFamily: 'PlusJakartaSans',
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(
        canvas,
        Offset(-textPainter.width / 2, -textPainter.height / 2 + 1),
      );
      canvas.restore();
    }

    canvas.restore();
  }

  void _drawPathProgress(
    Canvas canvas,
    Path path,
    double progress,
    Paint paint,
  ) {
    if (progress <= 0) return;
    if (progress >= 1) {
      canvas.drawPath(path, paint);
      return;
    }

    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;

    final totalLength = metrics.fold<double>(
      0,
      (sum, metric) => sum + metric.length,
    );
    var remaining = totalLength * progress;

    for (final metric in metrics) {
      if (remaining <= 0) break;
      final length = math.min(remaining, metric.length).toDouble();
      canvas.drawPath(metric.extractPath(0, length), paint);
      remaining -= length;
    }
  }

  @override
  bool shouldRepaint(covariant _SimpleSalesMarkPainter oldDelegate) {
    return borderProgress != oldDelegate.borderProgress ||
        innerEdgeProgress != oldDelegate.innerEdgeProgress ||
        letterOpacity != oldDelegate.letterOpacity ||
        letterScale != oldDelegate.letterScale ||
        dotOpacity != oldDelegate.dotOpacity ||
        pulse != oldDelegate.pulse;
  }
}
