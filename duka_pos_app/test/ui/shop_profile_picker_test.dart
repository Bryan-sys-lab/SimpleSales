import 'package:duka_pos/ui/shop_profile_picker.dart';
import 'package:duka_pos/profile/shop_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('renders all four profiles with duka selected by default',
      (WidgetTester tester) async {
    tester.useDevice(Device.small);
    await tester.pumpApp(
      home: ShopProfilePicker(
        value: ShopProfile.duka,
        onChanged: (profile) {},
      ),
    );

    expect(find.text('Duka'), findsOneWidget);
    expect(find.text('Drinks'), findsOneWidget);
    expect(find.text('Fashion'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);

    // Duka card shows selected state.
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('selecting a profile updates selection visibly',
      (WidgetTester tester) async {
    tester.useDevice(Device.compact);
    ShopProfile? selected;
    await tester.pumpApp(
      home: ShopProfilePicker(
        value: ShopProfile.duka,
        onChanged: (profile) => selected = profile,
      ),
    );

    // Tap Drinks.
    await tester.tap(find.text('Drinks').first);
    await tester.pumpAndSettle();
    expect(selected, ShopProfile.drinks);

    // Tap Fashion.
    await tester.tap(find.text('Fashion').first);
    await tester.pumpAndSettle();
    expect(selected, ShopProfile.fashion);

    // Tap Open.
    await tester.tap(find.text('Open').first);
    await tester.pumpAndSettle();
    expect(selected, ShopProfile.open);

    // Back to Duka.
    await tester.tap(find.text('Duka').first);
    await tester.pumpAndSettle();
    expect(selected, ShopProfile.duka);
  });

  testWidgets('shows four columns on wide surfaces',
      (WidgetTester tester) async {
    tester.useDevice(Device.tablet);
    await tester.pumpApp(
      home: ShopProfilePicker(
        value: ShopProfile.duka,
        onChanged: (profile) {},
      ),
    );

    expect(find.text('Duka'), findsOneWidget);
    expect(find.text('Drinks'), findsOneWidget);
    expect(find.text('Fashion'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
  });

  for (final Device device in <Device>[Device.compact, Device.small]) {
    for (final double scale in <double>[1, 2]) {
      testWidgets('fits ${device.name} x$scale', (WidgetTester tester) async {
        tester.useDevice(device);
        await tester.pumpApp(
          home: ShopProfilePicker(
            value: ShopProfile.duka,
            onChanged: (profile) {},
          ),
          textScaler: TextScaler.linear(scale),
        );
        tester.expectNoOverflow('shop profile picker ${device.name} x$scale');
      });
    }
  }

  testWidgets('keeps profile cards above the touch-target floor',
      (WidgetTester tester) async {
    tester.useDevice(Device.compact);
    await tester.pumpApp(
      home: ShopProfilePicker(
        value: ShopProfile.duka,
        onChanged: (profile) {},
      ),
    );

    tester.expectTapTargetsMeetMinimum(find.byType(ShopProfilePicker));
  });
}
