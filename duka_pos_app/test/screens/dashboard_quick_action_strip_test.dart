import 'package:duka_pos/screens/dashboard_shared.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('quick actions scroll horizontally at narrow width and large text',
      (WidgetTester tester) async {
    tester.useDevice(Device.compact);
    await tester.pumpApp(
      home: Scaffold(
        body: DashboardQuickActionStrip(
          actions: <Widget>[
            for (int index = 1; index <= 8; index++)
              ActionChip(
                avatar: const Icon(Icons.bolt_outlined),
                label: Text('Action $index'),
                onPressed: () {},
              ),
          ],
        ),
      ),
      textScaler: const TextScaler.linear(2),
    );

    expect(find.text('Action 1'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Action 8'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Action 8'), findsOneWidget);
    tester.expectNoOverflow('dashboard quick-action strip');
  });
}
