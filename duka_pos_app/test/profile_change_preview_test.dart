import 'package:duka_pos/l10n/generated/app_localizations.dart';
import 'package:duka_pos/profile/shop_profile.dart';
import 'package:duka_pos/profile/profile_terminology.dart';
import 'package:flutter/material.dart';
import 'package:duka_pos/screens/settings_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    await loadAppFonts();
    l10n = await loadL10n();
  });

  testWidgets('profile change preview names navigation and terminology',
      (tester) async {
    tester.useDevice(Device.compact);
    await tester.pumpApp(
      home: SingleChildScrollView(
        child: ProfileChangePreview(
          current: ShopProfile.duka,
          selected: ShopProfile.open,
        ),
      ),
    );

    expect(find.text(l10n.settingsBusinessProfilePreviewTitle), findsOneWidget);
    expect(
      find.text(l10n.settingsBusinessProfilePreviewNavigation(
        l10n.settingsBusinessProfileStock,
        l10n.settingsBusinessProfileMoneyFirst,
      )),
      findsOneWidget,
    );
    expect(
      find.text(l10n.settingsBusinessProfilePreviewTerminology(
        ShopProfile.duka.terminology.product,
        ShopProfile.open.terminology.product,
      )),
      findsOneWidget,
    );
    tester.expectNoOverflow('profile change preview');
  });
}
