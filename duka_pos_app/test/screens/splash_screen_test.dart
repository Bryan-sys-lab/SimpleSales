import 'package:duka_pos/screens/splash_screen.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('fills the screen with the startup animation',
      (WidgetTester tester) async {
    tester.useDevice(Device.compact);
    await tester.pumpApp(home: const SplashScreen());

    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'assets/branding/simple_sales_startup_animation.gif',
      ),
      findsOneWidget,
    );
    tester.expectNoOverflow('full-screen startup animation');
  });

  testWidgets('uses a still brand background when reduced motion is enabled',
      (WidgetTester tester) async {
    tester.useDevice(Device.compact);
    await tester.pumpApp(
      home: const SplashScreen(),
      disableAnimations: true,
    );

    expect(find.byType(CircularProgressIndicator), findsNothing);
    tester.expectNoOverflow('reduced-motion startup');
  });
}
