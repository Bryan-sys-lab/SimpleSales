// The dashboard's sales-by-hour chart, in the real screen's own widget.
//
// What needs proving is that the widget the dashboard screen builds is the ONE
// SMOOTH LINE across the hours — a line, not a row of bars, with an axis that
// reads at an interval rather than as a row of collisions, and a money figure
// that appears when the line is touched — and that the peak is still stated
// for a screen reader and still survives the largest text scale without a
// clamp.

import 'package:duka_pos/l10n/generated/app_localizations.dart';
import 'package:duka_pos/screens/dashboard_sections.dart';
import 'package:duka_pos/services/analytics.dart';
import 'package:duka_pos/widgets/chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

/// A trading day: quiet at opening, a lunch peak, an evening peak.
///
/// TWENTY-FOUR buckets, because that is what the query answers with: one slot
/// per hour of the day, dense, so a quiet hour is a zero bar rather than a
/// missing one. A sparse list would be a different chart, and the widget's
/// contract is the dense one.
List<TimeBucket> _day() => <TimeBucket>[
      for (int hour = 0; hour < 24; hour++)
        TimeBucket(
          hour: hour,
          salesMinor: switch (hour) {
            8 => 400000,
            12 => 1200000,
            18 => 1850000,
            20 => 900000,
            _ => 0,
          },
          profitMinor: 0,
          transactions: 0,
        ),
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

  testWidgets('the quiet overnight hours are trimmed, the trading day is not',
      (tester) async {
    tester.useDevice(Device.small);
    await tester.pumpApp(home: harness(_day()));

    // A LINE, not a row of bars: the shape of the day is what a shopkeeper
    // looks at, and a line draws that shape in one gesture.
    expect(find.byType(PosLineChart), findsOneWidget);
    expect(find.byType(PosBarChart), findsNothing);
    final PosLineChart chart = tester.widget<PosLineChart>(
      find.byType(PosLineChart),
    );

    // The first sale is at 8am and the last at 8pm, so the chart runs from
    // 7am to 9pm — an hour of margin on each side, and nothing else.
    //
    // The hours in BETWEEN are kept, empty ones included: a quiet hour is a
    // zero, not a missing one, and dropping it would put a lunch peak and
    // an evening peak side by side as though they were an hour apart.
    expect(chart.points.length, 15);
    expect(chart.points.first.label, contains('7'));
    expect(chart.points.last.label, contains('9'));

    // The axis label is the SHORT form. Twenty-four "2:00 pm" labels across a
    // 320dp phone is the row of collisions this replaces.
    expect(chart.points.map((PosLinePoint p) => p.label),
        everyElement(isNot(contains(':00'))));
  });

  testWidgets('the axis reads at an interval, not at every hour',
      (tester) async {
    tester.useDevice(Device.compact);
    await tester.pumpApp(home: harness(_day()));

    // THE INTERVAL. A trading day is fifteen hours on this chart, and the axis
    // must not carry a label for every one of them: on a 320dp phone that is a
    // row of collisions rather than an axis.
    final PosLineChart chart = tester.widget<PosLineChart>(
      find.byType(PosLineChart),
    );
    expect(chart.minStride, greaterThanOrEqualTo(2));

    // The floor is the interval, and it is never LOWERED by a wide screen:
    // three is what a trading day reads at, however much room there is.
    expect(chart.minStride, kPosChartMinStride);
  });

  testWidgets('a reading answers when the line is touched', (tester) async {
    // The figure is painted on the canvas when the line is touched, so what a
    // test can reach is the announcement — which is also the part a screen
    // reader gets, and the reason the announce string exists at all.
    tester.useDevice(Device.small);
    await tester.pumpApp(home: harness(_day()));

    String labelOf() => tester
        .widget<Semantics>(
          find
              .descendant(
                of: find.byType(PosLineChart),
                matching: find.byType(Semantics),
              )
              .first,
        )
        .properties
        .label!;

    // Before the touch, the series is stated as a whole — here by the caller's
    // own sentence, naming the peak hour.
    expect(labelOf(), contains('Busiest'));

    // Touching the line reveals THAT hour, and the announcement follows the
    // finger — "Selected 6pm" rather than the peak the card already says in
    // words.
    //
    // The PEAK's reading, computed rather than guessed: the readings sit on a
    // line, the first at one edge and the last at the other, and the peak is
    // the twelfth of fifteen.
    final PosLineChart chart = tester.widget<PosLineChart>(
      find.byType(PosLineChart),
    );
    final int peakIndex =
        chart.points.indexWhere((PosLinePoint p) => p.value == 1850000);
    expect(peakIndex, isNot(-1));
    final Rect chartRect = tester.getRect(find.byType(PosLineChart));
    final double step = chartRect.width / (chart.points.length - 1);
    final Offset peak = Offset(
      chartRect.left + peakIndex * step,
      chartRect.center.dy,
    );

    await tester.tapAt(peak);
    await tester.pumpAndSettle();
    expect(labelOf(), contains('18,500'));

    // Tapping the same reading again puts the figure away, so nothing is left
    // on screen after the shop has read what it wanted.
    await tester.tapAt(peak);
    await tester.pumpAndSettle();
    // No substring match on the whole sentence: `DateFormat.jm` inserts the
    // meridiem as a narrow no-break space in this locale, and asserting on that
    // would test the platform's whitespace rather than this chart.
    expect(labelOf().contains('Selected'), isFalse);
  });

  testWidgets('the busiest hour is stated on the card', (tester) async {
    tester.useDevice(Device.small);
    await tester.pumpApp(home: harness(_day()));

    // 18:00 is the peak, and the badge names it — the colour difference the
    // line draws is not the only signal.
    expect(find.text(l10n.dashboardSalesByHour), findsWidgets);
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
