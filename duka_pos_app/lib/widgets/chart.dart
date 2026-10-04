import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Which way the bars grow.
enum PosChartAxis {
  /// Bars grow upward from a baseline — time on the horizontal axis.
  ///
  /// For a series the eye reads as a *sequence* (hours of a day, days of a
  /// month), where position along the axis carries the meaning.
  vertical,

  /// Bars grow sideways, names down the side — categories whose labels are
  /// words.
  ///
  /// A product name rotated or ellipsised under a vertical bar is unreadable;
  /// laid out horizontally it gets the whole left column to itself.
  horizontal,
}

/// One bar. [value] is the number the bar is drawn from; [valueLabel] is what
/// the user is told it is, when the raw figure is not what should be shown.
@immutable
class PosChartBar {
  const PosChartBar({
    required this.label,
    required this.value,
    this.valueLabel,
  });

  /// The axis label — an hour, a date, a product name.
  final String label;

  /// Height/length of the bar.
  final int value;

  /// The pre-formatted figure, e.g. `KSh 4,200`. Falls back to the raw value,
  /// which is what a unit count wants.
  final String? valueLabel;

  String get displayValue => valueLabel ?? '$value';
}

/// A dependency-free bar chart drawn with a [CustomPainter].
///
/// The app has no charting dependency, and adding one for two bar charts would
/// put a transitive package tree and a version pin between an owner and their
/// own takings. This paints what is needed and nothing else.
///
/// ## Accessibility
///
/// A painted chart is a canvas of coloured rectangles: it has no text nodes, so
/// a screen reader announces nothing at all for it. Every chart therefore
/// carries the *same* figures as a sentence on a [Semantics] node — the peak,
/// the total, how many periods had sales — and the painted text inside is
/// excluded so the two are not read out twice. Callers build that sentence
/// (see `describeDailyBuckets` in `services/analytics.dart`); if they do not,
/// a generic description of the series is used rather than silence.
///
/// ## Text scaling
///
/// Nothing here shrinks text to make it fit. Text scaling is honoured at full
/// size, and a label that does not fit is either truncated with an ellipsis or
/// — for the axis on a vertical chart, where a truncated date is worse than no
/// date — dropped entirely, with the value still present in the semantics.
/// That is also why neither orientation can overflow: heights are derived from
/// the *scaled* text metrics, and the painter is free to paint outside its box
/// without producing a layout overflow, because there is no layout to overflow.
class SimplePosChart extends StatelessWidget {
  const SimplePosChart({
    super.key,
    required this.title,
    required this.bars,
    this.semanticsLabel,
    this.axis = PosChartAxis.vertical,
    this.height = 148,
    this.emphasis,
  });

  /// Heading above the chart. Rendered as text, so it is real content rather
  /// than something painted.
  final String title;

  final List<PosChartBar> bars;

  /// The non-visual equivalent. When null a short generic description is built
  /// from [bars] — never an empty label, because an unlabelled chart is
  /// indistinguishable from a chart that failed to load.
  final String? semanticsLabel;

  final PosChartAxis axis;

  /// Plot height for [PosChartAxis.vertical]. Ignored for
  /// [PosChartAxis.horizontal], whose height follows its row count.
  final double height;

  /// Optional line under the heading — "Busiest at 6pm", a period caption.
  final String? emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodySmall ??
        const TextStyle(fontSize: 12, color: DukaColors.mutedInk);
    final valueStyle = (theme.textTheme.bodyMedium ??
            const TextStyle(fontSize: 14, color: DukaColors.ink))
        .copyWith(fontWeight: FontWeight.w600);

    return Semantics(
      label: semanticsLabel ?? _fallbackSemantics(),
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          if (emphasis != null) ...[
            const SizedBox(height: 2),
            Text(emphasis!, style: labelStyle),
          ],
          const SizedBox(height: DukaSpacing.sm),
          if (bars.isEmpty)
            Text('Nothing to show yet.', style: labelStyle)
          else
            ExcludeSemantics(
              child: _ChartCanvas(
                bars: bars,
                axis: axis,
                height: height,
                labelStyle: labelStyle,
                valueStyle: valueStyle,
                direction: Directionality.of(context),
              ),
            ),
        ],
      ),
    );
  }

  String _fallbackSemantics() {
    if (bars.isEmpty) return '$title. No values.';
    final peak = bars.reduce((a, b) => b.value > a.value ? b : a);
    return '$title. ${bars.length} values. '
        'Highest is ${peak.label} at ${peak.displayValue}.';
  }
}

/// The painted part. Kept as its own widget so the [Semantics] wrapper above
/// can exclude everything inside it in one place.
class _ChartCanvas extends StatelessWidget {
  const _ChartCanvas({
    required this.bars,
    required this.axis,
    required this.height,
    required this.labelStyle,
    required this.valueStyle,
    required this.direction,
  });

  final List<PosChartBar> bars;
  final PosChartAxis axis;
  final double height;
  final TextStyle labelStyle;
  final TextStyle valueStyle;
  final TextDirection direction;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : constraints.biggest.width;
        final painter = _ChartPainter(
          bars: bars,
          axis: axis,
          labelStyle: labelStyle,
          valueStyle: valueStyle,
          direction: direction,
          textScaler: scaler,
          plotHeight: height,
        );
        return SizedBox(
          width: width,
          height: axis == PosChartAxis.vertical
              ? height
              : painter.horizontalHeight(width),
          child: CustomPaint(painter: painter),
        );
      },
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.bars,
    required this.axis,
    required this.labelStyle,
    required this.valueStyle,
    required this.direction,
    required this.textScaler,
    required this.plotHeight,
  });

  final List<PosChartBar> bars;
  final PosChartAxis axis;
  final TextStyle labelStyle;
  final TextStyle valueStyle;
  final TextDirection direction;
  final TextScaler textScaler;
  final double plotHeight;

  /// Breathing room under/around the plot.
  static const double _gap = DukaSpacing.sm;

  /// The least a bar may be worth on screen.
  ///
  /// A zero-value bar still draws, as a stub: "nothing sold at 03:00" is a
  /// fact the chart is being asked to show, and a gap would be indistinguishable
  /// from "the hour was not counted".
  static const double _minBar = 2.0;

  /// Below this, the plot is too short to be worth an axis and the labels are
  /// dropped rather than drawn into the bars.
  static const double _minPlotWithAxis = 44.0;

  /// Share of the width given to names on a horizontal chart.
  static const double _labelColumnFraction = 0.42;
  static const double _minLabelColumn = 40.0;

  bool get _isRtl => direction == TextDirection.rtl;

  int get _maxValue => bars.fold(0, (m, b) => math.max(m, b.value));

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

  /// Height of one line of [style] *after* the user's text scale is applied.
  double _lineHeight(TextStyle style) =>
      _text('Ag', style, maxWidth: double.infinity).height;

  /// Widest of [texts] laid out at [style], truncated to [cap].
  double _widest(Iterable<String> texts, TextStyle style, double cap) {
    var widest = 0.0;
    for (final text in texts) {
      final painter = _text(text, style, maxWidth: cap);
      widest = math.max(widest, painter.width);
    }
    return widest;
  }

  /// Whether a vertical chart has room for an axis *under* its bars, and how
  /// much of the height it takes.
  double verticalAxisHeight(double height) {
    final label = _lineHeight(labelStyle);
    if (height - label - _gap < _minPlotWithAxis) return 0;
    return label + _gap;
  }

  /// Total height a vertical chart occupies: its plot plus the axis strip, if
  /// the axis survived the "does it fit" check.
  double verticalHeight(double plotOnlyHeight) => plotOnlyHeight;

  /// One row per bar, tall enough for the scaled text in it.
  double horizontalHeight(double width) {
    final label = _lineHeight(labelStyle);
    final value = _lineHeight(valueStyle);
    final row = math.max(math.max(label, value) + _gap * 2, 28.0);
    return row * bars.length;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty || size.width <= 0 || size.height <= 0) return;
    if (axis == PosChartAxis.vertical) {
      _paintVertical(canvas, size);
    } else {
      _paintHorizontal(canvas, size);
    }
  }

  void _paintVertical(Canvas canvas, Size size) {
    final slot = size.width / bars.length;
    final barWidth = _barWidth(slot);
    final axisHeight = verticalAxisHeight(size.height);
    final plotHeight = size.height - axisHeight;
    final maxValue = math.max(_maxValue, 1);
    final baseline = size.height - axisHeight;

    final fill = Paint()..color = DukaColors.primary;
    final track = Paint()..color = DukaColors.surfaceWarm;

    // Every slot gets a full-height track, so the shape of the day is readable
    // even before any value is compared.
    for (var i = 0; i < bars.length; i++) {
      final left = _slotLeft(i, slot, size.width);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left + (slot - barWidth) / 2, 0, barWidth, plotHeight),
          const Radius.circular(3),
        ),
        track,
      );
    }

    var peakIndex = 0;
    for (var i = 1; i < bars.length; i++) {
      if (bars[i].value > bars[peakIndex].value) peakIndex = i;
    }

    for (var i = 0; i < bars.length; i++) {
      final bar = bars[i];
      final drawn = bar.value <= 0
          ? _minBar
          : math.max(_minBar, (bar.value / maxValue) * plotHeight);
      final left = _slotLeft(i, slot, size.width);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            left + (slot - barWidth) / 2,
            baseline - drawn,
            barWidth,
            drawn,
          ),
          const Radius.circular(3),
        ),
        fill,
      );
    }

    if (axisHeight > 0) {
      _paintVerticalAxis(canvas, size, slot, baseline, peakIndex, plotHeight);
    }
  }

  /// Left edge of slot [index], mirrored in RTL so the series still reads
  /// start-to-finish.
  double _slotLeft(int index, double slot, double width) =>
      _isRtl ? width - (index + 1) * slot : index * slot;

  void _paintVerticalAxis(Canvas canvas, Size size, double slot,
      double baseline, int peakIndex, double plotHeight) {
    final cap = math.max(slot, 12.0);
    final widest = _widest(bars.map((b) => b.label), labelStyle, cap);
    // Draw every Nth label so they cannot overlap, and always the last one —
    // the most recent day is the one a reader is looking for.
    final stride = math.max(1, (widest / slot).ceil());
    final baselineY = baseline + _gap;

    void drawLabel(int index) {
      if (index < 0 || index >= bars.length) return;
      final painter = _text(bars[index].label, labelStyle, maxWidth: slot);
      final left = _slotLeft(index, slot, size.width);
      painter.paint(canvas, Offset(left, baselineY));
    }

    for (var i = 0; i < bars.length; i += stride) {
      drawLabel(i);
    }
    if ((bars.length - 1) % stride != 0) drawLabel(bars.length - 1);

    // The peak's figure, in text. A colour difference is the only other cue
    // that one bar matters, and colour alone is not a signal a low-vision or
    // colour-blind reader can use.
    final peak = bars[peakIndex];
    if (peak.value > 0) {
      final value = _text(peak.displayValue, labelStyle);
      final drawn = math.max(
          _minBar, (peak.value / math.max(_maxValue, 1)) * plotHeight);
      final barLeft =
          _slotLeft(peakIndex, slot, size.width) + (slot - _barWidth(slot)) / 2;
      final x = (barLeft + (_barWidth(slot) - value.width) / 2)
          .clamp(0.0, math.max(0.0, size.width - value.width))
          .toDouble();
      final y = (baseline - drawn - value.height - 2)
          .clamp(0.0, math.max(0.0, size.height))
          .toDouble();
      value.paint(canvas, Offset(x, y));
    }
  }

  double _barWidth(double slot) => (slot * 0.62).clamp(_minBar, 28.0).toDouble();

  void _paintHorizontal(Canvas canvas, Size size) {
    final labelColumn = (size.width * _labelColumnFraction)
        .clamp(_minLabelColumn, size.width * 0.6)
        .toDouble();
    final barGap = _gap * 2;

    final widestValue =
        _widest(bars.map((b) => b.displayValue), valueStyle, size.width);
    final minBarRoom = 32.0;
    final valueRoom = (size.width - labelColumn - barGap - minBarRoom) >=
            widestValue + barGap
        ? widestValue + barGap
        : 0.0;

    final trackStart = _isRtl
        ? size.width - labelColumn - barGap - valueRoom
        : labelColumn + barGap;
    final trackEnd = _isRtl ? labelColumn + barGap : size.width - valueRoom;
    final trackWidth = math.max(0.0, trackEnd - trackStart);

    final rowHeight = size.height / bars.length;
    final barHeight = (rowHeight * 0.56).clamp(4.0, 22.0);
    final maxValue = math.max(_maxValue, 1);

    final fill = Paint()..color = DukaColors.primary;
    final track = Paint()..color = DukaColors.surfaceWarm;

    for (var i = 0; i < bars.length; i++) {
      final bar = bars[i];
      final top = i * rowHeight;
      final centreY = top + rowHeight / 2;
      final y = centreY - barHeight / 2;

      // Name, ellipsised to its column rather than scaled to fit: a product
      // name is what identifies the row, and shrinking it until it fits makes
      // two different names indistinguishable. The full text is still in the
      // chart's semantics label.
      final name = _text(bar.label, labelStyle, maxWidth: labelColumn);
      final nameX = _isRtl ? size.width - name.width : 0.0;
      name.paint(canvas, Offset(nameX, centreY - name.height / 2));

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(trackStart, y, trackWidth, barHeight),
          const Radius.circular(3),
        ),
        track,
      );

      final length = bar.value <= 0
          ? _minBar
          : math.max(_minBar, (bar.value / maxValue) * trackWidth);
      final lengthClamped = math.min(length, trackWidth);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(trackStart, y, lengthClamped, barHeight),
          const Radius.circular(3),
        ),
        fill,
      );

      if (valueRoom > 0) {
        final value = _text(bar.displayValue, valueStyle, maxWidth: valueRoom);
        final valueX = _isRtl ? trackStart - _gap - value.width : trackEnd + _gap;
        value.paint(canvas, Offset(valueX, centreY - value.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) =>
      old.bars != bars ||
      old.axis != axis ||
      old.textScaler != textScaler ||
      old.direction != direction ||
      old.labelStyle != labelStyle ||
      old.valueStyle != valueStyle;
}
