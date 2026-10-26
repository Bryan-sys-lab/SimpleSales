import 'package:duka_pos/screens/product_onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('explains all four profiles and reaches account creation',
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

    expect(find.text('Your business, simplified'), findsOneWidget);
    await tester.tap(find.text('I have an account'));
    expect(signedIn, isTrue);

    // Return to the tour for the page-by-page profile assertions.
    signedIn = false;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpApp(
      home: ProductOnboardingScreen(
        onCreateAccount: () => created = true,
        onSignIn: () => signedIn = true,
      ),
    );
    for (final String label in <String>[
      'Continue',
      'Continue',
      'Continue',
      'Continue',
      'Continue',
    ]) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }
    expect(find.text('Open profile'), findsOneWidget);
    await tester.tap(find.text('Create your account'));
    expect(created, isTrue);
  });

  testWidgets('exposes the tour image and actions to accessibility services',
      (WidgetTester tester) async {
    tester.useDevice(Device.small);
    final SemanticsHandle handle = tester.ensureSemantics();
    await tester.pumpApp(
      home: ProductOnboardingScreen(
        onCreateAccount: () {},
        onSignIn: () {},
      ),
    );

    expect(find.bySemanticsLabel('Kenyan shop business'), findsOneWidget);
    expect(find.bySemanticsLabel('I have an account'), findsOneWidget);
    expect(find.bySemanticsLabel('Continue'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('keeps the first-page actions above the touch-target floor',
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
