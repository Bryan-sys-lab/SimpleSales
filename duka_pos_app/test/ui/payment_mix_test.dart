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
      expect(find.text(row.label), findsWidgets);
    }
    tester.expectNoOverflow('payment mix ring and legend');
  });

  testWidgets('the whole is stated in the hole', (tester) async {
    tester.useDevice(Device.small);
    await tester.pumpApp(
      home: const Scaffold(
        body: SingleChildScrollView(
          child: PaymentMixCard(rows: _rows, totals: _totals),
        ),
      ),
    );

    expect(find.text(l10n.analyticsPaymentMixTotal), findsOneWidget);
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

    // A chart alone cannot be read to the shilling: the rows underneath carry
    // the figures, and each states its share of the whole.
    expect(find.text('64%'), findsOneWidget); // mpesa, 900k of 1400k
    expect(find.text('29%'), findsOneWidget); // cash, 400k of 1400k
    expect(find.text('7%'), findsOneWidget); // card, 100k of 1400k
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
