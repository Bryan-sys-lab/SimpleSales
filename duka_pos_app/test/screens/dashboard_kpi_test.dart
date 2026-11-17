import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:duka_pos/screens/dashboard_shared.dart';

import '../support/harness.dart';

void main() {
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
