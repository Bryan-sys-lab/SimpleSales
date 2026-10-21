import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_shapes.dart';
import '../../theme/app_spacing.dart';
import '../../theme/typography.dart';

/// "Nothing here yet" and "nothing matches this filter" are DIFFERENT screens.
///
/// They answer different questions and offer different actions: the first invites
/// the user to create something, the second invites them to undo the filter they
/// just applied. Collapsing them into one "No items" view is how a user who
/// filtered to nothing is told they have no products.
enum EmptyKind {
  /// The collection is genuinely empty. Offer the primary action.
  collection,

  /// A filter is active and matched nothing. Offer to clear it.
  filtered,
}

/// The non-happy-path views.
///
/// Every one is a widget class rather than a `buildX()` method, so a screen can
/// pump it in a test and a design change lands in one place.
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    required this.title,
    required this.message,
    this.kind = EmptyKind.collection,
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    super.key,
  });

  final String title;
  final String message;
  final EmptyKind kind;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);

    // A live region: an empty list appearing after a load is an eye-only change,
    // and a screen-reader user mid-task otherwise gets silence where content
    // should be.
    return Semantics(
      liveRegion: true,
      container: true,
      child: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(spacing.xl),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: spacing.readableMaxWidth),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // The glyph differs per KIND, so the two empty states are
                // distinguishable at a glance and not only by their words.
                Icon(
                  kind == EmptyKind.filtered
                      ? Icons.filter_alt_off_outlined
                      : Icons.inbox_outlined,
                  size: 40,
                  color: colors.onSurfaceMuted,
                ),
                SizedBox(height: spacing.md),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: type.titleMedium,
                ),
                SizedBox(height: spacing.sm),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style:
                      type.bodyMedium?.copyWith(color: colors.onSurfaceMuted),
                ),
                if (onAction != null) ...<Widget>[
                  SizedBox(height: spacing.lg),
                  FilledButton(onPressed: onAction, child: Text(actionLabel!)),
                ],
                if (onSecondaryAction != null) ...<Widget>[
                  SizedBox(height: spacing.sm),
                  TextButton(
                    onPressed: onSecondaryAction,
                    child: Text(secondaryActionLabel!),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The error view.
///
/// [message] is already localized and already human. A caller must never pass
/// `e.toString()`: an exception is untranslatable, unactionable, and leaks file
/// paths and ids to whoever is standing at the till. Map a typed failure's stable
/// code to a string at the boundary instead.
class ErrorStateView extends StatelessWidget {
  const ErrorStateView({
    required this.message,
    this.onRetry,
    this.retryLabel = 'Try again',
    this.detail,
    this.icon = Icons.cloud_off_outlined,
    super.key,
  });

  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;

  /// A short technical line, only when there is a support process that needs it.
  /// Never the exception itself.
  final String? detail;

  /// The glyph that says what failed.
  ///
  /// The default is the network's own mark, because that is what this view is
  /// most often about. A screen whose failure is NOT a network passes the
  /// glyph that names ITS failure: an error view that shows a crossed-out
  /// cloud over a camera problem tells the operator to check their wifi.
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);

    return Semantics(
      liveRegion: true,
      container: true,
      child: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(spacing.xl),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: spacing.readableMaxWidth),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  icon,
                  size: 40,
                  color: colors.danger,
                ),
                SizedBox(height: spacing.md),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: type.titleMedium,
                ),
                if (detail != null) ...<Widget>[
                  SizedBox(height: spacing.sm),
                  Text(
                    detail!,
                    textAlign: TextAlign.center,
                    style: type.bodySmall,
                  ),
                ],
                if (onRetry != null) ...<Widget>[
                  SizedBox(height: spacing.lg),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: Text(retryLabel),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A skeleton shaped like the result it stands in for.
///
/// Two rules make this worth having over a `CircularProgressIndicator`:
///
/// 1. **Delayed.** A load that resolves in 80ms should never flash a skeleton.
///    [delay] suppresses it until it is worth showing.
/// 2. **Shaped like the content.** A skeleton of the same rows the real list will
///    use means nothing jumps when the data lands. A centred spinner over an empty
///    box means everything jumps.
///
/// The shimmer itself collapses to a static block under reduced motion — a
/// looping animation with no stop condition is a battery bug, and this one stops
/// when it is off-screen, when the app is backgrounded, and here.
class SkeletonList extends StatefulWidget {
  const SkeletonList({
    this.itemCount = 6,
    this.linesPerItem = 2,
    this.itemBuilder,
    super.key,
  });

  final int itemCount;
  final int linesPerItem;

  /// How long to show nothing at all before the skeleton appears. Reads
  /// `AppMotion.of(context).skeletonDelay` — a behavioural threshold, so it lives
  /// with the rest of the timing rather than as a default a caller must know to
  /// override.

  /// Overrides the default row shape — pass the real item's silhouette when one
  /// screen's rows differ from the rest.
  final Widget Function(BuildContext context, int index)? itemBuilder;

  @override
  State<SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<SkeletonList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    // Reassigned in `didChangeDependencies`, where the theme is first readable.
    duration: AppMotion.standard.skeletonShimmer,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = AppMotion.of(context).skeletonShimmer;
    _armSkeleton(AppMotion.of(context).skeletonDelay);
  }

  /// The key that suppresses the skeleton for the first [delay].
  bool _showSkeleton = false;

  /// The timer that reveals the skeleton once the delay has passed.
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    _showSkeleton = false;
  }

  /// Arms the reveal timer.
  ///
  /// Called from [didChangeDependencies], NOT from `initState`: the delay comes
  /// from the theme, and looking up an inherited widget during the element's
  /// own `initState` is a lookup before that state is alive — the framework
  /// rejects it, and every screen that showed a skeleton crashed in debug
  /// mode. `didChangeDependencies` is where the theme first becomes readable,
  /// and re-arming there means a theme change re-times the reveal.
  ///
  /// A real timer, cancelled on dispose. Leaking it fires into a dead tree.
  void _armSkeleton(Duration delay) {
    _delayTimer?.cancel();
    _delayTimer = Timer(delay, () {
      if (!mounted) return;
      setState(() => _showSkeleton = true);
      _play();
    });
  }

  void _play() {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    _controller.repeat();
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_showSkeleton) return const SizedBox.shrink();

    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);

    return IgnorePointer(
      // A skeleton must never take a tap: a user who taps a loading row and gets
      // nothing has no way to tell the app from a hung one.
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? _) {
          // Under reduced motion the block is simply there, at its resting tone.
          // Not a slower shimmer.
          final double t = reduceMotion ? 0.4 : _controller.value;
          final Color fill = Color.lerp(
            colors.surfaceSunken,
            colors.outline,
            t,
          )!;

          return ListView.builder(
            padding: EdgeInsets.all(spacing.md),
            itemCount: widget.itemCount,
            itemBuilder: (BuildContext context, int index) {
              if (widget.itemBuilder != null) {
                return widget.itemBuilder!(context, index);
              }
              return Padding(
                padding: EdgeInsets.only(bottom: spacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (int line = 0; line < widget.linesPerItem; line++)
                      Container(
                        height: 12,
                        margin: EdgeInsets.only(bottom: spacing.sm),
                        // The last line is shorter, which is what makes a stack
                        // of bars read as text rather than as a barcode.
                        width: line.isEven
                            ? double.infinity
                            : MediaQuery.sizeOf(context).width * 0.6,
                        decoration: BoxDecoration(
                          color: fill,
                          borderRadius: AppShapes.of(context).controlRadius,
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
