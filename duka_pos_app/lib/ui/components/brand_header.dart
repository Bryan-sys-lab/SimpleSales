import 'package:flutter/material.dart';

import '../brand/simple_pos_mark.dart';

/// Shared brand lockup at the head of every screen header.
///
/// One definition so the mark size, gap, and wordmark cannot drift across
/// screens. Pass [title] (usually `Text(l10n.xxxTitle)`); the widget renders
/// mark, optional wordmark, and title in reading order, mirroring under RTL
/// through `SizedBox` gap. The strip carries a single `Semantics` image node
/// so a screen reader announces "SimpleSales" once instead of stuttering on
/// mark and wordmark separately.
class BrandHeader extends StatelessWidget {
  const BrandHeader({
    this.title,
    this.markSize = 20.0,
    this.gap = 8.0,
    this.showWordmark = false,
    this.wordmarkFontSize = 16.0,
    super.key,
  });

  /// The screen title, typically `Text(l10n.xxxTitle)`. Omit for mark-only
  /// strips (wordmark beside mark, no title).
  final Widget? title;

  /// Brand mark size in logical pixels.
  final double markSize;

  /// Gap between mark/wordmark and title.
  final double gap;

  /// Whether to render the wordmark between the mark and the title.
  final bool showWordmark;

  /// Wordmark font size in logical pixels.
  final double wordmarkFontSize;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'SimpleSales',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SimplePosMark(size: markSize, variant: SimplePosMarkVariant.full),
            SizedBox(width: gap),
            if (showWordmark) SimplePosWordmark(fontSize: wordmarkFontSize),
            if (title != null) title!,
          ],
        ),
      ),
    );
  }
}
