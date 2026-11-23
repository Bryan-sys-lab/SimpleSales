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
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: AppGradients.primary,
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
                        opacity: 0.72 + progress * 0.28,
                        child: Transform.scale(
                          scale: 0.84 + progress * 0.16,
                          child: child,
                        ),
                      );
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        SimplePosMark(
                          size: 76,
                          screen: colors.electric,
                          decorative: true,
                        ),
                        const SizedBox(height: 16),
                        SimplePosWordmark(
                          fontSize: 24,
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
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colors.electric,
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
