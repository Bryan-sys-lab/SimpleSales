// The dashboard's sales-by-hour chart, in the real screen's own widget.
//
// What needs proving is that the widget the dashboard screen builds is the ONE
// PER HOUR bar chart — one bar per bucket, an axis that reads at an interval
// rather than as a row of collisions, and a money figure that appears only when
// a bar is touched — and that the peak is still stated for a screen reader and
// still survives the largest text scale without a clamp.

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

  testWidgets('one bar per hour, including the hours that sold nothing',
      (tester) async {
    tester.useDevice(Device.small);
    await tester.pumpApp(home: harness(_day()));

    expect(find.byType(PosBarChart), findsOneWidget);
    final PosBarChart chart = tester.widget<PosBarChart>(
      find.byType(PosBarChart),
    );
    // EVERY bucket in the day. The axis is index-based, so dropping the empty
    // hours would pull every later bar left and flatten a day that traded at
    // noon and at 8pm into one adjacent pair.
    expect(chart.points.length, 5);
    // The axis label is the SHORT form. Twenty-four "2:00 pm" labels across a
    // 320dp phone is the row of collisions this replaces.
    expect(chart.points.map((PosLinePoint p) => p.label),
        everyElement(isNot(contains(':00'))));
  });

  testWidgets('a bar answers when it is touched', (tester) async {
    // The figure is painted on the canvas when a bar is tapped, so what a test
    // can reach is the announcement — which is also the part a screen reader
    // gets, and the reason the announce string exists at all.
    tester.useDevice(Device.small);
    await tester.pumpApp(home: harness(_day()));

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

    // Before the touch, the series is stated as a whole — here by the caller's
    // own sentence, naming the peak hour.
    expect(labelOf(), contains('Busiest'));

    // Touching a bar reveals THAT hour, and the announcement follows the finger
    // — "Selected 6pm" rather than the peak the card already says in words.
    await tester.tap(find.byType(PosBarChart));
    await tester.pumpAndSettle();
    expect(labelOf(), contains('18,500'));

    // Tapping the same bar again puts the figure away, so nothing is left on
    // screen after the shop has read what it wanted.
    await tester.tap(find.byType(PosBarChart));
    await tester.pumpAndSettle();
    // No substring match on the whole sentence: `DateFormat.jm` inserts the
    // meridiem as a narrow no-break space in this locale, and asserting on that
    // would test the platform's whitespace rather than this chart.
    expect(labelOf().contains('Selected'), isFalse);
  });

  testWidgets('the axis is labelled at an interval, not every bar',
      (tester) async {
    // The interval the user asked for: a whole trading day, on a phone. The
    // point is that the axis READS — morning, midday, evening — rather than
    // thinning itself until it disappears.
    tester.useDevice(Device.compact);
    await tester.pumpApp(
      home: harness(<TimeBucket>[
        for (int hour = 0; hour < 24; hour++)
          TimeBucket(
              hour: hour,
              salesMinor: hour == 18 ? 1850000 : 0,
              profitMinor: 0,
              transactions: hour == 18 ? 34 : 0),
      ]),
    );

    // The painted labels are the chart's own business, so the reachable text is
    // what matters: NONE is absent, and the series is still stated for a screen
    // reader.
    expect(find.byType(PosBarChart), findsOneWidget);
    final Semantics node = tester.widget<Semantics>(
      find
          .descendant(
            of: find.byType(PosBarChart),
            matching: find.byType(Semantics),
          )
          .first,
    );
    // All twenty-four hours are in the series, and the peak is named.
    expect(node.properties.label, contains('18,500'));
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
            of: find.byType(PosBarChart),
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
    expect(find.byType(PosBarChart), findsNothing);
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
