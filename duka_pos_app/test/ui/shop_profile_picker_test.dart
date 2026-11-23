import 'package:duka_pos/ui/shop_profile_picker.dart';
import 'package:duka_pos/profile/shop_profile.dart';
import 'package:duka_pos/theme/app_colors.dart';
import 'package:material_ui/material_ui.dart';
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

    // Duka card shows selected state.
    expect(find.byIcon(Icons.check), findsOneWidget);
    final Map<String, String> profileImages = <String, String>{
      'Duka': 'assets/onboarding/duka_shop_photo.jpg',
      'Drinks': 'assets/onboarding/drinks_shop_photo.jpg',
      'Fashion': 'assets/onboarding/fashion_shop_photo.jpg',
      'Open': 'assets/onboarding/open_shop_photo.jpg',
    };
    for (final MapEntry<String, String> profile in profileImages.entries) {
      await tester.scrollUntilVisible(
        find.text(profile.key),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is Image &&
              widget.image is AssetImage &&
              (widget.image as AssetImage).assetName == profile.value,
        ),
        findsOneWidget,
      );
    }
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('selecting a profile updates selection visibly',
      (WidgetTester tester) async {
    tester.useDevice(Device.compact);
    ShopProfile selected = ShopProfile.duka;
    await tester.pumpApp(
      home: StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) =>
            ShopProfilePicker(
          value: selected,
          onChanged: (ShopProfile profile) {
            setState(() => selected = profile);
          },
        ),
      ),
    );
    final AppColors colors =
        AppColors.of(tester.element(find.byType(ShopProfilePicker)));

    Material profileCard(String title) {
      final Finder card = find
          .ancestor(
            of: find.text(title).first,
            matching: find.byType(Material),
          )
          .first;
      return tester.widget<Material>(card);
    }

    expect(profileCard('Duka').color, colors.selectionContainer);
    expect(
      (profileCard('Duka').shape! as RoundedRectangleBorder).side.color,
      colors.selection,
    );

    final rail = find.byType(Scrollable).first;
    // Each option remains reachable in order on the horizontal rail.
    await tester.tap(find.text('Drinks').first);
    await tester.pumpAndSettle();
    expect(selected, ShopProfile.drinks);
    expect(profileCard('Drinks').color, colors.selectionContainer);
    expect(find.byIcon(Icons.check), findsOneWidget);

    // Tap Fashion.
    await tester.scrollUntilVisible(find.text('Fashion'), 120,
        scrollable: rail);
    await tester.tap(find.text('Fashion').first);
    await tester.pumpAndSettle();
    expect(selected, ShopProfile.fashion);
    expect(profileCard('Fashion').color, colors.selectionContainer);

    // Tap Open.
    await tester.scrollUntilVisible(find.text('Open'), 120, scrollable: rail);
    await tester.tap(find.text('Open').first);
    await tester.pumpAndSettle();
    expect(selected, ShopProfile.open);
    expect(profileCard('Open').color, colors.selectionContainer);

    // Back to Duka.
    await tester.drag(find.byType(ListView), const Offset(400, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duka').first);
    await tester.pumpAndSettle();
    expect(selected, ShopProfile.duka);
    expect(profileCard('Duka').color, colors.selectionContainer);
  });

  testWidgets('keeps the profile rail horizontally scrollable on wide surfaces',
      (WidgetTester tester) async {
    tester.useDevice(Device.tablet);
    await tester.pumpApp(
      home: ShopProfilePicker(
        value: ShopProfile.duka,
        onChanged: (profile) {},
      ),
    );

    expect(find.byType(ListView), findsOneWidget);
    expect(
        find.byWidgetPredicate((widget) =>
            widget is ListView && widget.scrollDirection == Axis.horizontal),
        findsOneWidget);
    await tester.scrollUntilVisible(find.text('Open'), 160,
        scrollable: find.byType(Scrollable).first);
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
