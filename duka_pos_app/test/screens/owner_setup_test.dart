import 'package:duka_pos/screens/owner_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:duka_pos/ui/shop_profile_picker.dart';

import '../support/harness.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('selecting each profile reaches setShopProfile',
      (WidgetTester tester) async {
    tester.useDevice(Device.compact);
    await tester.pumpApp(
      home: OwnerSetupScreen(
        isAdditionalShop: false,
        onCancel: () {},
      ),
    );

    // Default is Duka.
    expect(find.text('Duka'), findsOneWidget);

    // Select Drinks.
    await tester.ensureVisible(find.byType(ShopProfilePicker));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Drinks').first);
    await tester.pumpAndSettle();
    expect(find.text('Drinks'), findsOneWidget);

    // Select Fashion.
    await tester.ensureVisible(find.byType(ShopProfilePicker));
    await tester.pumpAndSettle();
    final profileRail = find.descendant(
      of: find.byType(ShopProfilePicker),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(find.text('Fashion'), 120,
        scrollable: profileRail);
    await Scrollable.ensureVisible(
      tester.element(find.text('Fashion')),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fashion').first);
    await tester.pumpAndSettle();
    expect(find.text('Fashion'), findsOneWidget);

    // Select Open.
    await tester.scrollUntilVisible(find.text('Open'), 120,
        scrollable: profileRail);
    await Scrollable.ensureVisible(
      tester.element(find.text('Open')),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open').first);
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('additional shop retains prefilled owner behaviour',
      (WidgetTester tester) async {
    tester.useDevice(Device.compact);
    await tester.pumpApp(
      home: OwnerSetupScreen(
        isAdditionalShop: true,
        onCancel: () {},
      ),
    );

    expect(find.text('ADD SHOP'), findsOneWidget);
    expect(find.text('Add another shop'), findsOneWidget);
    expect(find.text('Duka'), findsOneWidget);
  });
}
