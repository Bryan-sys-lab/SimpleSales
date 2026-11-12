// The loose-goods form must speak the active profile's words — never
// drink/tank/cup wording for duka, and never product/servings wording for
// drinks.

import 'package:duka_pos/l10n/generated/app_localizations.dart';
import 'package:duka_pos/profile/shop_profile.dart';
import 'package:duka_pos/screens/loose_goods_form_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    await loadAppFonts();
    l10n = await loadL10n();
  });

  testWidgets(
    'duka loose-goods form uses product and servings wording',
    (WidgetTester tester) async {
      tester.useDevice(Device.compact);
      await tester.pumpApp(
        home: Scaffold(
          body: const LooseGoodsFormSheet(profile: ShopProfile.duka),
        ),
      );

      expect(find.text(l10n.dukaFieldProductName), findsAtLeastNWidgets(1));
      expect(find.text(l10n.dukaFieldProductNameHint), findsOneWidget);
      expect(find.text(l10n.dukaServingsTitle), findsAtLeastNWidgets(1));
      expect(find.text(l10n.dukaServingLabel(1)), findsOneWidget);
      expect(find.text(l10n.dukaSaveProduct), findsOneWidget);

      // Drink/tank wording must not leak into the duka sheet.
      expect(find.text(l10n.tankFieldNameHint), findsNothing);
      expect(find.text('Cup 1'), findsNothing);
      tester.expectNoOverflow('duka loose-goods form');
    },
  );

  testWidgets(
    'drinks loose-goods form keeps tank and cup wording',
    (WidgetTester tester) async {
      tester.useDevice(Device.compact);
      await tester.pumpApp(
        home: Scaffold(
          body: const LooseGoodsFormSheet(profile: ShopProfile.drinks),
        ),
      );

      expect(find.text(l10n.tankFieldNameHint), findsOneWidget);
      expect(find.text(l10n.tankServingsTitle), findsOneWidget);
      expect(find.text('Cup 1'), findsOneWidget);
      expect(find.text(l10n.tankServingAdd), findsOneWidget);

      // Duka product/servings wording must not leak into the drinks sheet.
      expect(find.text(l10n.dukaFieldProductName), findsNothing);
      expect(find.text(l10n.dukaServingsTitle), findsNothing);
      tester.expectNoOverflow('drinks loose-goods form');
    },
  );
}
