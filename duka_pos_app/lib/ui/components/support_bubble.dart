// A floating bubble that opens the support page.
//
// ## WHY A BUBBLE
//
// Support was a tab in the bottom bar, which is a poor place for it: it took
// a slot from the bar's symmetry, and a person who needs help is not browsing
// the app — they want to say something NOW, from wherever they are.
//
// So it is a bubble in the corner, the way every website's help widget is,
// and the bar keeps its symmetry.
//
// ## WHY IT IS LIGHT
//
// The bubble is a leaf: a gesture detector, an icon and a shadow. It holds no
// state beyond "is the finger down", it reads nothing, it subscribes to
// nothing, and it never rebuilds the page behind it — the page is a SIBLING in
// the stack, not its child. A help widget that made the till redraw on every
// pointer move would be a help widget that costs money at the counter.
//
// The one animation is the press: it scales to 94% and back over a hundred
// milliseconds. That is the feedback that tells the finger it was heard, and
// it is short because the bubble is tapped in a hurry.

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_shapes.dart';

/// The floating support bubble.
class SupportBubble extends StatefulWidget {
  const SupportBubble({
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

  /// The bubble's diameter. The 44dp floor, and no more: a bubble is an
  /// invitation, not a control, and it sits over the till's content.
  static const double size = 44;

  @override
  State<SupportBubble> createState() => _SupportBubbleState();
}

class _SupportBubbleState extends State<SupportBubble> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppShapes shapes = AppShapes.of(context);
    final AppMotion motion = AppMotion.of(context);

    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.94 : 1.0,
          // A press acknowledgement, not an entrance. It is the shortest role
          // the motion scale has, and it collapses to nothing under reduced
          // motion — the state change is still there, it just does not travel.
          duration: AppMotion.resolve(context, motion.instant),
          curve: AppMotion.resolveCurve(context, motion.enter),
          child: DecoratedBox(
            // The bubble's whole appearance is ONE decoration: the raised
            // surface, the hairline edge and the shadow that lifts it off the
            // page. A `Material` elevation would be a second, competing answer
            // to the same question, and a literal elevation here is a height
            // nobody chose.
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.surfaceRaised,
              border: Border.all(color: colors.outline),
              boxShadow: shapes.floatingShadow,
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: widget.onTap,
                customBorder: const CircleBorder(),
                child: SizedBox(
                  width: SupportBubble.size,
                  height: SupportBubble.size,
                  child: Icon(
                    Icons.chat_bubble_outline,
                    size: 21,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
