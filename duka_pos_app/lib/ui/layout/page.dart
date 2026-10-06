import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import 'window_size_class.dart';

/// A screen's body: full-bleed background, inset content.
///
/// The window is edge-to-edge; the TARGETS are inset. Those are two different
/// questions and conflating them is why an app ends up either with a stripe of
/// canvas under the status bar or with content sliding under the notch.
///
/// [scrollable] false is for a screen whose child owns its scrolling — a tab
/// body, a grid — so this cannot nest two scrollables and produce the
/// unbounded-height error.
class AdaptivePage extends StatelessWidget {
  const AdaptivePage({
    required this.child,
    this.scrollable = false,
    this.padding,
    this.maxContentWidth,
    this.resizeToAvoidBottomInset = true,
    super.key,
  });

  final Widget child;

  /// Wrap the child in a scroll view. Off when the child scrolls itself.
  final bool scrollable;

  final EdgeInsetsGeometry? padding;

  /// Overrides the readable cap. The default caps PROSE; a table or a product
  /// grid is legitimately wider than 680px and should fill the window.
  final double? maxContentWidth;

  /// False for a screen with a fixed grid that must not reflow under the IME.
  final bool resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final double cap = maxContentWidth ?? double.infinity;

    Widget content = Padding(
      padding: padding ?? EdgeInsets.all(spacing.md),
      child: child,
    );

    if (cap.isFinite) {
      content = Center(
        child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: cap), child: content),
      );
    }

    if (scrollable) {
      content = SingleChildScrollView(
        // Never `pumpAndSettle` this in a test: a scroll view settles fine, but
        // wrapping it around a list that never stops loading does not.
        child: content,
      );
    }

    return ColoredBox(
      // Full-bleed behind the system bars.
      color: AppColors.of(context).canvas,
      child: SafeArea(
        bottom: false,
        child: resizeToAvoidBottomInset
            ? content
            : MediaQuery.removeViewInsets(
                context: context,
                removeBottom: true,
                child: content,
              ),
      ),
    );
  }
}

/// A screen that is mostly one scrollable column of mixed content.
///
/// The common case for Settings and Analytics: sections of cards, separated by
/// headers, that must reflow rather than scroll horizontally when the window is
/// narrow.
class SectionedPage extends StatelessWidget {
  const SectionedPage({
    required this.sections,
    this.padding,
    this.maxContentWidth,
    super.key,
  });

  final List<Widget> sections;
  final EdgeInsetsGeometry? padding;
  final double? maxContentWidth;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);

    return AdaptivePage(
      // Prose and forms get the readable cap; a full-width section list on a
      // 1600px monitor is unreadable in a way that looks fine at a glance.
      maxContentWidth: maxContentWidth ?? spacing.readableMaxWidth,
      scrollable: true,
      padding: padding ?? EdgeInsets.all(spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int i = 0; i < sections.length; i++) ...<Widget>[
            if (i > 0) SizedBox(height: spacing.md),
            sections[i],
          ],
        ],
      ),
    );
  }
}

/// Lays out children in a grid whose column count comes from the WINDOW.
///
/// Not a media query, not a device check: the count is computed from the width
/// actually available, so a resized desktop window and a split-screen tablet get
/// the right answer without either of them being a phone-shaped window.
///
/// A minimum column width is a floor on the CELL, not on the window — an
/// assertion that a window is at least N wide fires exactly where a narrow
/// window is already in trouble.
class AdaptiveGrid extends StatelessWidget {
  const AdaptiveGrid({
    required this.itemCount,
    required this.itemBuilder,
    this.minCellWidth = 220,
    this.maxColumns = 4,
    this.spacing,
    this.padding,
    super.key,
  });

  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final double minCellWidth;

  /// Stops a 1600px monitor becoming eight 190px columns of unreadable numbers.
  final int maxColumns;

  final double? spacing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final AppSpacing tokens = AppSpacing.of(context);
    final double gap = spacing ?? tokens.md;
    final EdgeInsetsGeometry inset = padding ?? EdgeInsets.zero;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double available = constraints.maxWidth - inset.horizontal;
        final int columns = columnsFor(
          available: available,
          gap: gap,
          minCellWidth: minCellWidth,
          maxColumns: maxColumns,
        );

        return GridView.builder(
          padding: inset,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          // The cell's height is derived from its width, not fixed: a taller
          // number or a 200% text scale makes a taller cell, and a fixed height
          // clips it.
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: available / columns,
            mainAxisSpacing: gap,
            crossAxisSpacing: gap,
            childAspectRatio: 1.7,
          ),
          itemCount: itemCount,
          itemBuilder: itemBuilder,
        );
      },
    );
  }

  /// The column count, as a pure function so a test can drive it without pumping.
  static int columnsFor({
    required double available,
    required double gap,
    required double minCellWidth,
    required int maxColumns,
  }) {
    if (available <= 0) return 1;
    final int fitting = ((available + gap) / (minCellWidth + gap)).floor();
    return fitting.clamp(1, maxColumns);
  }
}

/// Whether the window can afford two panes.
///
/// Reads the size class rather than a device flag, so a resized desktop window
/// gets the two-pane layout and a foldable's cover display does not.
bool canSplitPanes(BuildContext context) =>
    windowSizeClassOf(context).splitsTwoPanes;
