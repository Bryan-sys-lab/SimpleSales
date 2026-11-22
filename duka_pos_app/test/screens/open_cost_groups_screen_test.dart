import 'package:duka_pos/screens/open_cost_groups_screen.dart';
import 'package:duka_pos/ui/components/surface.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('summary and cost groups fit a compact phone without loud fills',
      (WidgetTester tester) async {
    tester.useDevice(Device.compact);

    await tester.pumpApp(
      home: OpenCostGroupsScreen(
        loadPools: () async => <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 42,
            'name': 'Spring inventory',
            'invested_minor': 1250000,
            'recovered_minor': 250000,
          },
        ],
      ),
      textScaler: TextScaler.linear(1.25),
    );
    await tester.pump();

    expect(find.text('Spring inventory'), findsOneWidget);
    expect(find.byTooltip('New cost group'), findsOneWidget);
    final List<SurfaceCard> cards =
        tester.widgetList<SurfaceCard>(find.byType(SurfaceCard)).toList();
    expect(cards, hasLength(2));
    expect(cards.every((SurfaceCard card) => card.gradient == null), isTrue);
    expect(cards.every((SurfaceCard card) => card.color == null), isTrue);
    expect(cards.where((SurfaceCard card) => card.accentEdge), hasLength(1));
    tester.expectNoOverflow('cost groups at compact width');
  });
}
