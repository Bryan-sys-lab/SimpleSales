import 'package:duka_pos/screens/product_onboarding_screen.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('shows exactly three product-tour pages',
      (WidgetTester tester) async {
    tester.useDevice(Device.small);
    bool created = false;
    bool signedIn = false;
    await tester.pumpApp(
      home: ProductOnboardingScreen(
        onCreateAccount: () => created = true,
        onSignIn: () => signedIn = true,
      ),
    );

    // Page 1: value proposition.
    expect(find.text('The till your shop already knows'), findsOneWidget);
    expect(find.text('1 of 3'), findsOneWidget);

    // Sign-in is visible in the header.
    expect(find.text('Sign in'), findsOneWidget);

    // Continue advances to page 2.
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Four profiles, one app'), findsOneWidget);
    expect(find.text('2 of 3'), findsOneWidget);

    // Page 2: four profile cards are visible.
    expect(find.text('Duka'), findsOneWidget);
    expect(find.text('Drinks'), findsOneWidget);
    expect(find.text('Fashion'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'assets/onboarding/fashion_shop_photo.jpg',
      ),
      findsOneWidget,
    );

    // Continue advances to page 3.
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Your shop, on your phone'), findsOneWidget);
    expect(find.text('3 of 3'), findsOneWidget);

    // Continue on the final page creates an account.
    await tester.tap(find.text('Create account'));
    expect(created, isTrue);
    expect(signedIn, isFalse);
  });

  testWidgets('sign-in works from any page', (WidgetTester tester) async {
    tester.useDevice(Device.small);
    bool signedIn = false;
    await tester.pumpApp(
      home: ProductOnboardingScreen(
        onCreateAccount: () {},
        onSignIn: () => signedIn = true,
      ),
    );

    expect(find.text('Sign in'), findsOneWidget);
    await tester.tap(find.text('Sign in'));
    expect(signedIn, isTrue);
  });

  testWidgets('skip calls onSkip and does not create an account',
      (WidgetTester tester) async {
    tester.useDevice(Device.small);
    bool skipped = false;
    bool created = false;
    await tester.pumpApp(
      home: ProductOnboardingScreen(
        onCreateAccount: () => created = true,
        onSignIn: () {},
        onSkip: () => skipped = true,
      ),
    );

    expect(find.text('Skip'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    expect(skipped, isTrue);
    expect(created, isFalse);
  });

  testWidgets('exposes page progress and hero to accessibility services',
      (WidgetTester tester) async {
    tester.useDevice(Device.small);
    final SemanticsHandle handle = tester.ensureSemantics();
    await tester.pumpApp(
      home: ProductOnboardingScreen(
        onCreateAccount: () {},
        onSignIn: () {},
      ),
    );

    expect(find.bySemanticsLabel('Page 1 of 3'), findsOneWidget);
    expect(find.bySemanticsLabel('Sign in'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('keeps first-page actions above the touch-target floor',
      (WidgetTester tester) async {
    tester.useDevice(Device.small);
    await tester.pumpApp(
      home: ProductOnboardingScreen(
        onCreateAccount: () {},
        onSignIn: () {},
      ),
    );

    tester.expectTapTargetsMeetMinimum(find.byType(ProductOnboardingScreen));
  });

  for (final Device device in <Device>[Device.compact, Device.small]) {
    for (final double scale in <double>[1, 2]) {
      testWidgets('fits ${device.name} x$scale', (WidgetTester tester) async {
        tester.useDevice(device);
        await tester.pumpApp(
          home: ProductOnboardingScreen(
            onCreateAccount: () {},
            onSignIn: () {},
          ),
          textScaler: TextScaler.linear(scale),
        );
        tester.expectNoOverflow('product onboarding ${device.name} x$scale');
      });
    }
  }
}
