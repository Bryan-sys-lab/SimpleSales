import 'package:flutter/material.dart';

import '../brand/simple_pos_mark.dart';
import '../../app_brand.dart';
import '../../theme/app_spacing.dart';

/// Shared brand lockup at the head of every screen header.
///
/// One definition so the mark size, gap, and wordmark cannot drift across
/// screens. Pass [title] (usually `Text(l10n.xxxTitle)`); the widget renders
/// mark, optional wordmark, and title in reading order, mirroring under RTL
/// through `SizedBox` gap. The strip carries a single `Semantics` image node
/// so a screen reader announces "SimpleSales" once instead of stuttering on
/// mark and wordmark separately.
///
/// The strip is the BRAND, and it is deliberately not the screen's title: a
/// screen that opens with a logo has spent its first line on the product
/// instead of on the thing the user came to do. Use [ScreenTitle] for that.
class BrandHeader extends StatelessWidget {
  const BrandHeader({
    this.title,
    this.markSize,
    this.gap,
    this.showWordmark = false,
    this.wordmarkFontSize,
    super.key,
  });

  /// The screen title, typically `Text(l10n.xxxTitle)`. Omit for mark-only
  /// strips (wordmark beside mark, no title).
  final Widget? title;

  /// Brand mark size in logical pixels. Null takes the spacing scale's step.
  final double? markSize;

  /// Gap between mark/wordmark and title. Null takes the spacing scale's step.
  final double? gap;

  /// Whether to render the wordmark between the mark and the title.
  final bool showWordmark;

  /// Wordmark font size in logical pixels. Null takes the type scale's step.
  final double? wordmarkFontSize;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final double mark = markSize ?? spacing.xl;
    final double space = gap ?? spacing.md;
    final double wordmark = wordmarkFontSize ?? spacing.xl;

    return Semantics(
      image: true,
      label: SimplePosBrand.appName,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SimplePosMark(size: mark, variant: SimplePosMarkVariant.full),
            SizedBox(width: space),
            if (showWordmark) SimplePosWordmark(fontSize: wordmark),
            if (title != null) title!,
          ],
        ),
      ),
    );
  }
}
