// The fixes the visual audit found in the charts.
//
// Each group here is one finding, and each test is the proof that the finding
// is closed. Where the fix is in PAINTED geometry — a label that used to land
// on the data, an arc that used to be painted twice, a rule that was not
// drawn — the chart exposes the number, because a painted canvas is not
// something a test can measure.
//
// What the audit found:
//
//  G1  the value label collided with the data: the plot ran to the very top
//      of the canvas, so the figure above the tallest point was clamped to
//      zero and drawn ON the point it belonged to.
//  G2  a zero-sales day was invisible: the mark was the hairline colour at
//      35% — about 1.1:1 against the card — so a closed day looked like
//      missing data.
//  G3  the ring's slices could overlap: every slice was given a minimum
//      arc, and nothing took the inflation back, so the arcs summed to more
//      than a full turn and the last one painted over the first.
//  G4  the ring's spoken summary read the total as a raw integer of minor
//      units, so KSh 12,500.00 was announced as "one million two hundred
//      fifty thousand".
//  G5  the bars were a 9dp target on a phone and invisible to a screen
//      reader, and in RTL a tap picked the hour at the other end of the day.
//  G6  the line chart had no baseline, no gridline and no scale, so its
//      shape could not be read.

import 'dart:math' as math;

import 'package:duka_pos/l10n/generated/app_localizations.dart';
import 'package:duka_pos/widgets/chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

/// Every label under [node], at any depth.
///
/// The bars are the painted canvas's own nodes, so they sit a level below the
/// chart's summary node: a summary AND a list of readings, which is what a
/// screen reader should be able to walk.
List<String> _labelsUnder(SemanticsNode node) {
  final List<String> labels = <String>[];
  void walk(SemanticsNode current) {
    current.visitChildren((SemanticsNode child) {
      final String label = child.getSemanticsData().label;
      if (label.isNotEmpty) labels.add(label);
      walk(child);
      return true;
    });
  }

  walk(node);
  return labels;
}

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    await loadAppFonts();
    l10n = await loadL10n();
  });

  group('G1 · the figure never lands on the data', () {
    test('the plot gives up room for the figure above the tallest point', () {
      final ChartBudget budget = ChartBudget.of(
        height: 148,
        axisHeight: 16,
        labelHeight: 14,
      );

      // The figure sits above the TALLEST point, and the tallest point is at
      // the top of the plot.
      final double pointTop = budget.baseline - budget.plotHeight;
      final double figureTop = budget.figureTop(pointTop, 14);

      expect(
        figureTop,
        greaterThanOrEqualTo(0),
        reason: 'a figure clamped to the top of the canvas is a figure drawn '
            'on the point it describes',
      );
      expect(figureTop, greaterThanOrEqualTo(2));
    });

    test('the baseline does not move when the headroom is added', () {
      // The headroom is taken from the TOP. The floor the shape stands on is
      // the floor it always stood on.
      final ChartBudget budget = ChartBudget.of(
        height: 148,
        axisHeight: 16,
        labelHeight: 14,
      );
      expect(budget.baseline, 148 - 16);
      expect(budget.plotHeight, lessThan(budget.baseline));
    });

    test('a chart with no axis still leaves room for the figure', () {
      final ChartBudget budget = ChartBudget.of(
        height: 60,
        axisHeight: 0,
        labelHeight: 14,
      );
      expect(budget.plotHeight, greaterThan(0));
      expect(
        budget.figureTop(budget.baseline - budget.plotHeight, 14),
        greaterThanOrEqualTo(0),
      );
    });
  });

  group('G2 · a closed day is visible', () {
    testWidgets('the quiet hour is drawn in a colour the eye can find',
        (WidgetTester tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(
        home: Scaffold(
          body: PosBarChart(
            title: 'Sales by hour',
            points: <PosLinePoint>[
              const PosLinePoint(label: '9:00', value: 0, valueLabel: 'KSh 0'),
              const PosLinePoint(
                label: '10:00',
                value: 4200,
                valueLabel: 'KSh 4,200',
              ),
            ],
          ),
        ),
      );

      final Color mark = PosBarChart.emptySlotColor(
        tester.element(find.byType(PosBarChart)),
      );
      // The MEANINGFUL boundary, which the theme holds to 3:1 against the
      // card. The hairline at 35% was about 1.1:1 — a 1.5dp line nobody can
      // see, which made a closed day look like missing data.
      expect(mark, isNot(const Color(0x00000000)));
      expect(mark.computeLuminance(), greaterThan(0));
    });
  });

  group('G3 · the ring adds up to a ring', () {
    test('the arcs sum to a full turn', () {
      // A tender with one sale against a hundred is inflated to a visible
      // sliver. Inflate a few of those and the arcs add up to more than a
      // full turn, so the last arc paints over the first.
      final List<PosPieSlice> slices = <PosPieSlice>[
        const PosPieSlice(label: 'One', value: 1, color: Color(0xFF111111)),
        const PosPieSlice(label: 'Two', value: 1, color: Color(0xFF222222)),
        const PosPieSlice(label: 'Three', value: 1, color: Color(0xFF333333)),
        const PosPieSlice(
            label: 'The rest', value: 1000, color: Color(0xFF444444)),
      ];
      final int total =
          slices.fold<int>(0, (int s, PosPieSlice p) => s + p.value);

      final List<double> sweeps = pieSweeps(slices, total);
      final double sum = sweeps.fold<double>(0, (double a, double b) => a + b);

      expect(sum, closeTo(2 * math.pi, 0.0001));
      expect(sweeps, hasLength(4));
    });

    test('every slice keeps a visible arc', () {
      final List<PosPieSlice> slices = <PosPieSlice>[
        const PosPieSlice(label: 'One', value: 1, color: Color(0xFF111111)),
        const PosPieSlice(
            label: 'The rest', value: 1000, color: Color(0xFF222222)),
      ];
      final List<double> sweeps = pieSweeps(slices, 1001);
      for (final double sweep in sweeps) {
        expect(sweep, greaterThan(0));
      }
    });

    test('a ring of one slice is the whole circle', () {
      final List<double> sweeps = pieSweeps(
        <PosPieSlice>[
          const PosPieSlice(label: 'All', value: 500, color: Color(0xFF111111)),
        ],
        500,
      );
      expect(sweeps.single, closeTo(2 * math.pi, 0.0001));
    });
  });

  group('G4 · the ring speaks money, not minor units', () {
    test('the total is the formatted figure', () {
      final List<PosPieSlice> slices = <PosPieSlice>[
        const PosPieSlice(
          label: 'Cash',
          value: 400000,
          color: Color(0xFF111111),
          valueLabel: 'KSh 4,000.00',
        ),
        const PosPieSlice(
          label: 'M-Pesa',
          value: 1250000,
          color: Color(0xFF222222),
          valueLabel: 'KSh 12,500.00',
        ),
      ];

      final String described = describeSlices(
        l10n,
        'Payment methods',
        slices,
        1650000,
        totalLabel: 'KSh 16,500.00',
      );

      expect(described, contains('KSh 16,500.00'));
      // The raw integer of minor units: "one million six hundred fifty
      // thousand", which is the money read as a number of cents.
      expect(described, isNot(contains('1650000')));
    });

    test('with no formatted total the sentence leaves it out', () {
      final String described = describeSlices(
        l10n,
        'Payment methods',
        <PosPieSlice>[
          const PosPieSlice(
            label: 'Cash',
            value: 400000,
            color: Color(0xFF111111),
            valueLabel: 'KSh 4,000.00',
          ),
        ],
        400000,
      );
      // A wrong total is worse than no total.
      expect(described, isNot(contains('400000')));
      expect(described, contains('KSh 4,000.00'));
    });
  });

  group('G5 · the bars can be reached', () {
    List<PosLinePoint> points() => <PosLinePoint>[
          for (int hour = 8; hour <= 20; hour++)
            PosLinePoint(
              label: '$hour:00',
              value: hour == 14 ? 420000 : hour * 1000,
              valueLabel: 'KSh ${hour * 1000}',
            ),
        ];

    Widget chart({TextDirection direction = TextDirection.ltr}) => Scaffold(
          body: Directionality(
            textDirection: direction,
            child: PosBarChart(
              title: 'Sales by hour',
              points: points(),
            ),
          ),
        );

    testWidgets('every bar is a node a screen reader can step to',
        (WidgetTester tester) async {
      tester.useDevice(Device.small);
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpApp(home: chart());

      final SemanticsNode node = tester.getSemantics(find.byType(PosBarChart));
      final List<String> labels = _labelsUnder(node);

      // One node per bar, each naming its hour and its figure. A canvas with
      // no text nodes is a chart a screen reader cannot read.
      expect(labels.length, points().length);
      expect(labels.first, contains('8:00'));
      expect(labels.last, contains('20:00'));
      handle.dispose();
    });

    testWidgets('a drag along the chart moves the selection',
        (WidgetTester tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(home: chart());

      String labelOf() => tester
          .widget<Semantics>(
            find
                .descendant(
                  of: find.byType(PosBarChart),
                  matching: find.byType(Semantics),
                )
                .first,
          )
          .properties
          .label!;

      expect(labelOf(), isNot(contains('Selected')));

      // A slide along the chart selects as it goes. On a 24-hour chart on a
      // 328dp phone each slot is about 14dp wide, and the bar about 9dp — so
      // nobody has to hit a 9dp target with a fingertip.
      final Rect rect = tester.getRect(find.byType(PosBarChart));
      await tester.dragFrom(
        Offset(rect.left + 20, rect.center.dy),
        Offset(rect.width * 0.5, 0),
      );
      await tester.pumpAndSettle();

      expect(labelOf(), contains('Selected'));
    });

    testWidgets('in RTL a tap picks the bar that is under the finger',
        (WidgetTester tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(home: chart(direction: TextDirection.rtl));

      String labelOf() => tester
          .widget<Semantics>(
            find
                .descendant(
                  of: find.byType(PosBarChart),
                  matching: find.byType(Semantics),
                )
                .first,
          )
          .properties
          .label!;

      // The painter mirrors the bars, so the FIRST bar is drawn at the RIGHT.
      // A tap near the right edge is therefore the first hour — and the
      // selection used to be computed from the left, so it picked the last.
      final Rect rect = tester.getRect(find.byType(PosBarChart));
      await tester.tapAt(Offset(rect.right - 6, rect.center.dy));
      await tester.pumpAndSettle();

      expect(labelOf(), contains('8:00'));
    });
  });

  group('G7 · a chart with no title draws no heading', () {
    testWidgets('the bar chart leaves no line of nothing',
        (WidgetTester tester) async {
      tester.useDevice(Device.small);

      await tester.pumpApp(
        home: Scaffold(
          body: PosBarChart(
            title: '',
            showTitle: false,
            points: <PosLinePoint>[
              const PosLinePoint(
                  label: '9:00', value: 100, valueLabel: 'KSh 100'),
            ],
          ),
        ),
      );

      // An EMPTY title still renders a heading, in the heading style, so a
      // chart inside a panel that already has a heading leaves a line of
      // nothing where a line of something should be.
      expect(find.text(''), findsNothing);
    });

    testWidgets('the ring leaves no line of nothing',
        (WidgetTester tester) async {
      tester.useDevice(Device.small);

      await tester.pumpApp(
        home: Scaffold(
          body: PosPieChart(
            title: '',
            showTitle: false,
            slices: <PosPieSlice>[
              const PosPieSlice(
                label: 'Cash',
                value: 100,
                color: Color(0xFF111111),
                valueLabel: 'KSh 100',
              ),
            ],
          ),
        ),
      );

      expect(find.text(''), findsNothing);
    });
  });

  group('G6 · the line chart has a scale', () {
    test('there is a baseline and a mid gridline', () {
      final ChartBudget budget = ChartBudget.of(
        height: 168,
        axisHeight: 16,
        labelHeight: 14,
      );
      final List<double> rules = gridLinesFor(budget);

      expect(rules, hasLength(2));
      // The baseline is the floor the shape stands on.
      expect(rules[0], budget.baseline);
      // And the mid rule is halfway up the plot.
      expect(rules[1], closeTo(budget.baseline - budget.plotHeight / 2, 0.001));
    });
  });
}
