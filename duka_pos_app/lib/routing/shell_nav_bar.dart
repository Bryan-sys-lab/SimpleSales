// The till's bottom navigation: an OMEGA bar.
//
// ## THE SHAPE
//
// The bar is a PILL — a stadium, rounded at both ends — whose top edge rises
// in the middle into a smooth bell curve, and the SELL button is a big green
// ball sitting ON that curve.
//
// It is a shape rather than a rectangle because the sell button is what a
// cashier presses forty times an hour, and the eye finds a raised circle
// faster than it finds a rectangle. The curve is what ties the circle to the
// bar: the hump is drawn to the circle's own radius, so the bar appears to
// swell up around it rather than to have a button dropped on top.
//
// The remaining destinations divide around it, evenly on each side, so the
// ball is dead in the middle whatever the role.
//
// ## WHY THE HUMP IS A CURVE AND NOT A NOTCH
//
// A notch — a bite taken out of the bar — leaves the ball floating in a hole
// with a gap all the way round, which reads as a separate object dropped on
// top of a rectangle. A hump reads as ONE shape: the bar swelling around the
// action it is centred on.
//
// ## WHY THE BALL IS GREEN
//
// Everything else in the bar is ink: the icons, the labels, the outline. The
// one saturated thing on the screen is the one thing to press. That is the
// whole colour strategy of a till: the accent means "this is the action", and
// there is exactly one.
//
// ## THE MOTION
//
// A press scales the ball to 96% and back, in a hundred and twenty
// milliseconds. That is the only animation here: the ball is tapped
// constantly, and an animation that plays on every press is a delay on every
// press. The selected destination changes colour, which needs no animation to
// be read.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import 'routes.dart';

/// The bar's dimensions.
///
/// The ball is 56dp — bigger than the 44dp floor, because it is the control
/// that is pressed most and the one that has to be found first.
class _NavMetrics {
  const _NavMetrics();

  /// The pill's body: the icons and their labels.
  static const double bodyHeight = 52;

  /// How far the ball's centre sits above the bar's straight top edge.
  ///
  /// The same as the hump's height, because the hump's peak IS the ball's
  /// centre: the curve swells to meet the ball.
  static const double humpHeight = 20;

  /// The ball's diameter. Bigger than the bar's body, so the central action is
  /// the first thing the eye lands on.
  static const double ballSize = 60;

  /// The bar reaches the screen's edges.
  ///
  /// It used to float fourteen pixels in from each side, which put two dark
  /// slivers down both edges of every screen and made the bar read as a
  /// separate object hovering above the phone rather than as the bottom of
  /// the app. The bar is the bottom of the app: its ends are cut square and
  /// they meet the screen's edges.
  static const double sideMargin = 0;

  /// The bar sits ON the bottom edge, with no gap beneath it.
  ///
  /// The ten pixels that used to sit under the bar were a second void, below
  /// the first: the page content ended, then there was a gap, then the bar,
  /// then another gap, then the screen edge. Three bands where there should
  /// be one.
  static const double bottomMargin = 0;

  /// The bar's radius.
  static const double ballRadius = ballSize / 2;

  /// How far the ball rises above the hump's peak.
  static const double overhang = ballRadius - humpHeight;

  /// How far the outermost LABEL sits from the screen's edge.
  ///
  /// The bar's ends are square now, so this is not a cap to clear — it is
  /// simply the margin a word needs so it does not look glued to the edge of
  /// the phone. It used to be half the bar's height, twenty-six pixels, which
  /// was a cap's worth of clearance for a cap that is no longer there.
  static const double endInset = 8;
}

/// The till's bottom navigation.
class ShellNavBar extends StatelessWidget {
  const ShellNavBar({
    required this.destinations,
    required this.selected,
    required this.onSelect,
    super.key,
  });

  /// Every destination this role can reach, in the order the bar shows them.
  ///
  /// The SELL destination is expected to be in the middle; the bar splits the
  /// rest around it.
  final List<AppDestination> destinations;

  final AppDestination selected;
  final ValueChanged<AppDestination> onSelect;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);

    final int sellIndex = destinations.indexOf(AppDestination.sell);
    if (sellIndex < 0) {
      // No sell button: the bar is a plain row. It should not happen — every
      // role can sell — but a bar with a hump and no ball in it is a bar with
      // a mistake in it.
      return _PlainBar(
        destinations: destinations,
        selected: selected,
        onSelect: onSelect,
      );
    }

    final List<AppDestination> left = destinations.sublist(0, sellIndex);
    final List<AppDestination> right = destinations.sublist(sellIndex + 1);

    final double height = _NavMetrics.overhang +
        _NavMetrics.humpHeight +
        _NavMetrics.bodyHeight +
        _NavMetrics.bottomMargin;

    // The ball's centre, measured from the top of the widget: the hump's peak
    // is that far up from the bar's straight top edge.
    final double ballCentre =
        height - (_NavMetrics.bottomMargin + _NavMetrics.bodyHeight);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // The LABELS are chosen by each button, against the width it is
        // actually given — see `_DestinationButton`. The bar used to estimate
        // the room per cell here, and the estimate was about ten pixels
        // generous, which was invisible while the label was ellipsised and
        // became a wrapped second line the moment it was not.

        return SizedBox(
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              // The bar: a pill with a bell hump, floating above the edge.
              Positioned(
                left: _NavMetrics.sideMargin,
                right: _NavMetrics.sideMargin,
                bottom: _NavMetrics.bottomMargin,
                height: _NavMetrics.humpHeight + _NavMetrics.bodyHeight,
                child: CustomPaint(
                  painter: _OmegaBarPainter(
                    surface: colors.surface,
                    hairline: colors.outline,
                    shadow: colors.shadow,
                    bodyHeight: _NavMetrics.bodyHeight,
                    humpHeight: _NavMetrics.humpHeight,
                  ),
                ),
              ),
              // The destinations, on each shoulder of the hump.
              //
              // Inset from the screen's edges by a word's margin — the bar's ends
              // are square now, so there is no cap for the outermost LABEL to
              // clear. They use the width they are given, and the width is the
              // whole screen.
              Positioned(
                left: _NavMetrics.endInset,
                right: _NavMetrics.endInset,
                bottom: _NavMetrics.bottomMargin,
                height: _NavMetrics.bodyHeight,
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: _DestinationRow(
                        destinations: left,
                        l10n: l10n,
                        selected: selected,
                        onSelect: onSelect,
                        type: type,
                        colors: colors,
                        spacing: spacing,
                      ),
                    ),
                    // The hump's width, kept clear.
                    //
                    // The BALL's width, and no more: the ball is what stands above
                    // the bar here, and every extra pixel reserved for it is a
                    // pixel taken off the labels beside it. On a 320dp phone with
                    // four labels and a ball, twelve pixels of air was the
                    // difference between "Reports" fitting and "Reports" being a
                    // word the eye had to reconstruct.
                    SizedBox(width: _NavMetrics.ballSize),
                    Expanded(
                      child: _DestinationRow(
                        destinations: right,
                        l10n: l10n,
                        selected: selected,
                        onSelect: onSelect,
                        type: type,
                        colors: colors,
                        spacing: spacing,
                      ),
                    ),
                  ],
                ),
              ),
              // The ball, sitting on the hump.
              Positioned(
                left: 0,
                right: 0,
                top: ballCentre - _NavMetrics.ballRadius,
                child: Center(
                  child: _SellBall(
                    selected: selected == AppDestination.sell,
                    onTap: () => onSelect(AppDestination.sell),
                    l10n: l10n,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The width of a word, measured once and remembered.
///
/// Measuring means laying the text out, and the bar is rebuilt on every
/// navigation. The width of a word does not change, so it is measured once and
/// kept — keyed by the text, the size, the weight and the direction, because a
/// word in a different language is a different word.
final Map<String, double> _labelWidths = <String, double>{};

double _measure(String text, TextStyle style, TextDirection direction) {
  final String key = '$text|${style.fontSize}|${style.fontWeight}|$direction';
  final double? cached = _labelWidths[key];
  if (cached != null) return cached;

  final TextPainter painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: direction,
    maxLines: 1,
  )..layout();
  final double width = painter.width;
  painter.dispose();
  _labelWidths[key] = width;
  return width;
}

/// The bar itself: a pill whose top edge swells into a bell curve.
class _OmegaBarPainter extends CustomPainter {
  const _OmegaBarPainter({
    required this.surface,
    required this.hairline,
    required this.shadow,
    required this.bodyHeight,
    required this.humpHeight,
  });

  final Color surface;
  final Color hairline;
  final Color shadow;

  /// The height of the pill's straight part.
  final double bodyHeight;

  /// How far the hump rises above it.
  final double humpHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final double top = humpHeight;
    final double bottom = humpHeight + bodyHeight;
    final double centreX = size.width / 2;

    // The width of the hump.
    //
    // Just wider than the ball, so the curve rises steeply out of the bar's
    // straight edge and swells to meet the ball's sides. A wider hump is a
    // long shallow ramp, and the ball then reads as a button dropped on a
    // slope rather than as the thing the bar is built around.
    final double sigma = _NavMetrics.ballRadius * 1.25;

    // The bar is cut SQUARE at both ends.
    //
    // It used to end in a semicircle the height of the bar, which is what a
    // floating pill does — but this bar is not floating, it is the bottom of
    // the app, and a rounded end leaves a dark crescent down each edge of
    // every screen. The ends now meet the screen edges cleanly.
    //
    // The top edge is sampled ONCE, into a list of points, because two paths
    // need it: the filled shape and the stroked outline. Sampling it twice
    // would let the two drift apart by a hair, and the outline would stop
    // matching the shape it is supposed to trace.
    final List<Offset> topEdge = <Offset>[];
    const int steps = 96;
    for (int i = 0; i <= steps; i++) {
      final double x = (i / steps) * size.width;
      final double dx = (x - centreX) / sigma;
      final double y = top - humpHeight * math.exp(-0.5 * dx * dx);
      topEdge.add(Offset(x, y));
    }

    final Path path = Path()..moveTo(topEdge.first.dx, topEdge.first.dy);
    for (final Offset point in topEdge.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }

    // The right edge, the bottom edge, and the left edge — all square.
    path
      ..lineTo(size.width, bottom)
      ..lineTo(0, bottom)
      ..close();

    // The bar floats, so it casts a shadow.
    canvas.drawShadow(path, shadow, 8, false);
    canvas.drawPath(path, Paint()..color = surface);

    // A hairline along the edge — but NOT along the bottom.
    //
    // The outline is a separate OPEN path: up the left edge, over the hump,
    // down the right edge, and stopped there. The bottom edge is left
    // unstroked on purpose. The bar is the bottom of the app, so a line across
    // its foot drew a boundary between the app and the screen — the last thing
    // left of the floating object the bar used to be. Without it the bar and
    // the screen behind it read as one surface, and only the hump and the two
    // shoulders still say where the bar ends.
    final Path outline = Path()..moveTo(0, bottom);
    outline.lineTo(0, topEdge.first.dy);
    for (final Offset point in topEdge) {
      outline.lineTo(point.dx, point.dy);
    }
    outline
      ..lineTo(size.width, topEdge.last.dy)
      ..lineTo(size.width, bottom);

    canvas.drawPath(
      outline,
      Paint()
        ..color = hairline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _OmegaBarPainter old) =>
      old.surface != surface ||
      old.hairline != hairline ||
      old.shadow != shadow ||
      old.bodyHeight != bodyHeight ||
      old.humpHeight != humpHeight;
}

/// The destinations on one shoulder.
class _DestinationRow extends StatelessWidget {
  const _DestinationRow({
    required this.destinations,
    required this.l10n,
    required this.selected,
    required this.onSelect,
    required this.type,
    required this.colors,
    required this.spacing,
  });

  final List<AppDestination> destinations;

  /// The strings, for the labels each destination shows.
  final AppLocalizations l10n;

  final AppDestination selected;
  final ValueChanged<AppDestination> onSelect;
  final TextTheme type;
  final AppColors colors;
  final AppSpacing spacing;

  @override
  Widget build(BuildContext context) {
    if (destinations.isEmpty) return const SizedBox.shrink();
    return Row(
      children: <Widget>[
        for (final AppDestination destination in destinations)
          Expanded(
            child: _DestinationButton(
              destination: destination,
              l10n: l10n,
              selected: destination == selected,
              onTap: () => onSelect(destination),
              type: type,
              colors: colors,
              spacing: spacing,
            ),
          ),
      ],
    );
  }
}

/// One destination: an icon and its label.
class _DestinationButton extends StatelessWidget {
  const _DestinationButton({
    required this.destination,
    required this.l10n,
    required this.selected,
    required this.onTap,
    required this.type,
    required this.colors,
    required this.spacing,
  });

  final AppDestination destination;
  final AppLocalizations l10n;
  final bool selected;
  final VoidCallback onTap;
  final TextTheme type;
  final AppColors colors;
  final AppSpacing spacing;

  @override
  Widget build(BuildContext context) {
    // The selection is COLOUR, and nothing else.
    //
    // The bar has one saturated thing on it — the sell ball — and a second
    // pill behind the selected item would compete with it. A green icon and a
    // green label say "you are here" without adding a shape to read.
    final Color ink = selected ? colors.accent : colors.onSurfaceMuted;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // THE LABEL IS CHOSEN AGAINST THE WIDTH THIS BUTTON WAS GIVEN.
        //
        // "Dashboard" is nine characters and the cell beside a 60dp ball on a
        // 360dp phone is not nine characters wide. The bar used to ESTIMATE
        // the room per cell and pick from the estimate, and the estimate ran
        // about ten pixels generous — which nobody could see while the label
        // was ellipsised, and became a wrapped second line the moment the
        // ellipsis came off. A widget that knows its own width does not have
        // to guess.
        //
        // The full word when it fits; the short one when it does not. A
        // shorter word that is COMPLETE beats a longer one that is cut.
        final String full = destination.label(l10n);
        final String shown = _fits(context, full, constraints.maxWidth)
            ? full
            : destination.shortLabel(l10n);

        return Semantics(
          button: true,
          selected: selected,
          // The FULL name, always: the short form is a visual compromise for
          // a narrow cell, and a screen-reader user has no such problem.
          label: full,
          excludeSemantics: true,
          child: InkWell(
            onTap: onTap,
            borderRadius: AppShapes.of(context).controlRadius,
            child: Padding(
              // The group sits HIGH in the bar's body, with the space below the
              // label: the icon and its word read as one pair, and the bar's
              // curve has room to close under them.
              padding: const EdgeInsets.only(top: 7),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.start,
                children: <Widget>[
                  Icon(destination.icon, size: 21, color: ink),
                  SizedBox(height: spacing.xs),
                  Text(
                    shown,
                    textAlign: TextAlign.center,
                    // ONE line, and never a second one: a label that wrapped
                    // pushed the icon up out of the bar's body. `softWrap:
                    // false` keeps it on one line rather than letting it break
                    // the bar's shape, and the short form above has already
                    // made sure it fits.
                    maxLines: 1,
                    softWrap: false,
                    style: type.labelSmall?.copyWith(
                      color: ink,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Whether [text] fits in [width], at the weight this label is drawn at.
  ///
  /// The selected item is drawn at w700 and the unselected at w500. Measuring
  /// the unselected label at the selected weight would throw away a full
  /// label that would have fitted perfectly well — "Inventory" on a 320dp
  /// phone is 51px in the cell and 53px bold, and the cell is neither.
  bool _fits(BuildContext context, String text, double width) {
    final TextStyle style = type.labelSmall ?? const TextStyle();
    final TextDirection direction = Directionality.of(context);
    final double measured = _measure(
      text,
      style.copyWith(
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
      direction,
    );
    return measured <= width;
  }
}

/// The sell button: the green ball on the hump.
class _SellBall extends StatefulWidget {
  const _SellBall({
    required this.selected,
    required this.onTap,
    required this.l10n,
  });

  final bool selected;
  final VoidCallback onTap;
  final AppLocalizations l10n;

  @override
  State<_SellBall> createState() => _SellBallState();
}

class _SellBallState extends State<_SellBall>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;

  /// One heartbeat: a short, FINITE animation.
  ///
  /// The curve inside it is the "lub-dub" — a big beat, a pause, a smaller
  /// one — which is what a resting heart actually does. Copying that is what
  /// makes the button read as ALIVE rather than as a lamp on a timer. A
  /// single even pulse reads as a notification badge; two uneven beats read
  /// as a pulse.
  ///
  /// The animation is finite on purpose. A controller that repeats forever
  /// schedules a frame every tick, which means the app never has an idle
  /// frame — and a till that never goes idle is a till that never stops
  /// burning battery. A TIMER starts each beat and lets the app go quiet in
  /// between, which is also what lets a test settle.
  late final AnimationController _beat;

  Timer? _beatTimer;

  /// How long one beat lasts.
  static const Duration _beatDuration = Duration(milliseconds: 460);

  /// How long between beats.
  static const Duration _beatPeriod = Duration(milliseconds: 2400);

  @override
  void initState() {
    super.initState();
    _beat = AnimationController(vsync: this, duration: _beatDuration);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _armBeat();
  }

  /// Starts the next beat, and keeps starting them.
  ///
  /// Re-armed whenever the dependencies change, because the reduced-motion
  /// flag is one of them: a person who asked the OS to stop animations gets
  /// a still button, not a faster pulse.
  void _armBeat() {
    _beatTimer?.cancel();
    if (MediaQuery.disableAnimationsOf(context)) {
      _beat.value = 0;
      return;
    }
    _beatTimer = Timer(_beatPeriod, () {
      if (!mounted) return;
      _beat.forward(from: 0).whenComplete(() {
        if (mounted) _armBeat();
      });
    });
  }

  @override
  void dispose() {
    _beatTimer?.cancel();
    _beat.dispose();
    super.dispose();
  }

  /// The glow's strength, 0 at rest and 1 at the top of a beat.
  ///
  /// Read from [MediaQuery] rather than from a provider: the flag comes from
  /// the platform, and the platform state is already reactive.
  double _pulse(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return 0;
    final double t = _beat.value;
    // lub: a sharp rise and a slower fall, over the first part of the beat.
    // dub: a smaller one, a little later.
    // rest: flat, which is most of the period.
    if (t <= 0) return 0;
    if (t < 0.26) return t / 0.26;
    if (t < 0.60) return 1 - (t - 0.26) / 0.34;
    if (t < 0.78) return 0.6 * (t - 0.60) / 0.18;
    if (t < 1) return 0.6 * (1 - (t - 0.78) / 0.22);
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppMotion motion = AppMotion.of(context);
    final String label = AppDestination.sell.label(widget.l10n);

    return Semantics(
      button: true,
      selected: widget.selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          // Ninety-six percent, for the shortest beat the motion scale has.
          //
          // The ball is pressed forty times an hour, so this is the shortest
          // feedback in the app: enough to feel the touch land, short enough
          // never to be waited for. It collapses to nothing under reduced
          // motion, where the state change is still there — it just does not
          // travel.
          scale: _pressed ? 0.96 : 1.0,
          duration: AppMotion.resolve(context, motion.instant),
          curve: AppMotion.resolveCurve(context, motion.enter),
          child: AnimatedBuilder(
            animation: _beat,
            builder: (BuildContext context, Widget? child) {
              final double pulse = _pulse(context);
              return Container(
                width: _NavMetrics.ballSize,
                height: _NavMetrics.ballSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // SOLID accent, not a gradient. The one saturated thing on the
                  // screen is one colour, and a second green in the same ball
                  // reads as a printing error rather than as light.
                  color: colors.accent,
                  // The glow: the ball is LIT, and the light spills onto the
                  // bar. It breathes with the heartbeat — brightest at the top
                  // of a beat, settling back between them.
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: colors.accent.withValues(
                        alpha: 0.26 + 0.30 * pulse,
                      ),
                      blurRadius: 14 + 14 * pulse,
                      offset: Offset(0, 5 + 2 * pulse),
                    ),
                  ],
                ),
                // A GLYPH, and not an image.
                //
                // The sell destination used to carry a promotional tile — a dark
                // card with "NEW SALE" written on it — and at the size of a nav
                // icon that is unreadable mush, and inside a circle it would be
                // a square inside a circle. The other items are outline
                // glyphs, and so is this one: one language across the bar.
                child: child,
              );
            },
            child: Icon(
              AppDestination.sell.icon,
              size: 26,
              color: colors.onAccent,
            ),
          ),
        ),
      ),
    );
  }
}

/// The bar for a role with no sell button.
///
/// It should not happen — every role can sell — but a bar with a hump and no
/// ball in it is a bar with a mistake in it, and a plain row is the honest
/// answer.
class _PlainBar extends StatelessWidget {
  const _PlainBar({
    required this.destinations,
    required this.selected,
    required this.onSelect,
  });

  final List<AppDestination> destinations;
  final AppDestination selected;
  final ValueChanged<AppDestination> onSelect;

  @override
  Widget build(BuildContext context) => NavigationBar(
        selectedIndex: destinations.contains(selected)
            ? destinations.indexOf(selected)
            : 0,
        onDestinationSelected: (int i) => onSelect(destinations[i]),
        destinations: <Widget>[
          for (final AppDestination destination in destinations)
            NavigationDestination(
              icon: Icon(destination.icon),
              label: destination.label(AppLocalizations.of(context)),
            ),
        ],
      );
}
