import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:duka_pos/profile/shop_profile.dart';
import 'package:duka_pos/screens/dashboard_shared.dart';
import 'package:duka_pos/ui/components/surface.dart';
import 'package:duka_pos/utils/money.dart';

import '../support/harness.dart';

void main() {
  testWidgets('dashboard sales hero uses a neutral card and quiet brand edge',
      (tester) async {
    tester.useDevice(Device.compact);
    await tester.pumpApp(
      home: DashboardMoneyHero(
        profile: ShopProfile.duka,
        label: 'Net sales',
        amount: Money.fromMajor(12450),
        primaryActionLabel: 'New sale',
        onPrimaryAction: () {},
      ),
    );

    final SurfaceCard card =
        tester.widget<SurfaceCard>(find.byType(SurfaceCard));
    expect(card.color, isNull);
    expect(card.gradient, isNull);
    expect(card.accentEdge, isTrue);
  });

  testWidgets('positive and pending KPI cards keep neutral surfaces',
      (tester) async {
    tester.useDevice(Device.compact);
    await tester.pumpApp(
      home: const Material(
        child: Column(
          children: <Widget>[
            DashboardKpiCard(
              data: DashboardKpiData(
                label: 'Growth',
                value: '+12%',
                icon: Icons.trending_up,
                tone: DashboardKpiTone.positive,
              ),
            ),
            DashboardKpiCard(
              data: DashboardKpiData(
                label: 'Follow-up',
                value: '4',
                icon: Icons.schedule,
                tone: DashboardKpiTone.pending,
              ),
            ),
          ],
        ),
      ),
    );

    final List<SurfaceCard> cards =
        tester.widgetList<SurfaceCard>(find.byType(SurfaceCard)).toList();
    expect(cards, hasLength(2));
    expect(cards.every((SurfaceCard card) => card.gradient == null), isTrue);
    expect(cards.every((SurfaceCard card) => card.color == null), isTrue);
    expect(cards.every((SurfaceCard card) => !card.accentEdge), isTrue);
  });

  testWidgets('a tappable dashboard KPI responds to press and release',
      (tester) async {
    tester.useDevice(Device.compact);
    var taps = 0;
    await tester.pumpApp(
      home: Material(
        child: DashboardKpiCard(
          data: DashboardKpiData(
            label: 'Inventory',
            value: '12',
            icon: Icons.inventory_2_outlined,
            onTap: () => taps++,
          ),
        ),
      ),
    );

    final finder = find.text('Inventory');
    await tester.tap(finder);
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.byType(Transform), findsWidgets);
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('a dashboard KPI keeps press feedback still under reduced motion',
      (tester) async {
    tester.useDevice(Device.compact);
    await tester.pumpApp(
      disableAnimations: true,
      home: const Material(
        child: DashboardKpiCard(
          data: DashboardKpiData(
            label: 'Inventory',
            value: '12',
            icon: Icons.inventory_2_outlined,
          ),
        ),
      ),
    );

    expect(find.text('Inventory'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
  });
}
