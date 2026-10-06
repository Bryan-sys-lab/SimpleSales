import 'package:flutter/widgets.dart';

/// The Material 3 window size classes, as one shared vocabulary.
///
/// These are structural breakpoints, not design tokens — which is exactly why
/// they belong in one file rather than as a `bool isTablet` flag threaded through
/// twenty screens. Every screen that adapts reads this enum, so every screen
/// breaks at the same widths.
///
/// Branches on CONSTRAINTS, never on the device: a resized desktop window, a
/// split-screen tablet and a foldable's outer display all report their real
/// size, and none of them is `Platform.isTablet`.
enum WindowSizeClass {
  /// Phone in either orientation. One pane; a bottom navigation bar.
  compact,

  /// Small tablet, phone in landscape-plus. A navigation rail, collapsed.
  medium,

  /// Tablet, unfolded foldable. A navigation rail, extended; list-detail splits.
  expanded,

  /// Desktop window. An extended rail; master-detail with real columns.
  large,

  /// Wide desktop. A navigation drawer, and the measure cap matters.
  extraLarge;

  bool get isCompact => this == WindowSizeClass.compact;

  /// Whether a list and its detail can sit side by side. Two panes on a 360dp
  /// phone are unreadable; one pane on a desktop wastes most of the width.
  bool get splitsTwoPanes => index >= WindowSizeClass.expanded.index;

  /// Whether the navigation affordance is a bottom bar rather than a rail.
  bool get usesBottomBar => this == WindowSizeClass.compact;
}

WindowSizeClass windowSizeClassFor(double width) => switch (width) {
      < 600 => WindowSizeClass.compact,
      < 840 => WindowSizeClass.medium,
      < 1200 => WindowSizeClass.expanded,
      < 1600 => WindowSizeClass.large,
      _ => WindowSizeClass.extraLarge,
    };

/// The size class for the whole window.
///
/// Prefers [MediaQuery.sizeOf] over `MediaQuery.of`: the aspect getter rebuilds
/// only when the window SIZE changes, where `.of` subscribes the widget to every
/// MediaQuery change — keyboard, rotation, text scale.
WindowSizeClass windowSizeClassOf(BuildContext context) =>
    windowSizeClassFor(MediaQuery.sizeOf(context).width);
