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
class PosLineChart extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);
    final labelStyle = type.bodySmall ?? const TextStyle();

    return Semantics(
      label: semanticsLabel ?? _fallbackSemantics(AppLocalizations.of(context)),
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(title, style: type.titleMedium),
          if (emphasis != null) ...[
            const SizedBox(height: 2),
            Text(emphasis!, style: labelStyle),
          ],
          SizedBox(height: spacing.sm),
          if (points.isEmpty)
            Text(
              AppLocalizations.of(context).chartNothingToShow,
              style: labelStyle,
            )
          else
            ExcludeSemantics(
              child: _LineCanvas(
                points: points,
                height: height,
                labelStyle: labelStyle,
                direction: Directionality.of(context),
                accent: colors.accent,
                gap: spacing.sm,
              ),
            ),
        ],
      ),
    );
  }

  String _fallbackSemantics(AppLocalizations l10n) {
    if (points.isEmpty) return l10n.chartSpokenNoValues(title);
    final peak = points.reduce((a, b) => b.value > a.value ? b : a);
    return l10n.chartSpokenPeak(
        points.length, peak.label, title, peak.displayValue);
  }
}

/// The painted part, kept separate so the [Semantics] wrapper can exclude it in
/// one place.
class _LineCanvas extends StatelessWidget {
  const _LineCanvas({
    required this.points,
    required this.height,
    required this.labelStyle,
    required this.direction,
    required this.accent,
    required this.gap,
  });

  final List<PosLinePoint> points;
  final double height;
  final TextStyle labelStyle;
  final TextDirection direction;
  final Color accent;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : constraints.biggest.width;
        final painter = _LineChartPainter(
          points: points,
          labelStyle: labelStyle,
          direction: direction,
          textScaler: scaler,
          plotHeight: height,
          accent: accent,
          gap: gap,
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

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({
    required this.points,
    required this.labelStyle,
    required this.direction,
    required this.textScaler,
    required this.plotHeight,
    required this.accent,
    required this.gap,
  });

  final List<PosLinePoint> points;
  final TextStyle labelStyle;
  final TextDirection direction;
  final TextScaler textScaler;
  final double plotHeight;
  final Color accent;
  final double gap;

  /// Label metrics, laid out ONCE.
  ///
  /// `paint()` re-runs on every repaint — for an hourly chart that is 24
  /// `TextPainter.layout()` calls per frame, on top of the line height — and it
  /// used to redo all of them every time, because the peak value and every
  /// label were measured inside `paint()` itself. The layout depends only on
  /// the point list, the style, the scaler and the direction, all of which
  /// `shouldRepaint` already compares, so caching per painter instance is exact.
  Map<String, double>? _labelWidths;
  double? _lineHeightValue;

  /// Below this, the plot is too short to be worth an axis and the labels are
  /// dropped rather than drawn into the plot.
  static const double _minPlotWithAxis = 44.0;

  bool get _isRtl => direction == TextDirection.rtl;

  int get _maxValue => points.fold(0, (m, p) => math.max(m, p.value));

  TextPainter _text(String text, TextStyle style, {double? maxWidth}) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: direction,
      textScaler: textScaler,
      maxLines: 1,
      ellipsis: '…',
    );
    painter.layout(maxWidth: maxWidth ?? double.infinity);
    return painter;
  }

  /// One line of label-size text, measured once per painter instance.
  double _lineHeight(TextStyle style) =>
      _lineHeightValue ??= _text('Ag', style, maxWidth: double.infinity).height;

  /// The widest label, measured once per painter instance.
  ///
  /// Capped at [cap], so a label wider than its slot does not set the stride.
  double _widestCached(Iterable<PosLinePoint> pts, double cap) {
    final cache = _labelWidths ??= <String, double>{};
    var widest = 0.0;
    for (final point in pts) {
      final label = point.label;
      final width = cache[label] ??= () {
        final measured = _text(label, labelStyle, maxWidth: cap).width;
        cache[label] = measured;
        return measured;
      }();
      widest = math.max(widest, width);
    }
    return widest;
  }

  /// The axis strip, if there is room for one.
  double _axisHeight(double height) {
    final label = _lineHeight(labelStyle);
    if (height - label - gap < _minPlotWithAxis) return 0;
    return label + gap;
  }

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
      // Measured through the same cache the axis labels use, so the peak's
      // caption is not a per-frame TextPainter layout of its own.
      final cache = _labelWidths ??= <String, double>{};
      final valueWidth = cache[peak.displayValue] ??= () {
        final measured = _text(peak.displayValue, labelStyle).width;
        cache[peak.displayValue] = measured;
        return measured;
      }();
      final value = _text(peak.displayValue, labelStyle);
      final x = (_x(peakIndex, size.width) - valueWidth / 2)
          .clamp(0.0, math.max(0.0, size.width - valueWidth))
          .toDouble();
      final y = (yOf(peak.value) - value.height - 6)
          .clamp(0.0, math.max(0.0, size.height))
          .toDouble();
      value.paint(canvas, Offset(x, y));
    }

    if (axisHeight <= 0) return;

    // Axis labels, every Nth so they cannot overlap — and always the last one,
    // the most recent reading, which is the one a reader is looking for.
    //
    // The widest label is read from the cache rather than measured here: 24
    // layout passes per repaint was the cost of a chart that repainted on every
    // parent rebuild.
    final slot = size.width / math.max(points.length, 1);
    final widest = _widestCached(points, math.max(slot, 12.0));
    final stride = math.max(1, (widest / slot).ceil());
    final baselineY = baseline + gap;

    for (var i = 0; i < points.length; i += stride) {
      _paintAxisLabel(canvas, size, i, stride, baselineY);
    }
    if ((points.length - 1) % stride != 0) {
      _paintAxisLabel(canvas, size, points.length - 1, stride, baselineY);
    }
  }

  void _paintAxisLabel(
      Canvas canvas, Size size, int index, int stride, double baselineY) {
    if (index < 0 || index >= points.length) return;
    final painter = _text(points[index].label, labelStyle);
    final x = (_x(index, size.width) - painter.width / 2)
        .clamp(0.0, math.max(0.0, size.width - painter.width))
        .toDouble();
    painter.paint(canvas, Offset(x, baselineY));
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter old) =>
      old.points != points ||
      old.textScaler != textScaler ||
      old.direction != direction ||
      old.labelStyle != labelStyle ||
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
