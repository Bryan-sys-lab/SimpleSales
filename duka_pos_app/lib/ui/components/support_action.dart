// The support action: a small icon in the app bar.
//
// ## WHY IT IS NOT A BUBBLE ANY MORE
//
// It used to be a 44dp floating circle with a raised surface, a hairline and a
// shadow, sitting in the corner of the page. That is the shape every website's
// help widget has, and on a phone it read as a floating message button — a
// large, chat-shaped object that followed the thumb and, when the keyboard
// opened, rode up over the buttons at the far end of the screen.
//
// The bar already has two plain icons that mean things (the account and sign
// out). Support is the third thing that means something, so it is the third
// plain icon. No circle, no shadow, no chat bubble: those said "widget", and
// what this is is a destination.
//
// ## WHY IT SITS BEFORE THE NAME
//
// The name and the account icon answer one question — "who am I signed in as,
// and where do I change that?" — and a support icon wedged between them
// breaks the pair. So support comes first, then the name, then the account.
//
// ## THE ONLY MOTION
//
// A press scale of 0.97 over a hundred and twenty milliseconds. It is the
// shortest role the motion scale has and it collapses to nothing under reduced
// motion: the press is still acknowledged, it just does not travel.

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';

/// Opens the support page. A plain icon button, sized and weighted like the
/// account and sign-out actions beside it.
class SupportAction extends StatefulWidget {
  const SupportAction({
    required this.onTap,
    required this.label,
    super.key,
  });

  /// Opens the support page.
  final VoidCallback onTap;

  /// What a screen reader calls it.
  ///
  /// Passed in rather than read from the localisations here, so this widget
  /// stays a leaf with no dependencies beyond the theme — and so the shell,
  /// which owns the wording, owns the wording.
  final String label;

  /// The tap target. The accessibility floor, and no more: the icon inside is
  /// small, and the target around it is the part that has to be reachable.
  static const double size = 44;

  /// The glyph. Smaller than the tap target on purpose — a top bar full of
  /// icon-sized icons reads as a toolbar, and this bar is not one.
  static const double iconSize = 20;

  @override
  State<SupportAction> createState() => _SupportActionState();
}

class _SupportActionState extends State<SupportAction> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppMotion motion = AppMotion.of(context);

    return Tooltip(
      message: widget.label,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: widget.label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedScale(
            scale: _pressed ? 0.97 : 1.0,
            duration: AppMotion.resolve(context, motion.instant),
            curve: AppMotion.resolveCurve(context, motion.enter),
            child: SizedBox(
              width: SupportAction.size,
              height: SupportAction.size,
              child: Icon(
                Icons.support_agent_outlined,
                size: SupportAction.iconSize,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
