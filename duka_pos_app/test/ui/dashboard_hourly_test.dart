// The dashboard's sales-by-hour chart, in the real screen's own widget.
//
// This chart was the one on the screenshotted dashboard, and it is the chart the
// bar-to-line conversion was asked for. What needs proving is that the LINE
// actually replaces the bars in place — that the widget the dashboard screen
// builds still renders, still states the peak, and still survives the largest
// text scale without a clamp.

import 'package:duka_pos/l10n/generated/app_localizations.dart';
import 'package:duka_pos/screens/dashboard_sections.dart';
import 'package:duka_pos/services/analytics.dart';
import 'package:duka_pos/widgets/chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

/// A trading day: quiet at opening, a lunch peak, an evening peak.
List<TimeBucket> _day() => <TimeBucket>[
      const TimeBucket(hour: 7, salesMinor: 0, profitMinor: 0, transactions: 0),
      const TimeBucket(
          hour: 12, salesMinor: 1200000, profitMinor: 500000, transactions: 22),
      const TimeBucket(
          hour: 18, salesMinor: 1850000, profitMinor: 700000, transactions: 34),
      const TimeBucket(
          hour: 20, salesMinor: 900000, profitMinor: 400000, transactions: 15),
      const TimeBucket(
          hour: 22, salesMinor: 0, profitMinor: 0, transactions: 0),
    ];

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    await loadAppFonts();
    l10n = await loadL10n();
  });

  Widget harness(List<TimeBucket> buckets, {TextScaler? scaler}) => Scaffold(
        body: SingleChildScrollView(
          child: DashboardHourlySales(buckets: buckets),
        ),
      );

  testWidgets('the hourly chart is a line, not a stack of bars',
      (tester) async {
    tester.useDevice(Device.small);
    await tester.pumpApp(home: harness(_day()));

    expect(find.byType(PosLineChart), findsOneWidget);
    // The bar chart is removed from the codebase entirely — that is why there
    // is no `SimplePosChart` reference in this file to check for.
    final PosLineChart chart = tester.widget<PosLineChart>(
      find.byType(PosLineChart),
    );
    // EVERY bucket in the day, including the hours that sold nothing.
    //
    // The chart's x axis is index-based, so dropping the empty hours would pull
    // every later point left and flatten a day that traded at noon and at 8pm
    // into one adjacent pair — the false "continuous sales" reading the line
    // chart exists to avoid.
    expect(chart.points.length, 5);
  });

  testWidgets('the busiest hour is stated on the card', (tester) async {
    tester.useDevice(Device.small);
    await tester.pumpApp(home: harness(_day()));

    // 18:00 is the peak, and the badge names it — the colour difference the
    // line draws is not the only signal.
    expect(find.text(l10n.dashboardSalesByHour), findsOneWidget);
    expect(find.textContaining('6:00'), findsWidgets);
  });

  testWidgets('the series is restated as a sentence for a screen reader',
      (tester) async {
    tester.useDevice(Device.small);
    await tester.pumpApp(home: harness(_day()));

    final Semantics node = tester.widget<Semantics>(
      find
          .descendant(
            of: find.byType(PosLineChart),
            matching: find.byType(Semantics),
          )
          .first,
    );
    // "Busiest at 6:00 pm with KSh 18,500" rather than silence.
    expect(node.properties.label, contains('6:00'));
    expect(node.properties.label, contains('18,500'));
  });

  testWidgets('a day with no sales says so instead of drawing a flat line',
      (tester) async {
    tester.useDevice(Device.small);
    await tester.pumpApp(
      home: harness(<TimeBucket>[
        for (int hour = 0; hour < 24; hour++)
          TimeBucket(
              hour: hour, salesMinor: 0, profitMinor: 0, transactions: 0),
      ]),
    );

    expect(find.text(l10n.dashboardNoSalesTitle), findsOneWidget);
    expect(find.byType(PosLineChart), findsNothing);
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
            home: harness(_day(), scaler: TextScaler.linear(scale)),
            textScaler: TextScaler.linear(scale),
            brightness: brightness,
          );
          tester.expectNoOverflow('dashboard hourly chart $where');
        });
      }
    }
  }
}
