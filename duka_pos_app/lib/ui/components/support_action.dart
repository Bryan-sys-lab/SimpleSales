// The support action: a small icon in the app bar.
//
// ## WHY IT IS NOT A BUBBLE ANY MORE
//
// It used to be a 48dp floating circle with a raised surface, a hairline and a
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
// The interaction uses the shared Material button feedback and preserves the
// full semantic/action surface for TalkBack and Switch Access.

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// Opens the support page. A plain icon button, sized and weighted like the
/// account and sign-out actions beside it.
class SupportAction extends StatelessWidget {
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

  /// The preferred Android tap target. The icon inside is small, and the
  /// target around it is the part that has to be reachable.
  static const double size = 48;

  /// The glyph. Smaller than the tap target on purpose — a top bar full of
  /// icon-sized icons reads as a toolbar, and this bar is not one.
  static const double iconSize = 20;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Semantics(
      button: true,
      label: label,
      child: IconButton(
        onPressed: onTap,
        tooltip: label,
        constraints: const BoxConstraints(
          minWidth: SupportAction.size,
          minHeight: SupportAction.size,
        ),
        icon: Icon(
          Icons.support_agent_outlined,
          size: SupportAction.iconSize,
          color: colors.onSurfaceVariant,
        ),
      ),
    );
  }
}
