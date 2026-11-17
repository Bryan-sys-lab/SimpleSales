import 'package:flutter_test/flutter_test.dart';
import 'package:duka_pos/profile/shop_profile.dart';
import 'package:duka_pos/screens/dashboard_shared.dart';

import '../support/harness.dart';

void main() {
  testWidgets(
      'dashboard header localizes the greeting and shows the staff name',
      (tester) async {
    tester.useDevice(Device.compact);
    await tester.pumpApp(
      home: const DashboardBusinessHeader(
        shopName: 'Mama Duka',
        profile: ShopProfile.duka,
        staffName: 'Amina',
      ),
    );

    final l10n = await loadL10n();
    final greeting = timeOfDayWord(l10n);
    expect(find.text(l10n.dashboardGreetingNamed(greeting, 'Amina')),
        findsOneWidget);
    expect(find.text('Mama Duka'), findsOneWidget);
    expect(find.text('Amina welcome to Mama Duka'), findsNothing);
  });

  testWidgets(
      'dashboard header gives an anonymous session a localized greeting',
      (tester) async {
    tester.useDevice(Device.compact);
    await tester.pumpApp(
      home: const DashboardBusinessHeader(
        shopName: 'Mama Duka',
        profile: ShopProfile.duka,
      ),
    );

    final l10n = await loadL10n();
    expect(find.text(l10n.dashboardGreetingAnonymous(timeOfDayWord(l10n))),
        findsOneWidget);
    expect(find.text('Mama Duka'), findsOneWidget);
  });
}
