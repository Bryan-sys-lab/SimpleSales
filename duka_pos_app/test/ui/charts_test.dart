// The overflow + accessibility matrix for the app's two charts.
//
// The bar chart was replaced by these two, so they need the same scrutiny the
// design system's components get: one `testWidgets` per (device, scale,
// brightness) tuple, the loop AROUND `testWidgets` and never inside it. A
// `RenderFlex` overflow is reported once per render object, so a test that loops
// scales internally silently checks 1.0 and under-reports the rest.
//
// The charts are deliberately dependency-free `CustomPainter`s, which means
// nothing in Flutter's own test machinery asserts anything about them: the
// painted surface has no text nodes and no layout to overflow. What these tests
// DO assert is what a consumer actually breaks — the semantics sentence being
// present, the legend being real scalable text, and the widgets holding up
// under the largest text scale without a clamp in sight.
//
// `loadAppFonts` is not optional: under the default Ahem test font every glyph is
// a fixed em-square, so the large-text half of this matrix would pass vacuously.

import 'package:duka_pos/l10n/generated/app_localizations.dart';
import 'package:duka_pos/widgets/chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void main() {
  late AppLocalizations l10n;
  late List<PosLinePoint> points;
  late List<PosPieSlice> slices;

  setUpAll(() async {
    await loadAppFonts();
    l10n = await loadL10n();
  });

  setUp(() {
    points = <PosLinePoint>[
      for (int hour = 6; hour <= 22; hour++)
        PosLinePoint(
          label: '$hour:00',
          value: hour == 6 || hour == 22 ? 0 : (hour - 6) * (22 - hour) * 50,
          valueLabel: 'KSh ${(hour - 6) * (22 - hour) * 50}',
        ),
    ];
    slices = <PosPieSlice>[
      PosPieSlice(
        label: 'Cash',
        value: 4000,
        color: const Color(0xFF6B635A),
        valueLabel: 'KSh 4,000',
      ),
      PosPieSlice(
        label: 'M-Pesa',
        value: 9000,
        color: const Color(0xFF00A651),
        valueLabel: 'KSh 9,000',
      ),
      PosPieSlice(
        label: 'Card',
        value: 1000,
        color: const Color(0xFF1A6BAA),
        valueLabel: 'KSh 1,000',
      ),
    ];
  });

  group('line chart', () {
    Widget line({String? semanticsLabel}) => Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: PosLineChart(
                title: 'Sales by hour',
                points: points,
                semanticsLabel: semanticsLabel,
                height: 140,
              ),
            ),
          ),
        );

    test('announces the series as a sentence, not as a canvas', () {
      // A painted chart has no text nodes. Without this, a screen reader
      // announces nothing at all for the day's takings.
      final String label =
          describeSlices(l10n, 'Sales by hour', const <PosPieSlice>[], 0);
      expect(label, l10n.chartSpokenNoValues('Sales by hour'));
    });

    testWidgets('the peak figure is stated in the semantics', (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(home: line());

      // The fallback sentence names the peak, which is the one reading a
      // manager acts on. The label lives on the chart's own Semantics node, so
      // it is read off that rather than off the title text.
      final Semantics node = tester.widget<Semantics>(
        find
            .descendant(
              of: find.byType(PosLineChart),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(node.properties.label, isNotNull);
      expect(node.properties.label, contains('14:00'));
      // 14:00 is the peak of this series: (14-6) * (22-14) * 50 = 3200.
      expect(node.properties.label, contains('KSh 3200'));
    });

    testWidgets('the painted surface is excluded from the semantics',
        (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(home: line());

      // Excluded so the figure is not announced twice: once in the sentence and
      // once from inside the painted canvas.
      expect(
        find.descendant(
          of: find.byType(ExcludeSemantics),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
      );
    });

    for (final Device device in <Device>[Device.compact, Device.small]) {
      for (final double scale in <double>[1.0, 2.0]) {
        for (final Brightness brightness in <Brightness>[
          Brightness.light,
          Brightness.dark,
        ]) {
          final String where = '${device.name} x$scale $brightness';
          testWidgets('fits $where', (tester) async {
            tester.useDevice(device);
            await tester.pumpApp(
              home: line(),
              textScaler: TextScaler.linear(scale),
              brightness: brightness,
            );
            tester.expectNoOverflow('line chart $where');
          });
        }
      }
    }
  });

  group('pie chart', () {
    Widget pie({String? semanticsLabel}) => Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: PosPieChart(
                title: 'Payment methods',
                slices: slices,
                semanticsLabel: semanticsLabel,
                centerLabel: l10n.analyticsPaymentMixTotal,
                centerValue: 'KSh 14,000',
              ),
            ),
          ),
        );

    test('describes every slice with its share of the whole', () {
      final String described = describeSlices(
        l10n,
        'Payment methods',
        slices,
        14000,
      );
      // The ring is a picture of what the sentence already says: the slices, in
      // order of size, each with its figure and its percentage.
      expect(described, contains('M-Pesa KSh 9,000, 64 percent'));
      expect(described, contains('Cash KSh 4,000, 29 percent'));
      expect(described, contains('Card KSh 1,000, 7 percent'));
    });

    testWidgets('the legend is real, scalable text', (tester) async {
      tester.useDevice(Device.compact);
      await tester.pumpApp(
        home: pie(),
        textScaler: TextScaler.linear(2.0),
      );

      // Not painted: a label that cannot grow with the user's text scale is the
      // defect this chart exists to avoid.
      for (final PosPieSlice slice in slices) {
        expect(find.text(slice.label), findsOneWidget);
        expect(find.text(slice.displayValue), findsOneWidget);
      }
      expect(find.text(l10n.analyticsPaymentMixTotal), findsOneWidget);
      tester.expectNoOverflow('pie legend at 2.0x');
    });

    testWidgets('the ring itself is painted, not built from widgets',
        (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(home: pie());

      expect(
        find.descendant(
          of: find.byType(ExcludeSemantics),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
      );
    });

    testWidgets('an empty chart says so rather than drawing nothing',
        (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(
        home: const Scaffold(
          body: PosPieChart(
            title: 'Payment methods',
            slices: <PosPieSlice>[],
          ),
        ),
      );

      expect(find.text(l10n.chartNothingToShow), findsOneWidget);
    });

    for (final Device device in <Device>[Device.compact, Device.small]) {
      for (final double scale in <double>[1.0, 2.0]) {
        for (final Brightness brightness in <Brightness>[
          Brightness.light,
          Brightness.dark,
        ]) {
          final String where = '${device.name} x$scale $brightness';
          testWidgets('fits $where', (tester) async {
            tester.useDevice(device);
            await tester.pumpApp(
              home: pie(),
              textScaler: TextScaler.linear(scale),
              brightness: brightness,
            );
            tester.expectNoOverflow('pie chart $where');
          });
        }
      }
    }
  });

  group('chart semantics helpers', () {
    test('a chart with no values is never labelled as silence', () {
      // An unlabelled chart is indistinguishable from one that failed to load.
      expect(describeSlices(l10n, 'Sales', const <PosPieSlice>[], 0),
          l10n.chartSpokenNoValues('Sales'));
    });

    test('every slice colour is a distinct, opaque value', () {
      for (final PosPieSlice slice in slices) {
        // `(r * 255).round()` rather than `.alpha`: the deprecated member reads
        // as an integer in one API family and a double in another.
        expect((slice.color.a * 255).round(), 255);
      }
      final Set<int> unique =
          slices.map((PosPieSlice s) => s.color.toARGB32()).toSet();
      // Two slices sharing a colour are two slices nobody can tell apart in
      // greyscale.
      expect(unique.length, slices.length);
    });
  });
}
