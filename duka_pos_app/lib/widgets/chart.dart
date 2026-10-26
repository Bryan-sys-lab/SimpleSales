import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
// ---------------------------------------------------------------------------
// Time series
// ---------------------------------------------------------------------------

/// One point in a series over time.
///
/// This app's chart widgets carry no shape: a caller reading one cannot tell
/// whether it will be drawn as a line, a ring, or anything else.
@immutable
class PosLinePoint {
  const PosLinePoint({
    required this.label,
    required this.value,
    this.valueLabel,
  });

  /// The moment — an hour, a date.
  final String label;

  final int value;

  /// Pre-formatted figure. Falls back to the raw value.
  final String? valueLabel;

  String get displayValue => valueLabel ?? '$value';
}

/// A smooth path through [points].
///
/// MONOTONE cubic interpolation — the Fritsch–Carlson construction — and not a
/// Catmull-Rom spline. A Catmull-Rom spline through noisy readings invents a
/// peak between two points and swings past the ends of the data: a chart of a
/// shop's takings that invents a peak is not smoothing the data, it is
/// misreporting it.
///
/// Monotone interpolation passes through EVERY reading and never leaves the
/// range of the data. The shape gets softer; the values do not move.
///
/// The construction: the secants give the local slope, each tangent is the
/// weighted harmonic mean of the two secants around its point, and a point
/// whose secants disagree in sign — a local maximum or a local minimum — gets
/// a tangent of zero, so the curve flattens there instead of swinging past it.
Path smoothPathThrough(List<Offset> points) {
  final Path path = Path();
  if (points.isEmpty) return path;
  path.moveTo(points.first.dx, points.first.dy);
  if (points.length == 1) return path;
  if (points.length == 2) {
    path.lineTo(points[1].dx, points[1].dy);
    return path;
  }

  final int n = points.length;
  final List<double> spans = <double>[];
  final List<double> secants = <double>[];
  for (int i = 0; i < n - 1; i++) {
    final double h = points[i + 1].dx - points[i].dx;
    spans.add(h);
    secants.add(h == 0 ? 0 : (points[i + 1].dy - points[i].dy) / h);
  }

  final List<double> tangent = List<double>.filled(n, 0);
  tangent[0] = secants.first;
  tangent[n - 1] = secants.last;
  for (int i = 1; i < n - 1; i++) {
    if (secants[i - 1] * secants[i] <= 0) {
      // A local extremum. No tangent, so no overshoot past the peak.
      tangent[i] = 0;
    } else {
      final double w1 = 2 * spans[i] + spans[i - 1];
      final double w2 = spans[i] + 2 * spans[i - 1];
      tangent[i] = (w1 + w2) / (w1 / secants[i - 1] + w2 / secants[i]);
    }
  }

  for (int i = 0; i < n - 1; i++) {
    final double h = spans[i];
    path.cubicTo(
      points[i].dx + h / 3,
      points[i].dy + tangent[i] * h / 3,
      points[i + 1].dx - h / 3,
      points[i + 1].dy - tangent[i + 1] * h / 3,
      points[i + 1].dx,
      points[i + 1].dy,
    );
  }
  return path;
}

/// A line chart, for a series the eye reads as a SEQUENCE.
///
/// The line is SMOOTH — a monotone cubic through the readings, so the shape of
/// the day is drawn as one gesture rather than as a row of corners, and no
/// reading is invented between two points.
///
/// The axis reads at an INTERVAL, not one label per reading: a trading day is
/// twenty-four hours, and twenty-four labels across a 320dp phone is a row of
/// collisions rather than an axis. The interval is a floor, and a narrower
/// phone or a wider label widens it further.
///
/// The bar chart this replaces was the wrong instrument: twelve vertical bars
/// for twelve hours asks the reader to compare twelve heights to find a shape,
/// when a line already draws the shape. A line is what "the day rose, peaked at
/// six, and fell" looks like without being described in words.
///
/// Same accessibility contract as [PosPieChart] — a painted canvas has no
/// text nodes, so the whole series is restated as a sentence on a [Semantics]
/// node and the painted content is excluded from it — and the same rules on
/// text scaling: nothing shrinks, axis labels are dropped rather than squeezed,
/// and the painter is free to paint outside its box because there is no layout
/// to overflow.
class PosLineChart extends StatefulWidget {
  const PosLineChart({
    super.key,
    required this.title,
    required this.points,
    this.semanticsLabel,
    this.height = 148,
    this.emphasis,
    this.minStride = 1,
    this.showTitle = true,
  });

  final String title;
  final List<PosLinePoint> points;
  final String? semanticsLabel;

  /// Plot height. The axis strip is added on top of it.
  final double height;

  final String? emphasis;

  /// Whether to render the title above the plot.
  ///
  /// False when the panel the chart sits in already says what the chart is —
  /// an empty title still renders a heading, in the heading style, and leaves
  /// a line of nothing where a line of something should be.
  final bool showTitle;

  /// The smallest gap, in readings, between two axis labels.
  ///
  /// One is "label every reading", and on a phone that is a row of
  /// collisions. Three reads as morning, midday, evening — the interval a
  /// trading day is actually read at — and it is a FLOOR: a wider label or a
  /// narrower phone widens the stride further, so the axis can never become a
  /// wall of text.
  final int minStride;

  @override
  State<PosLineChart> createState() => _PosLineChartState();
}

class _PosLineChartState extends State<PosLineChart> {
  /// The reading the finger revealed, or null for none.
  ///
  /// State rather than nothing: this is the one piece of the chart that a tap
  /// creates, and it belongs to the chart.
  int? _selected;

  /// Label measurements, owned HERE so they outlive the painter.
  ///
  /// A painter is built on every `build()`, so widths cached inside one are
  /// always cold — and a fresh [_ChartLabels] per build makes the painter's
  /// `shouldRepaint` compare by identity and answer `true` forever after, so
  /// every parent rebuild repaints a chart that has not changed. Holding the
  /// helper here fixes both: it is reused across builds and its measurements
  /// survive them.
  final Map<String, double> _labelWidths = <String, double>{};
  _ChartLabels? _labels;

  /// The shared label helper for the style this state is building with.
  _ChartLabels _labelsFor(TextStyle style) {
    final direction = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final existing = _labels;
    if (existing != null &&
        existing.labelStyle == style &&
        existing.direction == direction &&
        existing.textScaler == scaler) {
      return existing;
    }
    // A different type scale or direction invalidates every measurement, not
    // just the ones this dataset uses.
    _labelWidths.clear();
    return _labels = _ChartLabels(
      labelStyle: style,
      direction: direction,
      textScaler: scaler,
      widths: _labelWidths,
    );
  }

  /// The spoken sentence when the caller passed no label: the title, the count
  /// and the peak — a painted canvas has no text nodes, so without this the
  /// chart is silent to a screen reader.
  String _fallbackSemantics(AppLocalizations l10n) {
    if (widget.points.isEmpty) return l10n.chartSpokenNoValues(widget.title);
    final peak = widget.points
        .reduce((PosLinePoint a, PosLinePoint b) => b.value > a.value ? b : a);
    return l10n.chartSpokenPeak(
        widget.points.length, peak.label, widget.title, peak.displayValue);
  }

  @override
  void didUpdateWidget(covariant PosLineChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A fresh series makes the previous selection meaningless: the reading the
    // owner tapped is a different hour's money now.
    if (!identical(oldWidget.points, widget.points) &&
        oldWidget.points != widget.points) {
      _selected = null;
      _labelWidths.clear();
    }
  }

  /// Selects the reading nearest [localX].
  ///
  /// [toggle] is false for a drag: sliding a finger along the chart MOVES the
  /// selection, and it does not clear it when the finger passes over the
  /// reading that is already selected — which is what a tap does.
  void _selectAt(double localX, double width, {bool toggle = true}) {
    final List<PosLinePoint> points = widget.points;
    if (points.isEmpty || width <= 0) return;
    // The readings sit on a line, not in slots: the first is at one edge and
    // the last at the other, with the step between them.
    final double step = points.length > 1 ? width / (points.length - 1) : width;
    // Mirrored in RTL, because the painter mirrors the series: without this, a
    // tap on the right of the chart picks the reading at the OTHER end.
    final double fromStart = Directionality.of(context) == TextDirection.rtl
        ? width - localX
        : localX;
    final int index = (fromStart / step).round().clamp(0, points.length - 1);
    if (!toggle) {
      if (_selected == index) return;
      setState(() => _selected = index);
      return;
    }
    setState(() => _selected = _selected == index ? null : index);
  }

  void _selectRelative(int direction) {
    if (widget.points.isEmpty) return;
    final int current =
        _selected ?? (direction > 0 ? -1 : widget.points.length);
    final int next = (current + direction).clamp(0, widget.points.length - 1);
    if (_selected == next) return;
    setState(() => _selected = next);
  }

  /// What a screen reader says for this chart right now.
  ///
  /// The caller's description when it gave one, the series summary otherwise,
  /// and the tapped reading's figure APPENDED while one is tapped — so the
  /// announcement always carries the fact the finger just produced.
  String _announcement(AppLocalizations l10n) {
    final String base = widget.semanticsLabel ?? _fallbackSemantics(l10n);
    final int? at = _selected;
    if (at == null || at >= widget.points.length) return base;
    final PosLinePoint point = widget.points[at];
    if (point.value <= 0) return base;
    return '$base. ${l10n.chartSpokenSelected(point.label, widget.title, point.displayValue)}';
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);
    final labelStyle = type.bodySmall ?? const TextStyle();
    final l10n = AppLocalizations.of(context);

    return Semantics(
      label: _announcement(l10n),
      container: true,
      onIncrease: () => _selectRelative(1),
      onDecrease: () => _selectRelative(-1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (widget.showTitle) ...[
            Text(widget.title, style: type.titleMedium),
            SizedBox(height: spacing.sm),
          ],
          if (widget.emphasis != null) ...[
            const SizedBox(height: 2),
            Text(widget.emphasis!, style: labelStyle),
          ],
          SizedBox(height: spacing.sm),
          if (widget.points.isEmpty)
            Text(l10n.chartNothingToShow, style: labelStyle)
          else
            // The width the readings are cut from is the CANVAS's width, so the
            // selection is computed from the width the painter used and not
            // from the width of whatever contains the chart.
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final double width = constraints.maxWidth.isFinite
                    ? constraints.maxWidth
                    : constraints.biggest.width;
                final painter = _LineChartPainter(
                  points: widget.points,
                  plotHeight: widget.height,
                  selected: _selected,
                  accent: colors.accent,
                  grid: colors.outline,
                  gap: spacing.sm,
                  labels: _labelsFor(labelStyle),
                  minStride: widget.minStride,
                );
                return SizedBox(
                  width: width,
                  height: painter.totalHeight(widget.height),
                  child: GestureDetector(
                    // The whole plot is the target, not one reading: a finger
                    // between two readings still selects the nearer one, and a
                    // shop working through a queue should not have to aim.
                    onTapUp: (TapUpDetails details) =>
                        _selectAt(details.localPosition.dx, width),
                    // A DRAG selects too: on a phone each reading is a few
                    // pixels wide, and a finger can slide along the chart with
                    // the selection following it.
                    onHorizontalDragUpdate: (DragUpdateDetails details) =>
                        _selectAt(details.localPosition.dx, width,
                            toggle: false),
                    // The gesture layer is not a reading; the series is.
                    excludeFromSemantics: true,
                    behavior: HitTestBehavior.opaque,
                    child:
                        ExcludeSemantics(child: CustomPaint(painter: painter)),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// The vertical budget of a chart: the axis strip, the headroom, the plot.
///
/// WHY THE HEADROOM EXISTS
///
/// The plot used to run to the very top of the canvas, so the tallest point
/// and the figure above it were drawn on the same pixels — and the figure's y
/// was clamped to zero, which pinned it ON the point. The number and the dot
/// it described, in the same place.
///
/// So the plot is shorter than the canvas by one label's height, and the
/// baseline stays exactly where it was. The figure then lands a couple of
/// pixels below the top edge.
///
/// Public because the invariant is the whole point, and a painted canvas is
/// not something a test can measure. A test can measure this.
@immutable
class ChartBudget {
  const ChartBudget({
    required this.height,
    required this.axisHeight,
    required this.headroom,
    required this.plotHeight,
    required this.baseline,
  });

  /// The whole canvas.
  final double height;

  /// The strip under the plot that carries the axis labels.
  final double axisHeight;

  /// The room a figure needs above the tallest point.
  final double headroom;

  /// The room the data itself gets.
  final double plotHeight;

  /// Where the data sits on the canvas. Unchanged by the headroom: the shape
  /// still stands on the same floor.
  final double baseline;

  /// The budget for a canvas of [height] with an [axisHeight] strip and
  /// figures of [labelHeight].
  factory ChartBudget.of({
    required double height,
    required double axisHeight,
    required double labelHeight,
  }) {
    final double headroom = labelHeight + 6;
    final double baseline = height - axisHeight;
    return ChartBudget(
      height: height,
      axisHeight: axisHeight,
      headroom: headroom,
      plotHeight: math.max(0, baseline - headroom),
      baseline: baseline,
    );
  }

  /// Where a figure of [figureHeight] sits above the point it belongs to.
  ///
  /// [pointTop] is the top of the point — the top of the plot for the tallest
  /// one. The answer is never negative: a figure that would be clamped to the
  /// top of the canvas is a figure drawn on the data.
  double figureTop(double pointTop, double figureHeight, {double gap = 4}) =>
      pointTop - figureHeight - gap;
}

/// The horizontal rules a chart draws under its data.
///
/// The zero baseline and the mid gridline. A line chart with neither is a
/// shape with nothing under it: two readings can be compared by eye but not
/// read, and "did it really double" has no answer.
///
/// Public because the rule is the point, and a painted line is not something a
/// test can see.
List<double> gridLinesFor(ChartBudget budget) => <double>[
      budget.baseline,
      budget.baseline - budget.plotHeight / 2,
    ];

/// ONE place both charts measure their labels.
///
/// A `CustomPainter` is built on every `build()` of the chart — the bar chart's
/// once sat inside a `LayoutBuilder` builder — so a width cache the painter
/// owns is always empty by the time `paint()` runs: it re-measured all
/// twenty-four hour labels per repaint, on every tap. The width map is
/// therefore injected by whoever wants measurements to outlive a painter, and
/// the widths themselves are measured once. What `paint()` still does per frame
/// is lay out the labels it draws — that is one short string each, and the
/// framework's own text engine spends the same to render a `Text` widget; what
/// it used to do was the WIDEST-label scan of the whole series, every frame,
/// and that is what this removes.
///
/// It is also where the axis rules live — the strip height, the label stride
/// and its collision factor, pixel snapping — instead of being duplicated in
/// each painter and drifting into two different stride factors.
class _ChartLabels {
  _ChartLabels({
    required this.labelStyle,
    required this.direction,
    required this.textScaler,
    Map<String, double>? widths,
  }) : widths = widths ?? <String, double>{};

  final TextStyle labelStyle;
  final TextDirection direction;
  final TextScaler textScaler;

  /// Label widths, in logical pixels, measured once each.
  ///
  /// Owned by the caller when it outlives a painter instance; owned here
  /// (fresh) otherwise. The class speaks for a "map of per-label widths" either
  /// way, so a measurement can never be redone per frame.
  final Map<String, double> widths;

  double? _lineHeightValue;

  /// Below this, the plot is too short to be worth an axis and the labels are
  /// dropped rather than drawn into the plot.
  static const double minPlotWithAxis = 44.0;

  /// The room one label wants beyond its own width before the next slot is
  /// spoken for.
  static const double collisionFactor = 1.6;

  bool get isRtl => direction == TextDirection.rtl;

  /// The granularity at which caps are remembered, in logical pixels.
  ///
  /// The cap comes from the slot width, which changes by a fraction on every
  /// `LayoutBuilder` constraint — a rotation, a foldable unfolding, a
  /// split-screen drag — and embedding the raw float in the key would file a
  /// fresh entry per constraint change in a map the state never prunes. Half a
  /// pixel is finer than anything the stride decision can hear, so nearby caps
  /// share one entry.
  static const double _capQuantum = 0.5;

  /// A laid-out label, measured into [widths] the first time and free after.
  ///
  /// The key carries the quantised [cap]: a capped layout ellipsizes and stops
  /// at the cap, so a width measured for the stride decision must never be
  /// handed to a paint that needs the label's full width, or the other way
  /// round.
  double widthOf(String label, {double? cap}) {
    final quantum =
        cap == null ? null : (cap / _capQuantum).round() * _capQuantum;
    final key = quantum == null ? label : '$label\u0000$quantum';
    final cached = widths[key];
    if (cached != null) return cached;
    final painter = painterFor(label, cap: cap);
    widths[key] = painter.width;
    return painter.width;
  }

  /// A laid-out label, for the caller to paint.
  ///
  /// The painter is deliberately not cached: `TextPainter` holds its layout and
  /// is cheap to rebuild from a string, while a cached instance would have to
  /// be disposed when the style, scaler or direction changes — the one thing the
  /// width map above does not have to track. The WIDTH is the part that
  /// repeats; `paint()`'s own painter is one short string per frame, which is
  /// what the framework's own text engine spends on a `Text` widget.
  TextPainter painterFor(String label, {double? cap}) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: labelStyle),
      textDirection: direction,
      textScaler: textScaler,
      maxLines: 1,
      ellipsis: '…',
    );
    painter.layout(maxWidth: cap ?? double.infinity);
    return painter;
  }

  /// One line of label-size text, measured once per helper instance.
  double lineHeight() => _lineHeightValue ??= painterFor('Ag').height;

  /// The widest label, capped at [cap] so a label wider than its slot does not
  /// set the stride.
  double widest(Iterable<PosLinePoint> points, double cap) {
    var widest = 0.0;
    for (final point in points) {
      widest = math.max(widest, widthOf(point.label, cap: cap));
    }
    return widest;
  }

  /// The axis strip height, if there is room for one. Zero drops the axis.
  double axisHeight(double height, double gap) {
    final label = lineHeight();
    if (height - label - gap < minPlotWithAxis) return 0;
    return label + gap;
  }

  /// Every Nth label the axis draws.
  ///
  /// One rule with two callers, instead of the same arithmetic written twice
  /// and tuned apart: [minStride] is the floor the chart reads at and
  /// [collisionFactor] is the extra room one label asks of its slot. A stride
  /// of 1 with no factor at all would still collide, because the factor is the
  /// safety margin the axis needs to be readable rather than merely drawn.
  int stride({
    required double slot,
    required Iterable<PosLinePoint> points,
    required int minStride,
  }) {
    final widestLabel = widest(points, math.max(slot, 12.0));
    final needed = (widestLabel * collisionFactor / math.max(slot, 1)).ceil();
    return math.max(minStride, needed).clamp(1, points.length);
  }

  /// Pixel-snapped x for a label of [width] centred on [centerX].
  ///
  /// `TextPainter.paint` renders glyphs at exactly the offset it is given: a
  /// fractional origin straddles two device pixels and anti-aliases the label
  /// into softness, so both painters snap here rather than each carrying its
  /// own copy of the rounding.
  double snapCenter(double centerX, double width, double sizeWidth) =>
      (centerX - width / 2)
          .clamp(0.0, math.max(0.0, sizeWidth - width))
          .roundToDouble();
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({
    required this.points,
    required this.plotHeight,
    required this.selected,
    required this.accent,
    required this.grid,
    required this.gap,
    required this.labels,
    required this.minStride,
  });

  final List<PosLinePoint> points;
  final double plotHeight;

  /// The reading the finger revealed, or null for none.
  final int? selected;

  final Color accent;

  /// The colour of the baseline and the gridlines.
  final Color grid;
  final double gap;

  /// Shared label measurement and axis rules — see [_ChartLabels]. It carries
  /// the style, direction and scaler this painter paints with, so a change of
  /// any of them changes the helper and with it [shouldRepaint]'s answer.
  final _ChartLabels labels;

  /// The smallest gap, in readings, between two axis labels.
  final int minStride;

  bool get _isRtl => labels.isRtl;

  int get _maxValue => points.fold(0, (m, p) => math.max(m, p.value));

  /// The axis strip, if there is room for one.
  double _axisHeight(double height) => labels.axisHeight(height, gap);

  double totalHeight(double height) => height;

  /// X position of point [index], mirrored so the series still reads
  /// start-to-finish in both directions.
  double _x(int index, double width) {
    if (points.length == 1) return width / 2;
    final step = width / (points.length - 1);
    return _isRtl ? width - index * step : index * step;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || size.width <= 0 || size.height <= 0) return;

    final axisHeight = _axisHeight(size.height);
    final budget = ChartBudget.of(
      height: size.height,
      axisHeight: axisHeight,
      labelHeight: labels.lineHeight(),
    );
    final baseline = budget.baseline;
    final plotHeight = budget.plotHeight;
    final maxValue = math.max(_maxValue, 1);

    double yOf(int value) =>
        baseline - (value <= 0 ? 0 : (value / maxValue) * plotHeight);

    // The scale the shape is drawn against.
    //
    // A line chart with no baseline and no gridline is a shape with nothing
    // under it: two readings can be compared by eye but not read, and "did it
    // really double" has no answer. A hairline at zero says where the floor
    // is, and the mid gridline gives the eye something to measure a reading
    // against. Both are hairlines in the hairline colour — they are structure,
    // not content.
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    final faintGridPaint = Paint()
      ..color = grid.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    final List<double> rules = gridLinesFor(budget);
    canvas.drawLine(
      Offset(0, rules[0].roundToDouble()),
      Offset(size.width, rules[0].roundToDouble()),
      gridPaint,
    );
    canvas.drawLine(
      Offset(0, rules[1].roundToDouble()),
      Offset(size.width, rules[1].roundToDouble()),
      faintGridPaint,
    );

    final line = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // The series, as points.
    final List<Offset> geometry = <Offset>[
      for (var i = 0; i < points.length; i++)
        Offset(_x(i, size.width), yOf(points[i].value)),
    ];

    // The line itself: SMOOTH, and monotone.
    //
    // A monotone cubic through the readings, so the shape of the day is drawn
    // as one gesture rather than as a row of corners — and so the curve never
    // leaves the range of the data, which a Catmull-Rom spline does the
    // moment the readings are noisy. A curve that invents a peak the shop
    // never had is not smoothing the data; it is misreporting it.
    final path = smoothPathThrough(geometry);

    // The area under the line, so the shape reads as a quantity and not just a
    // trajectory. Filled at low alpha: the line stays the signal.
    final area = Path.from(path)
      ..lineTo(_x(points.length - 1, size.width), baseline)
      ..lineTo(_x(0, size.width), baseline)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            accent.withValues(alpha: 0.22),
            accent.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, baseline)),
    );

    canvas.drawPath(path, line);

    // A dot per point: the places where a reading is actually taken, which is
    // what makes a gap in the data visible as a gap rather than a straight line
    // across it.
    final dot = Paint()..color = accent;
    for (var i = 0; i < points.length; i++) {
      canvas.drawCircle(geometry[i], 2.5, dot);
    }

    // The reading the finger revealed, marked a little larger than the rest.
    final int? revealed = selected;
    if (revealed != null && revealed >= 0 && revealed < points.length) {
      canvas.drawCircle(
        geometry[revealed],
        4.5,
        Paint()
          ..color = accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    // The figure on the chart: the reading the finger revealed, and the PEAK
    // when nothing is revealed.
    //
    // A colour difference would be the only other cue that one reading
    // matters, and colour alone is not a signal.
    var peakIndex = 0;
    for (var i = 1; i < points.length; i++) {
      if (points[i].value > points[peakIndex].value) peakIndex = i;
    }
    final int figureIndex = revealed ?? peakIndex;
    final peak = points[figureIndex];
    if (peak.value > 0) {
      // One TextPainter for the caption: laid out once, reused for its width,
      // its height and the paint. Snapped through the shared rule.
      final value = labels.painterFor(peak.displayValue);
      final valueWidth = value.width;

      // The scale's maximum, in the headroom the plot gave up.
      //
      // It is the same figure as the peak's — the peak IS the maximum — but it
      // answers a different question: not "which reading was highest" but "how
      // high is high". Without it the only number on the chart is the peak's,
      // and there is nothing to compare a smaller reading against.
      value.paint(canvas, Offset(0, 0));

      // The figure's own value, above its point — and clear of the scale's
      // label, which shares the top of the chart with it. The two are the same
      // number, so they would sit on the same pixels whenever the figure is the
      // first reading; the scale's label keeps the corner and the figure's
      // starts after it.
      final double minX = valueWidth + 6;
      final double snapped = labels.snapCenter(
          _x(figureIndex, size.width), valueWidth, size.width);
      final double x = math
          .max(snapped, math.min(minX, size.width - valueWidth))
          .clamp(0.0, math.max(0.0, size.width - valueWidth))
          .toDouble();
      final double y = budget
          .figureTop(yOf(peak.value), value.height)
          .clamp(0.0, math.max(0.0, size.height))
          .roundToDouble();
      value.paint(canvas, Offset(x, y));
    }

    if (axisHeight <= 0) return;

    // Axis labels, every Nth so they cannot overlap — and always the last one,
    // the most recent reading, which is the one a reader is looking for.
    //
    // The stride comes from the shared rule in [_ChartLabels]; the widest label
    // is read from its cache rather than measured here.
    final slot = size.width / math.max(points.length, 1);
    final stride = labels.stride(
      slot: slot,
      points: points,
      minStride: minStride,
    );
    final baselineY = baseline + gap;

    for (var i = 0; i < points.length; i += stride) {
      _paintAxisLabel(canvas, size, i, baselineY);
    }
    if ((points.length - 1) % stride != 0) {
      _paintAxisLabel(canvas, size, points.length - 1, baselineY);
    }
  }

  void _paintAxisLabel(Canvas canvas, Size size, int index, double baselineY) {
    if (index < 0 || index >= points.length) return;
    final painter = labels.painterFor(points[index].label);
    // PIXEL-SNAPPED, and this is what makes the axis readable.
    //
    // `TextPainter.paint` renders glyphs at exactly the offset it is given, with
    // no pixel alignment. The x position here is `index * width / (points - 1)`
    // — an arbitrary fraction — and the y is a computed baseline, also fractional.
    // A glyph whose origin lands at 10.4 straddles two device pixels, so the
    // rasteriser splits each stem across them and anti-aliases it: the label
    // reads as grey and soft rather than as crisp text.
    //
    // Rounding BOTH axes to whole logical pixels puts every glyph origin on the
    // pixel grid, which is what the framework's own text engine does for a
    // `Text` widget. It is a one-line change that is the difference between an
    // axis a cashier can read and one they squint at.
    final snappedX =
        labels.snapCenter(_x(index, size.width), painter.width, size.width);
    painter.paint(canvas, Offset(snappedX, baselineY.roundToDouble()));
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter old) =>
      old.points != points ||
      old.labels != labels ||
      old.accent != accent ||
      old.selected != selected ||
      old.minStride != minStride;
}

// ---------------------------------------------------------------------------
// Magnitude per bucket
// ---------------------------------------------------------------------------

/// How far apart the axis labels sit, in readings.
///
/// Three is the sensible interval for a trading day: a shop that opens at 8am
/// and closes at 11pm reads the axis as morning, midday, evening without
/// counting bars, and eight labels fit a 320dp phone without touching. It is a
/// floor, not a cap — a wider label or a narrower phone still widens the stride,
/// so the axis can never read as a row of collisions.
const int kPosChartMinStride = 3;

/// The old name, kept so the bar chart's constant still reads.
const int kPosBarChartMinStride = kPosChartMinStride;

/// A bar chart, for a total PER BUCKET: money taken in each hour of the day.
///
/// Bars rather than a line, and the choice matters. An hourly total is a
/// magnitude at a moment, not a trajectory through it: the question the
/// dashboard is asking is "which hour was best", and that is a comparison of
/// LENGTHS, which a bar answers without being described. A line over 24 hourly
/// buckets reads as a trend in a series of readings and invites tracing it
/// finger-first, when there is no reading between the hours to trace.
///
/// The money figure is revealed by touch, not painted. A painted peak value on
/// the chart is a label the shop did not ask for sitting over a picture of the
/// answer, and at this size it is the one label most likely to collide with the
/// hour beneath it. So a bar is quiet until it is tapped, and the tapped bar's
/// hour and figure are announced — a screen reader gets the same answer the
/// finger did, which is the part a painted label never managed.
///
/// Same accessibility contract as [PosLineChart]: the series is restated as a
/// sentence on a [Semantics] node and the painted content is excluded from it,
/// axis labels are dropped rather than squeezed, and the painter is free to
/// paint outside its box because there is no layout to overflow.
class PosBarChart extends StatefulWidget {
  const PosBarChart({
    super.key,
    required this.title,
    required this.points,
    this.semanticsLabel,
    this.height = 148,
    this.showTitle = true,
  });

  final String title;
  final List<PosLinePoint> points;
  final String? semanticsLabel;
  final double height;

  /// Whether the title is drawn.
  ///
  /// A chart inside a panel that already has a heading does not need a second
  /// one — and an EMPTY title still renders a heading, in the heading style, so
  /// it leaves a line of nothing where a line of something should be.
  final bool showTitle;

  /// The colour of a quiet hour's mark.
  ///
  /// The MEANINGFUL boundary colour, not the hairline: at 35% of the hairline
  /// the mark was about 1.1:1 against the card, which is a 1.5dp line nobody
  /// can see — and a closed day then looked like missing data, which is a
  /// different and more worrying claim.
  static Color emptySlotColor(BuildContext context) =>
      AppColors.of(context).outlineStrong;

  @override
  State<PosBarChart> createState() => _PosBarChartState();
}

class _PosBarChartState extends State<PosBarChart> {
  /// The bar the finger is on, or null for none.
  ///
  /// State rather than nothing: this is the one piece of the chart that a tap
  /// creates, and it belongs to the chart — a caller passing a selected index in
  /// would be duplicating a fact the gesture already produced.
  int? _selected;

  /// Label measurements, owned HERE so they outlive the painter.
  ///
  /// A painter is built on every `build()`, so widths cached inside one are
  /// always cold: `paint()` used to lay all twenty-four hour labels out again
  /// on every tap that moved the selection. They depend on the labels, the
  /// style, the scaler and the direction — all four are checked before the
  /// helper is reused.
  final Map<String, double> _labelWidths = <String, double>{};
  _ChartLabels? _labels;

  /// The shared label helper for the style this state is building with.
  ///
  /// Equality, not identity: a theme hands out a `TextStyle` that compares
  /// equal across builds, and comparing by identity would throw a perfectly
  /// good cache away and re-measure every label on every rebuild.
  _ChartLabels _labelsFor(TextStyle style) {
    final direction = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final existing = _labels;
    if (existing != null &&
        existing.labelStyle == style &&
        existing.direction == direction &&
        existing.textScaler == scaler) {
      return existing;
    }
    // A different type scale or direction invalidates every measurement, not
    // just the ones this dataset uses.
    _labelWidths.clear();
    return _labels = _ChartLabels(
      labelStyle: style,
      direction: direction,
      textScaler: scaler,
      widths: _labelWidths,
    );
  }

  @override
  void didUpdateWidget(covariant PosBarChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A fresh day's bars make the previous selection meaningless: the bar the
    // owner tapped is a different hour's money now.
    if (!identical(oldWidget.points, widget.points) &&
        oldWidget.points != widget.points) {
      _selected = null;
      // A new series is a new set of labels, so the widths measured for the old
      // one are dead weight: clearing here bounds the map by the live series
      // instead of by every width this chart has ever been laid out at.
      _labelWidths.clear();
    }
  }

  /// Selects the bar under [localX].
  ///
  /// [toggle] is false for a drag: sliding a finger along the chart MOVES the
  /// selection, and it does not clear it when the finger passes over the bar
  /// that is already selected — which is what a tap does.
  void _selectAt(double localX, double width, {bool toggle = true}) {
    final points = widget.points;
    if (points.isEmpty || width <= 0) return;
    final slot = width / points.length;
    // Mirrored in RTL, because the painter mirrors the bars: without this, a
    // tap on the right of the chart picks the hour at the OTHER end of the
    // day.
    final double fromStart = Directionality.of(context) == TextDirection.rtl
        ? width - localX
        : localX;
    final index = (fromStart / slot).floor().clamp(0, points.length - 1);
    if (!toggle) {
      if (_selected == index) return;
      setState(() => _selected = index);
      return;
    }
    setState(() => _selected = _selected == index ? null : index);
  }

  void _selectRelative(int direction) {
    if (widget.points.isEmpty) return;
    final int current =
        _selected ?? (direction > 0 ? -1 : widget.points.length);
    final int next = (current + direction).clamp(0, widget.points.length - 1);
    if (_selected == next) return;
    setState(() => _selected = next);
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);
    final l10n = AppLocalizations.of(context);
    final labelStyle = type.bodySmall ?? const TextStyle();
    final selected = widget.points.isEmpty ? null : _selected;

    // The announcement is the chart's, not the caller's to own. A caller's
    // `semanticsLabel` describes the SERIES; what a tap just revealed is a fact
    // the chart alone knows, so the two are composed rather than one
    // overriding the other — which is how the selected-bar sentence ended up
    // unreachable on the one screen that passes a label of its own.
    // What each bar says, for the screen reader that cannot see it.
    //
    // The canvas is NOT excluded from semantics any more: the painter gives
    // every bar its own node, and a chart of readings that cannot be stepped
    // through is a chart that cannot be read. The gesture layer is excluded
    // instead, so the tap action does not become a second, unlabelled stop.
    final List<String> barLabels = <String>[
      for (final PosLinePoint point in widget.points)
        l10n.chartSpokenBar(point.label, point.displayValue),
    ];

    return Semantics(
      label: _announcement(l10n),
      container: true,
      onIncrease: () => _selectRelative(1),
      onDecrease: () => _selectRelative(-1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (widget.showTitle) ...<Widget>[
            Text(widget.title, style: type.titleMedium),
            SizedBox(height: spacing.sm),
          ],
          if (widget.points.isEmpty)
            Text(l10n.chartNothingToShow, style: labelStyle)
          else
            // The width the slots are cut from is the CANVAS's width, so the
            // selection is computed from the width the painter used and not
            // from the width of whatever contains the chart.
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final width = constraints.maxWidth.isFinite
                    ? constraints.maxWidth
                    : constraints.biggest.width;
                final painter = _BarChartPainter(
                  points: widget.points,
                  plotHeight: widget.height,
                  selected: selected,
                  accent: colors.accent,
                  emptySlot: PosBarChart.emptySlotColor(context),
                  gap: spacing.sm,
                  labels: _labelsFor(labelStyle),
                  semanticsLabels: barLabels,
                );
                return SizedBox(
                  width: width,
                  height: painter.totalHeight(widget.height),
                  child: GestureDetector(
                    // The whole plot is the target, not one bar: a finger
                    // between two bars still selects the nearer hour, and a
                    // shop working through a queue should not have to aim.
                    onTapUp: (TapUpDetails details) =>
                        _selectAt(details.localPosition.dx, width),
                    // A DRAG selects too.
                    //
                    // On a 24-hour chart on a 328dp phone each slot is about
                    // 14dp wide and the bar about 9dp — well under the 44dp a
                    // tap is supposed to be comfortable on. A finger can slide
                    // along the chart and the selection follows it, so nobody
                    // has to hit a 9dp target with a fingertip.
                    onHorizontalDragUpdate: (DragUpdateDetails details) =>
                        _selectAt(details.localPosition.dx, width,
                            toggle: false),
                    // The gesture layer is not a reading; the bars are.
                    excludeFromSemantics: true,
                    behavior: HitTestBehavior.opaque,
                    child: CustomPaint(painter: painter),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  /// What a screen reader says for this chart right now.
  ///
  /// The caller's description when it gave one, the series summary otherwise,
  /// and the tapped bar's figure APPENDED while one is tapped — so the
  /// announcement always carries the fact the finger just produced.
  String _announcement(AppLocalizations l10n) {
    final String base = widget.semanticsLabel ??
        (widget.points.isEmpty
            ? l10n.chartSpokenNoValues(widget.title)
            : l10n.chartSpokenPeak(
                widget.points.length,
                widget.points.reduce((a, b) => b.value > a.value ? b : a).label,
                widget.title,
                widget.points
                    .reduce((a, b) => b.value > a.value ? b : a)
                    .displayValue,
              ));
    final int? at = _selected;
    if (at == null || at >= widget.points.length) return base;
    final PosLinePoint point = widget.points[at];
    if (point.value <= 0) return base;
    return '$base. ${l10n.chartSpokenSelected(point.label, widget.title, point.displayValue)}';
  }
}

/// The painted part, kept separate so the [Semantics] wrapper can exclude it in
/// one place.
class _BarChartPainter extends CustomPainter {
  _BarChartPainter({
    required this.points,
    required this.plotHeight,
    required this.selected,
    required this.accent,
    required this.emptySlot,
    required this.gap,
    required this.labels,
    required this.semanticsLabels,
  });

  final List<PosLinePoint> points;
  final double plotHeight;

  /// The tapped bar, or null. Only this bar carries a figure, and it carries it
  /// as text above the bar rather than inside it — a label a finger revealed is
  /// one the tap made room for.
  final int? selected;
  final Color accent;
  final Color emptySlot;
  final double gap;

  /// Shared label measurement and axis rules — see [_ChartLabels]. Owned by the
  /// chart's state so its measurements outlive this painter.
  final _ChartLabels labels;

  /// What each bar says, in the same order as [points].
  ///
  /// Built by the chart, which has the localisations; the painter only paints
  /// and places them.
  final List<String> semanticsLabels;

  /// A bar never fills its slot: two bars touching read as one column of
  /// matched height rather than as separate hours.
  static const double _barFraction = 0.62;

  static const double _maxBarWidth = 16;

  bool get _isRtl => labels.isRtl;

  int get _maxValue => points.fold(0, (m, p) => math.max(m, p.value));

  double totalHeight(double height) => height;

  /// The slot each bar owns.
  double _slot(double width) => width / math.max(points.length, 1);

  /// Every Nth label drawn on the axis.
  ///
  /// The stride is the interval the axis reads at, so it is the whole
  /// difference between an axis a shop can read and the row of collisions this
  /// replaces. It starts at [kPosBarChartMinStride] and widens only when the
  /// labels genuinely need the room — see the shared rule in [_ChartLabels].
  int _stride(double width) => labels.stride(
        slot: _slot(width),
        points: points,
        minStride: kPosBarChartMinStride,
      );

  /// Left edge of bar [index], mirrored for RTL so the day still reads
  /// start-to-finish in both directions.
  double _barLeft(int index, double width) {
    final slot = _slot(width);
    final raw = index * slot + (slot - _barWidth(slot)) / 2;
    return _isRtl ? width - raw - _barWidth(slot) : raw;
  }

  double _barWidth(double slot) => math.min(slot * _barFraction, _maxBarWidth);

  double _heightOf(int value, double plotHeight) {
    final max = math.max(_maxValue, 1);
    return value <= 0 ? 0 : (value / max) * plotHeight;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || size.width <= 0 || size.height <= 0) return;

    final axisHeight = labels.axisHeight(size.height, gap);
    final budget = ChartBudget.of(
      height: size.height,
      axisHeight: axisHeight,
      labelHeight: labels.lineHeight(),
    );
    final baseline = budget.baseline;
    final plotHeight = budget.plotHeight;
    final slot = _slot(size.width);
    final barWidth = _barWidth(slot);

    final bar = Paint()..color = accent;
    final chosen = Paint()..color = accent;
    final empty = Paint()..color = emptySlot;

    for (var i = 0; i < points.length; i++) {
      final height = _heightOf(points[i].value, plotHeight);
      final x = _barLeft(i, size.width);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, baseline - height, barWidth, math.max(height, 2)),
        Radius.circular(math.min(barWidth / 2, 3)),
      );
      // A zero hour is a hairline, not nothing: the shop needs to see that the
      // hour is counted, or a gap in the middle of the day reads as missing data
      // rather than as a quiet hour.
      if (points[i].value <= 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, baseline - 1.5, barWidth, 1.5),
            Radius.circular(barWidth / 2),
          ),
          empty,
        );
        continue;
      }
      canvas.drawRRect(rect, i == selected ? chosen : bar);
    }

    // The revealed figure, above the bar it belongs to and nowhere else.
    //
    // ONE laid-out painter, reused for the width, the height and the paint:
    // the figure used to be laid out three times per frame for the same string.
    if (selected != null && points[selected!].value > 0) {
      final at = points[selected!];
      final value = labels.painterFor(at.displayValue);
      final valueWidth = labels.widthOf(at.displayValue);
      final x = labels.snapCenter(
          _barLeft(selected!, size.width) + barWidth / 2,
          valueWidth,
          size.width);
      // Four pixels below the top of the bar, which the headroom makes room
      // for: the figure is a label ON the chart, not a cap over it.
      final y = budget
          .figureTop(baseline - _heightOf(at.value, plotHeight), value.height)
          .clamp(0.0, math.max(0.0, size.height))
          .roundToDouble();
      value.paint(canvas, Offset(x, y));
    }

    if (axisHeight <= 0) return;

    final stride = _stride(size.width);
    final baselineY = baseline + gap;
    // The first label is the start of the window and is always drawn — it is
    // what the rest of the axis is measured from. The last is drawn only when
    // it does not land on top of the previous one.
    for (var i = 0; i < points.length; i += stride) {
      _paintAxisLabel(canvas, size, i, baselineY);
    }
    final last = points.length - 1;
    if (last % stride != 0 && _fits(last, stride, size.width)) {
      _paintAxisLabel(canvas, size, last, baselineY);
    }
  }

  /// Whether the label at [index] is far enough from the one before it.
  bool _fits(int index, int stride, double width) {
    final previous = index - (index % stride);
    if (previous < 0 || previous >= index) return true;
    final slot = _slot(width);
    final widest = labels.widest(points, math.max(slot, 12.0));
    return (index - previous) * slot >= widest * _ChartLabels.collisionFactor;
  }

  void _paintAxisLabel(Canvas canvas, Size size, int index, double baselineY) {
    if (index < 0 || index >= points.length) return;
    final painter = labels.painterFor(points[index].label);
    // Pixel-snapped, for the same reason [PosLineChart]'s are: a fractional
    // glyph origin straddles two device pixels and anti-aliases the label into
    // softness.
    final x = labels.snapCenter(
        _barLeft(index, size.width) + _barWidth(_slot(size.width)) / 2,
        painter.width,
        size.width);
    painter.paint(canvas, Offset(x, baselineY.roundToDouble()));
  }

  /// One semantics node per bar.
  ///
  /// A painted canvas has no text nodes, so without this a screen reader
  /// hears the chart's summary and NOTHING else: it cannot step through the
  /// bars, and a bar chart is a list of readings, so a list of readings it
  /// cannot reach is a chart it cannot read.
  ///
  /// The node covers the bar's whole SLOT, not just the bar: a 9dp-wide
  /// rectangle is a poor thing to ask a finger to find, and the slots tile the
  /// chart without gaps, so the nodes do too.
  @override
  SemanticsBuilderCallback get semanticsBuilder => (Size size) {
        final double slot = _slot(size.width);
        final List<CustomPainterSemantics> nodes = <CustomPainterSemantics>[];
        for (var i = 0; i < points.length; i++) {
          if (i >= semanticsLabels.length) break;
          final String label = semanticsLabels[i];
          if (label.isEmpty) continue;
          final double raw = i * slot;
          final double x = _isRtl ? size.width - raw - slot : raw;
          nodes.add(CustomPainterSemantics(
            key: ValueKey<int>(i),
            rect: Rect.fromLTWH(x, 0, slot, size.height),
            properties: SemanticsProperties(
              label: label,
              textDirection: labels.direction,
            ),
          ));
        }
        return nodes;
      };

  @override
  bool shouldRepaint(covariant _BarChartPainter old) =>
      old.points != points ||
      old.selected != selected ||
      old.labels != labels ||
      old.accent != accent;

  @override
  bool shouldRebuildSemantics(covariant _BarChartPainter old) =>
      old.semanticsLabels != semanticsLabels || old.selected != selected;
}

// ---------------------------------------------------------------------------
// Part-to-whole
// ---------------------------------------------------------------------------

/// One slice of a whole — a tender, a category, a share.
///
/// [color] comes from the caller rather than from the chart: which slice is which
/// tender is a fact the screen knows and the chart does not, and the legend
/// repeats it in words so colour is never the only channel.
@immutable
class PosPieSlice {
  const PosPieSlice({
    required this.label,
    required this.value,
    required this.color,
    this.valueLabel,
  });

  final String label;
  final int value;

  final Color color;

  /// Pre-formatted figure, e.g. `KSh 4,200`. Falls back to the raw value.
  final String? valueLabel;

  String get displayValue => valueLabel ?? '$value';
}

/// A donut chart, for a WHOLE and the parts it is made of.
///
/// The bar chart this replaces was the wrong instrument for a payment mix: five
/// horizontal bars invite reading them as a ranking, when the question is "is
/// this shop cash-heavy or mobile-money-heavy" — a question a ring answers at a
/// glance and a list of bars answers only after five comparisons.
///
/// The legend is real text, not painted: a label a screen reader cannot reach
/// and that cannot grow with the user's text scale is the thing this chart
/// exists to avoid, and the ring is the only painted part.
class PosPieChart extends StatelessWidget {
  const PosPieChart({
    super.key,
    required this.title,
    required this.slices,
    this.semanticsLabel,
    this.centerLabel,
    this.centerValue,
    this.size = 132,
    this.showTitle = true,
  });

  final String title;
  final List<PosPieSlice> slices;
  final String? semanticsLabel;

  /// Whether the title is drawn.
  ///
  /// A chart inside a section that already has a heading does not need a
  /// second one — and an EMPTY title still renders a heading, in the heading
  /// style, so it leaves a line of nothing where a line of something should
  /// be.
  final bool showTitle;

  /// Small word over the figure in the hole — "Total", "Taken".
  final String? centerLabel;

  /// The whole the slices divide — rendered as real text so it scales.
  final String? centerValue;

  final double size;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);
    final bool compactLegend = MediaQuery.textScalerOf(context).scale(1) > 1.3;

    Widget legendRow(PosPieSlice slice) => LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool stackValue = compactLegend || constraints.maxWidth < 170;
            final Widget label = stackValue
                ? Expanded(
                    child: Text(
                      slice.label,
                      style: type.bodySmall,
                      maxLines: 2,
                    ),
                  )
                : Text(
                    slice.label,
                    style: type.bodySmall,
                    maxLines: 2,
                  );
            final Widget identity = Row(
              children: <Widget>[
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: slice.color,
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: spacing.sm),
                label,
              ],
            );
            final Widget value = Text(
              slice.displayValue,
              style: AppTypography.money(
                context,
                size: 12,
                weight: FontWeight.w600,
              ),
            );
            return Padding(
              padding: EdgeInsets.symmetric(vertical: spacing.xs),
              child: stackValue
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        identity,
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: value,
                        ),
                      ],
                    )
                  : Row(
                      children: <Widget>[
                        identity,
                        SizedBox(width: spacing.xs),
                        value,
                      ],
                    ),
            );
          },
        );

    final total = slices.fold<int>(0, (sum, s) => sum + s.value);

    return Semantics(
      label: semanticsLabel ??
          _fallbackSemantics(AppLocalizations.of(context), total),
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (showTitle) ...<Widget>[
            Text(title, style: type.titleMedium),
            SizedBox(height: spacing.sm),
          ],
          if (slices.isEmpty)
            Text(
              AppLocalizations.of(context).chartNothingToShow,
              style: type.bodySmall,
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                // The ring, with the total inside it as real text over a hole.
                //
                // The ring is a MINIMUM, not a fixed box. The centre figure is
                // real text, and at 200% text scale it is TALLER than the ring:
                // a fixed-height box clipped it, and a clipped number is worse
                // than a taller row. The box grows with the text instead, and
                // the ring stays a circle drawn at its own size.
                ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: size,
                    minHeight: size,
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      ExcludeSemantics(
                        child: CustomPaint(
                          size: Size.square(size),
                          painter: _PiePainter(slices: slices, total: total),
                        ),
                      ),
                      if (centerValue != null)
                        // The centre figure is capped to the ring's hole: a
                        // 32-digit total would otherwise fill the middle and
                        // swallow the arcs it is supposed to summarise.
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: size * 0.62,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              if (centerLabel != null)
                                Text(
                                  centerLabel!,
                                  textAlign: TextAlign.center,
                                  style: type.bodySmall?.copyWith(
                                    color: AppColors.of(context).onSurfaceMuted,
                                  ),
                                ),
                              // Real text, at the size the scale asks for.
                              //
                              // NOT a `FittedBox`: scaling the figure down to
                              // fit would quietly defeat the user's text-scale
                              // setting, which is the one thing this chart must
                              // not do. The figure wraps inside the hole's
                              // width instead, and the ring grows around it.
                              Text(
                                centerValue!,
                                textAlign: TextAlign.center,
                                style: AppTypography.money(
                                  context,
                                  size: 16,
                                  weight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(width: spacing.md),
                // The legend: swatch, name, figure. This is the part that
                // survives greyscale, a colour-blind reader, and a screen
                // reader — the ring is a picture of what is already written
                // here.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      for (final PosPieSlice slice in slices) legendRow(slice),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  String _fallbackSemantics(AppLocalizations l10n, int total) {
    if (slices.isEmpty) return l10n.chartSpokenNoValues(title);
    // The centre figure IS the total, already formatted. Speaking the raw
    // minor-unit integer instead would read "KSh 12,500.00" as "one million
    // two hundred fifty thousand" — the money spoken as a number of cents.
    return describeSlices(l10n, title, slices, total, totalLabel: centerValue);
  }
}

/// The arc each slice of a ring is given, in radians, in the order given.
///
/// Every slice is given at least a sliver, and that sliver is BIGGER than the
/// slice's share: a tender with one sale against a hundred is inflated to
/// something visible, and nothing takes that back. Inflate a few of those and
/// the arcs add up to more than a full turn — so the last arc paints over the
/// first, and the ring shows a slice twice.
///
/// So the slices that are not inflated give back exactly what the inflated
/// ones borrowed: the big ones are scaled down by the amount the small ones
/// took, and the arcs then sum to a full turn.
///
/// Public because that sum is the invariant, and a painted ring is not
/// something a test can measure.
List<double> pieSweeps(List<PosPieSlice> slices, int total) {
  final List<PosPieSlice> live = <PosPieSlice>[
    for (final PosPieSlice slice in slices)
      if (slice.value > 0) slice,
  ];
  if (live.isEmpty || total <= 0) return const <double>[];
  final List<double> raw = <double>[
    for (final PosPieSlice slice in live) 2 * math.pi * slice.value / total,
  ];
  final int small = raw.where((double r) => r < _pieMinSweep).length;
  final double big =
      raw.where((double r) => r >= _pieMinSweep).fold(0.0, (a, b) => a + b);
  final double k = big <= 0 ? 1.0 : (2 * math.pi - small * _pieMinSweep) / big;
  return <double>[
    for (final double r in raw) r < _pieMinSweep ? _pieMinSweep : r * k,
  ];
}

/// The smallest arc a slice of a ring may have, in radians.
const double _pieMinSweep = 0.04;

/// The ring. Painted only — the total and the legend are widgets above it.
class _PiePainter extends CustomPainter {
  _PiePainter({required this.slices, required this.total});

  final List<PosPieSlice> slices;
  final int total;

  /// The hole, as a share of the radius. Big enough that the figure inside it
  /// has somewhere to live, small enough that each slice is still readable as a
  /// length of arc.
  static const double _holeFraction = 0.58;

  /// The smallest arc a slice may have, in radians.
  ///
  /// A tender that took one sale is a fact the ring is being asked to show, and
  /// a gap would read as "not counted".
  static const double _minSweep = _pieMinSweep;

  /// The gap between two slices, in radians. A degree and a half.
  ///
  /// Without it, two similar hues — the success green and the accent green —
  /// blur into one arc, and the boundary between "M-Pesa" and "bank transfer"
  /// is a line nobody can find. A degree and a half is enough to separate them
  /// and small enough that the ring still reads as a whole.
  static const double _sliceGap = 0.026;

  /// The arc each slice gets — see [pieSweeps].
  static List<double> _sweeps(List<PosPieSlice> live, int total) =>
      pieSweeps(live, total);

  @override
  void paint(Canvas canvas, Size size) {
    if (slices.isEmpty || total <= 0) return;

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final stroke = size.width * (1 - _holeFraction) / 2;
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;

    final List<PosPieSlice> live = <PosPieSlice>[
      for (final PosPieSlice slice in slices)
        if (slice.value > 0) slice,
    ];
    if (live.isEmpty) return;
    final int liveTotal =
        live.fold<int>(0, (int sum, PosPieSlice slice) => sum + slice.value);
    final List<double> sweeps = _sweeps(live, liveTotal);

    var start = -math.pi / 2;
    for (var i = 0; i < live.length; i++) {
      final double sweep = sweeps[i];
      // The gap is taken OUT of the slice, so the ring still closes and the
      // separation is a space rather than a shortening of the last arc.
      final double drawn = math.max(sweep - _sliceGap, _minSweep * 0.4);
      ringPaint.color = live[i].color;
      canvas.drawArc(
        rect.deflate(stroke / 2),
        start,
        drawn,
        false,
        ringPaint,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _PiePainter old) =>
      old.slices != slices || old.total != total;
}

/// The ring's non-visual equivalent: the title, the whole, and every part in
/// order. Public so the payment-mix screen can reuse it for its table.
String describeSlices(
  AppLocalizations l10n,
  String title,
  List<PosPieSlice> slices,
  int total, {
  String? totalLabel,
}) {
  if (slices.isEmpty) return l10n.chartSpokenNoValues(title);
  final ordered = List<PosPieSlice>.from(slices)
    ..sort((a, b) => b.value.compareTo(a.value));
  final parts = ordered
      .map((s) => '${s.label} ${s.displayValue}, '
          '${(s.value * 100 / math.max(total, 1)).round()} percent')
      .join('; ');
  // The total, SPOKEN AS A FIGURE.
  //
  // The slices' own values are formatted — "KSh 4,200.00" — and the total
  // was the raw integer, so "KSh 12,500.00" was announced as "total one
  // million two hundred fifty thousand": the money read as a number of cents,
  // and a cashier hearing it has no idea what it is.
  //
  // When no formatted total is available the sentence leaves it out, because
  // a wrong total is worse than no total.
  final String head = totalLabel == null ? title : '$title, total $totalLabel';
  return '$head. $parts.';
}
