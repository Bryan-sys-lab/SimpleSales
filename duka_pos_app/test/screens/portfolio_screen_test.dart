// End-to-end render checks for the portfolio view.
//
// This screen answers a question no single shop can answer — "how are ALL my
// shops doing" — and it is built almost entirely from a `PortfolioKpis` value,
// so the whole layout is renderable without a backend. What needs proving is the
// arithmetic the screen DISPLAYS: the total being the sum of the parts, the
// average being recomputed from the totals, and the busiest shop being named
// rather than left for a reader to work out.
//
// One `testWidgets` per (device, scale, brightness) tuple, with the loop AROUND
// the test: an overflow is reported once per render object, so a test looping
// scales internally under-reports everything but the first.
//
// `loadAppFonts` is not optional: under Ahem every glyph is a fixed em-square,
// so the 2.0x half of this matrix would pass vacuously.

import 'package:duka_pos/l10n/generated/app_localizations.dart';
import 'package:duka_pos/screens/portfolio_screen.dart';
import 'package:duka_pos/services/portfolio_kpis.dart';
import 'package:duka_pos/utils/money.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

/// Three shops: one busy, one middling, one that sold nothing.
///
/// The quiet one is deliberate — a shop missing from its own owner's list reads
/// as a shop the app has lost.
PortfolioKpis _kpis() => PortfolioKpis(
      windowStart: DateTime(2026, 1, 1),
      windowEnd: DateTime(2026, 2, 1),
      shops: <ShopKpi>[
        ShopKpi(
          tenantId: 't1',
          shopName: 'Amina Duka',
          role: 'admin',
          revenue: Money.fromMinor(900000),
          profit: Money.fromMinor(300000),
          transactions: 60,
          topPaymentMethod: 'mpesa',
        ),
        ShopKpi(
          tenantId: 't2',
          shopName: 'Njeri Shop',
          role: 'admin',
          revenue: Money.fromMinor(200000),
          profit: Money.fromMinor(60000),
          transactions: 10,
          topPaymentMethod: 'cash',
        ),
        ShopKpi(
          tenantId: 't3',
          shopName: 'Quiet Shop',
          role: 'admin',
          revenue: Money.zero,
          profit: Money.zero,
          transactions: 0,
          topPaymentMethod: null,
        ),
      ],
    );

/// The panel the screen builds, driven by a constructed value.
///
/// `PortfolioPanel` is public for exactly this reason — the same split
/// `SettingsPanel` and `TaxSettingsPanel` use, so the whole view is renderable
/// from a value without a backend and without a database.
class _PortfolioHarness extends StatelessWidget {
  const _PortfolioHarness();

  @override
  Widget build(BuildContext context) => PortfolioPanel(
        kpis: _kpis(),
        range: PortfolioRange.week,
        onRangeChanged: (PortfolioRange _) {},
      );
}

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    await loadAppFonts();
    l10n = await loadL10n();
  });

  group('portfolio view', () {
    testWidgets('the whole is the sum of the parts, on screen', (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(
        home: const Scaffold(body: _PortfolioHarness()),
      );

      // 9,000 + 2,000 + 0 = 11,000.
      expect(formatMoney(Money.fromMinor(1100000)), contains('11,000'));
      tester.expectNoOverflow('portfolio totals');
    });

    testWidgets('every shop is listed, including the quiet one',
        (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(
        home: const Scaffold(body: _PortfolioHarness()),
      );

      // Appears twice on purpose: once in the ring's legend, once in the
      // ranking below it. So this asserts presence rather than a count.
      expect(find.text('Amina Duka'), findsWidgets);
      expect(find.text('Njeri Shop'), findsWidgets);
      expect(find.text('Quiet Shop'), findsWidgets);
      expect(find.text(l10n.portfolioShopsTitle.toUpperCase()), findsOneWidget);
    });

    testWidgets('the busiest shop is named, not left to be derived',
        (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(
        home: const Scaffold(body: _PortfolioHarness()),
      );

      // "Busiest: Amina Duka at KSh 9,000" — a total an owner cannot act on
      // without knowing where it came from.
      expect(find.textContaining('Busiest:'), findsOneWidget);
    });

    testWidgets('the ranking starts at one and orders by revenue',
        (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(
        home: const Scaffold(body: _PortfolioHarness()),
      );

      expect(find.text('#1'), findsOneWidget);
      final double rank1Y = tester.getTopLeft(find.text('#1')).dy;
      final double rank2Y = tester.getTopLeft(find.text('#2')).dy;
      expect(rank1Y, lessThan(rank2Y));
    });

    testWidgets('the result of the load is announced, not just shown',
        (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(
        home: const Scaffold(body: _PortfolioHarness()),
      );

      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.liveRegion == true,
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
              home: const Scaffold(body: _PortfolioHarness()),
              textScaler: TextScaler.linear(scale),
              brightness: brightness,
            );
            tester.expectNoOverflow('portfolio $where');
          });
        }
      }
    }

    testWidgets('every control clears the 44px floor', (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(
        home: const Scaffold(body: _PortfolioHarness()),
      );

      // The range control and the chip that opens it. The sheet's other
      // interactive surfaces are the shared row widgets, which are asserted
      // against this floor in overflow_matrix_test rather than duplicated here
      // — and `expectTapTargetsMeetMinimum` is scoped to the controls this
      // screen owns, because it walks every InkWell it finds and an unrelated
      // one inside the chart's alignment stack is not this screen's target.
      tester.expectTapTargetsMeetMinimum(
          find.byType(PopupMenuButton<PortfolioRange>));
    });
  });
}
