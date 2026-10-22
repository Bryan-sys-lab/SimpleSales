// The chooser's hierarchy, which is a correctness property rather than a taste.
//
// The two reason this is worth testing:
//
//   1. Sign-in must be the DOMINANT control. It is the choice a shop owner
//      makes every single day of the app's life, and setting a shop up is the
//      one that happens once. When all three were the same weight and the same
//      size, the daily action had to compete with the once-only one — which on
//      a small screen at a large text scale is a real difference in what gets
//      tapped.
//
//   2. Setup must remain reachable. Demoting it is only correct if the shop
//      that has never set up can still find it, so its absence of a fill is
//      paired with an assertion that the control is still there and still
//      labelled.

import 'package:duka_pos/l10n/generated/app_localizations.dart';
import 'package:duka_pos/routing/app_stage_controller.dart';
import 'package:duka_pos/services/app_stage.dart';
import 'package:duka_pos/screens/welcome_chooser_screen.dart';
import 'package:duka_pos/ui/brand/simple_pos_mark.dart';
import 'package:duka_pos/services/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/harness.dart';

void main() {
  Future<void> pumpChooser(
    WidgetTester tester, {
    bool hasShop = false,
  }) async {
    tester.useDevice(Device.small);
    await tester.pumpApp(
      home: ChangeNotifierProvider<AppStageController>(
        create: (BuildContext _) => AppStageController(AppState()),
        child: WelcomeChooserScreen(
          hasShop: hasShop,
          shopName: hasShop ? 'Amina Duka' : '',
          intent: AppChooserIntent.signIn,
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('sign-in is the solid, dominant button',
      (WidgetTester tester) async {
    await pumpChooser(tester, hasShop: true);

    final l10n = AppLocalizations.of(
      tester.element(find.byType(WelcomeChooserScreen)),
    );

    // Sign-in is FILLED — solid, not outlined — so it is the one that draws the
    // eye. This is the hierarchy the screen did not have when all three
    // choices were the same weight.
    final filled = find.byType(FilledButton);
    expect(filled, findsWidgets);
    expect(
      find.descendant(
        of: filled,
        matching: find.text(l10n.chooserSignInAction),
      ),
      findsOneWidget,
    );
  });

  testWidgets('staff sign-in is present and reachable',
      (WidgetTester tester) async {
    await pumpChooser(tester, hasShop: true);

    final l10n = AppLocalizations.of(
      tester.element(find.byType(WelcomeChooserScreen)),
    );
    final staff =
        find.widgetWithText(FilledButton, l10n.chooserSignInAsStaffAction);
    expect(staff, findsOneWidget,
        reason: 'a till a cashier uses at shift start must not be buried');
  });

  testWidgets('setup is present but is the quietest control',
      (WidgetTester tester) async {
    await pumpChooser(tester);

    final l10n = AppLocalizations.of(
      tester.element(find.byType(WelcomeChooserScreen)),
    );

    // Reachable.
    final setup = find.widgetWithText(TextButton, l10n.chooserSetupFirst);
    expect(setup, findsOneWidget);

    // And not solid: the twice-a-year choice is not the primary one.
    final setupButton = tester.widget<TextButton>(setup);
    expect(setupButton.onPressed, isNotNull);

    final filledSetup = find.descendant(
      of: find.byType(TextButton),
      matching: find.byType(FilledButton),
    );
    expect(filledSetup, findsNothing,
        reason: 'setup must not compete with the daily action');
  });

  testWidgets('the vector mark is drawn, not a raster asset',
      (WidgetTester tester) async {
    // A PNG of a mark the app draws as paths is the one place the brand lands
    // fuzzy, and this is the first screen a shop owner sees. The launcher icon
    // and the app should finally agree.
    await pumpChooser(tester);

    expect(find.byType(SimplePosMark), findsOneWidget);

    // Scoped to the APP'S OWN brand, which is the point of the rule.
    //
    // The VENDOR's wordmark at the foot of this screen IS a raster asset: it
    // is a different company's logo, drawn by them, and this app does not draw
    // it as paths. What must never happen is the app's OWN mark arriving as a
    // PNG — that is the launcher icon and the app disagreeing about the brand.
    for (final Image image in tester.widgetList<Image>(find.byType(Image))) {
      final AssetImage? asset = image.image as AssetImage?;
      expect(
        asset?.assetName,
        isNot(startsWith('assets/branding/simple_pos')),
        reason:
            'the app\'s own brand is drawn as paths, never shipped as a PNG',
      );
    }
  });

  testWidgets('a shop that is already set up says so',
      (WidgetTester tester) async {
    await pumpChooser(tester, hasShop: true);

    final l10n = AppLocalizations.of(
      tester.element(find.byType(WelcomeChooserScreen)),
    );
    expect(find.textContaining('Amina Duka'), findsWidgets,
        reason: 'the shop name is what proves this is the right till');
    expect(l10n.chooserSignedInShop('Amina Duka'), isNotEmpty);
  });
}
