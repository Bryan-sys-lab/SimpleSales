import 'dart:math' as math;

import 'package:flutter/material.dart';

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

/// A line chart, for a series the eye reads as a SEQUENCE.
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
  });

  final String title;
  final List<PosLinePoint> points;
  final String? semanticsLabel;

  /// Plot height. The axis strip is added on top of it.
  final double height;

  final String? emphasis;

  @override
  State<PosLineChart> createState() => _PosLineChartState();
}

class _PosLineChartState extends State<PosLineChart> {
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
    return l10n.chartSpokenPeak(widget.points.length, peak.label, widget.title,
        peak.displayValue);
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);
    final labelStyle = type.bodySmall ?? const TextStyle();
    final l10n = AppLocalizations.of(context);

    return Semantics(
      label: widget.semanticsLabel ?? _fallbackSemantics(l10n),
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(widget.title, style: type.titleMedium),
          if (widget.emphasis != null) ...[
            const SizedBox(height: 2),
            Text(widget.emphasis!, style: labelStyle),
          ],
          SizedBox(height: spacing.sm),
          if (widget.points.isEmpty)
            Text(l10n.chartNothingToShow, style: labelStyle)
          else
            // Excluded so a painted canvas with no text nodes cannot announce
            // anything: the series is already stated as a sentence on the
            // [Semantics] node above, and this is what keeps it from being
            // announced twice.
            ExcludeSemantics(
              child: _LineCanvas(
                points: widget.points,
                height: widget.height,
                accent: colors.accent,
                gap: spacing.sm,
                labels: _labelsFor(labelStyle),
              ),
            ),
        ],
      ),
    );
  }
}

/// The painted part, kept separate so the [Semantics] wrapper can exclude it in
/// one place.
class _LineCanvas extends StatelessWidget {
  const _LineCanvas({
    required this.points,
    required this.height,
    required this.accent,
    required this.gap,
    required this.labels,
  });

  final List<PosLinePoint> points;
  final double height;
  final Color accent;
  final double gap;

  /// Shared label measurement and axis rules. Owned by [_PosLineChartState] so
  /// its measurements outlive the painter this build creates.
  final _ChartLabels labels;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : constraints.biggest.width;
        final painter = _LineChartPainter(
          points: points,
          plotHeight: height,
          accent: accent,
          gap: gap,
          labels: labels,
        );
        return SizedBox(
          width: width,
          height: painter.totalHeight(height),
          child: CustomPaint(painter: painter),
        );
      },
    );
  }
}

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
  double lineHeight() =>
      _lineHeightValue ??= painterFor('Ag').height;

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
    final needed =
        (widestLabel * collisionFactor / math.max(slot, 1)).ceil();
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
    required this.accent,
    required this.gap,
    required this.labels,
  });

  final List<PosLinePoint> points;
  final double plotHeight;
  final Color accent;
  final double gap;

  /// Shared label measurement and axis rules — see [_ChartLabels]. It carries
  /// the style, direction and scaler this painter paints with, so a change of
  /// any of them changes the helper and with it [shouldRepaint]'s answer.
  final _ChartLabels labels;

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
    final plotHeight = size.height - axisHeight;
    final baseline = size.height - axisHeight;
    final maxValue = math.max(_maxValue, 1);

    double yOf(int value) =>
        baseline - (value <= 0 ? 0 : (value / maxValue) * plotHeight);

    final line = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()..moveTo(_x(0, size.width), yOf(points[0].value));
    for (var i = 1; i < points.length; i++) {
      path.lineTo(_x(i, size.width), yOf(points[i].value));
    }

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
      canvas.drawCircle(
          Offset(_x(i, size.width), yOf(points[i].value)), 2.5, dot);
    }

    // The peak, stated in text. A colour difference would be the only other cue
    // that one reading matters, and colour alone is not a signal.
    var peakIndex = 0;
    for (var i = 1; i < points.length; i++) {
      if (points[i].value > points[peakIndex].value) peakIndex = i;
    }
    final peak = points[peakIndex];
    if (peak.value > 0) {
      // One TextPainter for the caption: laid out once, reused for its width,
      // its height and the paint. Snapped through the shared rule.
      final value = labels.painterFor(peak.displayValue);
      final valueWidth = value.width;
      final x = labels.snapCenter(
          _x(peakIndex, size.width), valueWidth, size.width);
      final y = (yOf(peak.value) - value.height - 6)
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
    final stride = labels.stride(slot: slot, points: points, minStride: 1);
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
      old.accent != accent;
}

// ---------------------------------------------------------------------------
// Magnitude per bucket
// ---------------------------------------------------------------------------

/// How far apart the axis labels sit, in bars.
///
/// Three is the sensible interval for a trading day: a shop that opens at 8am
/// and closes at 11pm reads the axis as morning, midday, evening without
/// counting bars, and eight labels fit a 320dp phone without touching. It is a
/// floor, not a cap — a wider label or a narrower phone still widens the stride,
/// so the axis can never read as a row of collisions.
const int kPosBarChartMinStride = 3;

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
  });

  final String title;
  final List<PosLinePoint> points;
  final String? semanticsLabel;
  final double height;

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

  void _selectAt(double localX, double width) {
    final points = widget.points;
    if (points.isEmpty || width <= 0) return;
    final slot = width / points.length;
    final index = (localX / slot).floor().clamp(0, points.length - 1);
    setState(() => _selected = _selected == index ? null : index);
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
    return Semantics(
      label: _announcement(l10n),
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(widget.title, style: type.titleMedium),
          SizedBox(height: spacing.sm),
          if (widget.points.isEmpty)
            Text(l10n.chartNothingToShow, style: labelStyle)
          else
            ExcludeSemantics(
              child: GestureDetector(
                // The whole plot is the target, not one bar: a finger between
                // two bars still selects the nearer hour, and a shop working
                // through a queue should not have to aim.
                onTapUp: (TapUpDetails details) => _selectAt(
                  details.localPosition.dx,
                  context.size?.width ?? 0,
                ),
                behavior: HitTestBehavior.opaque,
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final width = constraints.maxWidth.isFinite
                        ? constraints.maxWidth
                        : constraints.biggest.width;
                    final painter = _BarChartPainter(
                      points: widget.points,
                      plotHeight: widget.height,
                      selected: selected,
                      accent: colors.accent,
                      emptySlot: colors.outline.withValues(alpha: 0.35),
                      gap: spacing.sm,
                      labels: _labelsFor(labelStyle),
                    );
                    return SizedBox(
                      width: width,
                      height: painter.totalHeight(widget.height),
                      child: CustomPaint(painter: painter),
                    );
                  },
                ),
              ),
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
    final plotHeight = size.height - axisHeight;
    final baseline = size.height - axisHeight;
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
      final y = (baseline - _heightOf(at.value, plotHeight) - value.height - 4)
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
    return (index - previous) * slot >=
        widest * _ChartLabels.collisionFactor;
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

  @override
  bool shouldRepaint(covariant _BarChartPainter old) =>
      old.points != points ||
      old.selected != selected ||
      old.labels != labels ||
      old.accent != accent;
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
  });

  final String title;
  final List<PosPieSlice> slices;
  final String? semanticsLabel;

  /// Small word over the figure in the hole — "Total", "Taken".
  final String? centerLabel;

  /// The whole the slices divide — rendered as real text so it scales.
  final String? centerValue;

  final double size;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);

    final total = slices.fold<int>(0, (sum, s) => sum + s.value);

    return Semantics(
      label: semanticsLabel ??
          _fallbackSemantics(AppLocalizations.of(context), total),
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(title, style: type.titleMedium),
          SizedBox(height: spacing.sm),
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
                // `IntrinsicHeight` is not a trick to force; the ring is sized
                // by its own [size], and the centre figure is painted as real
                // text, so the ROW grows to whichever is taller. A fixed-height
                // `SizedBox` here overflowed by 12px at 2.0× text, which is the
                // one failure mode the brief bans.
                SizedBox(
                  width: size,
                  height: size,
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
                                  maxLines: 2,
                                  textAlign: TextAlign.center,
                                  style: type.bodySmall?.copyWith(
                                    color: AppColors.of(context).onSurfaceMuted,
                                  ),
                                ),
                              FittedBox(
                                child: Text(
                                  centerValue!,
                                  style: AppTypography.money(
                                    context,
                                    size: 16,
                                    weight: FontWeight.w700,
                                  ),
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
                      for (final PosPieSlice slice in slices)
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: spacing.xs),
                          child: Row(
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
                              Expanded(
                                child: Text(
                                  slice.label,
                                  style: type.bodySmall,
                                  maxLines: 2,
                                ),
                              ),
                              SizedBox(width: spacing.xs),
                              Text(
                                slice.displayValue,
                                style: AppTypography.money(
                                  context,
                                  size: 12,
                                  weight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
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
    return describeSlices(l10n, title, slices, total);
  }
}

/// The ring. Painted only — the total and the legend are widgets above it.
class _PiePainter extends CustomPainter {
  _PiePainter({required this.slices, required this.total});

  final List<PosPieSlice> slices;
  final int total;

  /// The hole, as a share of the radius. Big enough that the figure inside it
  /// has somewhere to live, small enough that each slice is still readable as a
  /// length of arc.
  static const double _holeFraction = 0.58;

  @override
  void paint(Canvas canvas, Size size) {
    if (slices.isEmpty || total <= 0) return;

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final stroke = size.width * (1 - _holeFraction) / 2;
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;

    var start = -math.pi / 2;
    for (final PosPieSlice slice in slices) {
      if (slice.value <= 0) continue;
      // At least a sliver: a tender that took one sale is a fact the ring is
      // being asked to show, and a gap would read as "not counted".
      final sweep = math.max(2 * math.pi * (slice.value / total), 0.04);
      ringPaint.color = slice.color;
      canvas.drawArc(
        rect.deflate(stroke / 2),
        start,
        sweep,
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
  int total,
) {
  if (slices.isEmpty) return l10n.chartSpokenNoValues(title);
  final ordered = List<PosPieSlice>.from(slices)
    ..sort((a, b) => b.value.compareTo(a.value));
  final parts = ordered
      .map((s) => '${s.label} ${s.displayValue}, '
          '${(s.value * 100 / math.max(total, 1)).round()} percent')
      .join('; ');
  return '$title, total ${ordered.fold<int>(0, (sum, s) => sum + s.value)}. $parts.';
}
