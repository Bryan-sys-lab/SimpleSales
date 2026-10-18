// The payment-mix card, rendered with its ring.
//
// The chart this card holds was a stack of horizontal bars until it became a
// donut, so what needs proving is the conversion: that every tender still has
// its own colour, its legend row, and its share of the whole — and that the
// figures a manager reads down the column are untouched by the picture above
// them.
//
// One `testWidgets` per (device, scale) tuple, with the loop AROUND the test:
// an overflow is reported once per render object, so a test looping scales
// internally under-reports everything but the first.

import 'package:duka_pos/l10n/generated/app_localizations.dart';
import 'package:duka_pos/screens/analytics_tables.dart';
import 'package:duka_pos/services/analytics.dart';
import 'package:duka_pos/widgets/chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';
import 'package:duka_pos/ui/components/surface.dart';

const List<PaymentMixRow> _rows = <PaymentMixRow>[
  PaymentMixRow(method: 'cash', salesMinor: 400000, transactions: 12),
  PaymentMixRow(method: 'mpesa', salesMinor: 900000, transactions: 41),
  PaymentMixRow(method: 'card', salesMinor: 100000, transactions: 3),
];

const DailyTotals _totals = DailyTotals(
  totalMinor: 1400000,
  profitMinor: 500000,
  transactions: 56,
  averageMinor: 25000,
);

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    await loadAppFonts();
    l10n = await loadL10n();
  });

  testWidgets('every tender gets a slice, a colour and a legend row',
      (tester) async {
    tester.useDevice(Device.small);
    await tester.pumpApp(
      home: const Scaffold(
        body: SingleChildScrollView(
          child: PaymentMixCard(rows: _rows, totals: _totals),
        ),
      ),
    );

    // The ring, carrying one slice per tender with a colour of its own.
    final PosPieChart chart = tester.widget<PosPieChart>(
      find.byType(PosPieChart),
    );
    expect(chart.slices.length, _rows.length);
    final Set<int> colours =
        chart.slices.map((PosPieSlice s) => s.color.toARGB32()).toSet();
    // Two tenders sharing a colour would be two tenders nobody can tell apart
    // in greyscale.
    expect(colours.length, _rows.length);

    // The legend: real text, so it scales and a screen reader can reach it.
    // Appears twice on purpose — once in the ring's legend, once in the exact
    // figures below it — so this asserts presence rather than a count.
    for (final PaymentMixRow row in _rows) {
      expect(find.text(row.label()), findsWidgets);
    }
    tester.expectNoOverflow('payment mix ring and legend');
  });

  testWidgets(
      'the hole carries nothing, because the total is already on the '
      'stat tile above', (tester) async {
    // The total was drawn inside the ring as well as on the stat tile, which
    // meant the owner had two copies of the same number on one screen to
    // reconcile. The ring is the picture; the tile is the figure.
    tester.useDevice(Device.small);
    await tester.pumpApp(
      home: const Scaffold(
        body: SingleChildScrollView(
          child: PaymentMixCard(rows: _rows, totals: _totals),
        ),
      ),
    );

    expect(find.text(l10n.analyticsPaymentMixTotal), findsNothing);
    // And no money in the hole either.
    expect(find.text('KSh 14,000'), findsNothing);
  });

  testWidgets('the ring is enlarged, and there is no card around it',
      (tester) async {
    // Two of the four changes, pinned. The ring was 116px inside a
    // `SurfaceCard`; the box cost a percentage of the width on a small phone
    // and the 116px made the minority arcs illegible.
    tester.useDevice(Device.small);
    await tester.pumpApp(
      home: const Scaffold(
        body: SingleChildScrollView(
          child: PaymentMixCard(rows: _rows, totals: _totals),
        ),
      ),
    );

    final PosPieChart chart = tester.widget(find.byType(PosPieChart));
    expect(chart.size, PaymentMixCard.pieSize);
    expect(chart.size, greaterThan(116),
        reason: 'a sliver arc nobody can land on is the bug');

    // And it is direct content, not a card's child: the boundary box is gone.
    expect(find.byType(SurfaceCard), findsNothing,
        reason: 'a rectangle around an already-legible figure');
  });

  testWidgets('each key line carries the colour of its own arc',
      (tester) async {
    // What makes the ring a KEY rather than a decoration: the swatch beside
    // the tender's name is the colour its arc is drawn in.
    tester.useDevice(Device.small);
    await tester.pumpApp(
      home: const Scaffold(
        body: SingleChildScrollView(
          child: PaymentMixCard(rows: _rows, totals: _totals),
        ),
      ),
    );

    final PosPieChart chart = tester.widget(find.byType(PosPieChart));
    final Set<int> arcColours =
        chart.slices.map((PosPieSlice s) => s.color.toARGB32()).toSet();

    // One coloured swatch per tender, in the arc's own colour. Without it the
    // colour is decorative and the ring cannot be read against the list.
    final Set<int> swatches = tester
        .widgetList<Container>(find.byType(Container))
        .where((Container c) => c.decoration is BoxDecoration)
        .map((Container c) =>
            (c.decoration as BoxDecoration).color?.toARGB32() ?? -1)
        .toSet();
    expect(swatches.intersection(arcColours), arcColours,
        reason: 'a slice with no matching swatch is a legend-less colour');
  });
  testWidgets('the exact figures survive below the picture', (tester) async {
    tester.useDevice(Device.small);
    await tester.pumpApp(
      home: const Scaffold(
        body: SingleChildScrollView(
          child: PaymentMixCard(rows: _rows, totals: _totals),
        ),
      ),
    );

    // The rows are keys and values: "M-Pesa  64%" then the money. The share
    // moved INTO the key line rather than sitting as its own column, so a
    // finder has to look for the line rather than for a bare percentage.
    expect(find.text('M-Pesa  64%'), findsOneWidget); // 900k of 1400k
    expect(find.text('Cash  29%'), findsOneWidget); // 400k of 1400k
    expect(find.text('Card  7%'), findsOneWidget); // 100k of 1400k

    // And the exact money, which a ring alone can never be read to. It appears
    // twice on purpose — once in the money column of the keys, once in the
    // ring's own spoken form — so this asserts presence rather than a count.
    expect(find.text('KSh 4,000'), findsWidgets);
    expect(find.text('KSh 9,000'), findsWidgets);
    expect(find.text('KSh 1,000'), findsWidgets);
  });

  testWidgets('an empty period says so rather than drawing an empty ring',
      (tester) async {
    tester.useDevice(Device.small);
    await tester.pumpApp(
      home: const Scaffold(
        body: SingleChildScrollView(
          child: PaymentMixCard(
              rows: <PaymentMixRow>[], totals: DailyTotals.empty),
        ),
      ),
    );

    expect(find.text(l10n.analyticsNothingTaken), findsOneWidget);
    expect(find.byType(PosPieChart), findsNothing);
  });

  for (final Device device in <Device>[Device.compact, Device.small]) {
    for (final double scale in <double>[1.0, 2.0]) {
      for (final Brightness brightness in <Brightness>[
        Brightness.light,
        Brightness.dark,
      ]) {
        // The system setting decides the theme (`ThemeMode.system`), so the
        // brightness axis here is the one a shopkeeper's OS actually controls.
        final String where = '${device.name} x$scale $brightness';
        testWidgets('fits $where', (tester) async {
          tester.useDevice(device);
          await tester.pumpApp(
            home: const Scaffold(
              body: SingleChildScrollView(
                child: PaymentMixCard(rows: _rows, totals: _totals),
              ),
            ),
            textScaler: TextScaler.linear(scale),
            brightness: brightness,
          );
          tester.expectNoOverflow('payment mix $where');
        });
      }
    }
  }
}
