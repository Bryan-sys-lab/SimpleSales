import 'package:duka_pos/routing/not_found_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void main() {
  testWidgets('a stale destination offers useful recovery paths',
      (WidgetTester tester) async {
    tester.useDevice(Device.compact);
    await tester.pumpApp(
      home: const NotFoundScreen(location: '/old/inventory/path'),
    );

    expect(find.text('Inventory'), findsOneWidget);
    expect(find.text('Sell'), findsOneWidget);
    expect(find.text('Analytics'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
