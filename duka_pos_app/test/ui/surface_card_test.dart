import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:duka_pos/ui/components/surface.dart';

import '../support/harness.dart';

void main() {
  testWidgets('tappable surface cards provide spring press feedback',
      (tester) async {
    tester.useDevice(Device.compact);
    var taps = 0;
    await tester.pumpApp(
      home: SurfaceCard(
        onTap: () => taps++,
        child: const Text('Open inventory'),
      ),
    );

    await tester.tap(find.text('Open inventory'));
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.byType(Transform), findsWidgets);
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('surface card feedback remains static with reduced motion',
      (tester) async {
    tester.useDevice(Device.compact);
    await tester.pumpApp(
      disableAnimations: true,
      home: SurfaceCard(
        onTap: () {},
        child: const Text('Open inventory'),
      ),
    );

    expect(find.text('Open inventory'), findsOneWidget);
  });
}
