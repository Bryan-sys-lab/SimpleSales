import 'package:material_ui/material_ui.dart';

import '../theme/app_colors.dart';
import '../theme/app_gradients.dart';
import '../ui/brand/simple_pos_mark.dart';

/// Startup status only. The app stage controller owns restoration and routing;
/// this screen never delays startup or invents a second navigation state.
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
  late final AnimationController _animation;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..addStatusListener(_onStatusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _animation
        ..stop()
        ..value = 1;
    } else if (_animation.status == AnimationStatus.dismissed) {
      if (widget.playOnce) {
        _animation.forward();
      } else {
        _animation.repeat(reverse: true);
      }
    }
  }

  void _onStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed && widget.playOnce) {
      widget.onAnimationComplete?.call();
    }
  }

  @override
  void dispose() {
    _animation
      ..removeStatusListener(_onStatusChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Scaffold(
      backgroundColor: colors.primaryButton,
      body: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (!reduceMotion)
              Image.asset(
                'assets/branding/simple_sales_startup_animation.gif',
                fit: BoxFit.cover,
                gaplessPlayback: true,
                excludeFromSemantics: true,
              )
            else
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: AppGradients.primary,
                ),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Color(0x33000000),
                    Color(0x66000000),
                    Color(0xCC000000),
                  ],
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: <Widget>[
                  const Spacer(),
                  AnimatedBuilder(
                    animation: _animation,
                    builder: (BuildContext context, Widget? child) {
                      final double progress =
                          reduceMotion ? 1 : _animation.value;
                      return Opacity(
                        opacity: 0.86 + progress * 0.14,
                        child: Transform.scale(
                          scale: 0.94 + progress * 0.06,
                          child: child,
                        ),
                      );
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const SimplePosMark(size: 88),
                        const SizedBox(height: 20),
                        SimplePosWordmark(
                          fontSize: 26,
                          color: colors.onMediaScrim,
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Semantics(
                    liveRegion: true,
                    label: 'SimpleSales. Opening your shop.',
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 36),
                      child: reduceMotion
                          ? Icon(
                              Icons.more_horiz,
                              color: colors.onMediaScrim,
                              size: 30,
                            )
                          : SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: colors.accent,
                                backgroundColor:
                                    colors.onMediaScrim.withValues(alpha: 0.18),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
