import 'package:flutter/material.dart';

import '../../app_brand.dart';
import '../../theme/typography.dart';
import 'simple_pos_mark.dart';

/// The first-frame brand lockup: the S arrives with weight, then the name is
/// written in one letter at a time. It is a short orientation moment, not a
/// loading mechanism, so reduced motion receives the finished lockup at once.
class AnimatedStartupBrand extends StatefulWidget {
  const AnimatedStartupBrand({super.key});

  @override
  State<AnimatedStartupBrand> createState() => _AnimatedStartupBrandState();
}

class _AnimatedStartupBrandState extends State<AnimatedStartupBrand>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else if (!_controller.isAnimating && _controller.value == 0) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool reduced = MediaQuery.disableAnimationsOf(context);
    final Color ink = Theme.of(context).colorScheme.onSurface;
    final TextStyle style =
        (AppTypography.of(context).headlineSmall ?? const TextStyle()).copyWith(
      fontFamily: AppTypography.family,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.6,
      color: ink,
    );

    return Semantics(
      label: SimplePosBrand.appName,
      image: true,
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final double markProgress =
              reduced ? 1 : const Interval(0, .52).transform(_controller.value);
          final double markValue = Curves.easeOutCubic.transform(markProgress);
          final double markScale = .82 + markValue * .18;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Transform.scale(
                scale: markScale,
                child: const SimplePosMark(size: 76),
              ),
              const SizedBox(height: 14),
              Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  // Keep the lockup discoverable as one text value for simple
                  // UI tooling while the visible layer animates each letter.
                  ExcludeSemantics(
                    child: Text(
                      SimplePosBrand.appName,
                      style: style.copyWith(color: Colors.transparent),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      for (var i = 0; i < SimplePosBrand.appName.length; i++)
                        _letter(
                          SimplePosBrand.appName[i],
                          i,
                          style,
                          reduced ? 1 : _controller.value,
                        ),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _letter(String letter, int index, TextStyle style, double progress) {
    final double start = .35 + index * .045;
    final double value = ((progress - start) / .34).clamp(0.0, 1.0);
    final double eased = Curves.easeOutCubic.transform(value);
    final bool drops = index.isOdd;
    return Opacity(
      opacity: eased,
      child: Transform.translate(
        offset: drops ? Offset(0, (1 - eased) * -10) : Offset.zero,
        child: Transform.scale(
          scale: drops ? 1 : .92 + eased * .08,
          child: Text(letter, style: style),
        ),
      ),
    );
  }
}
