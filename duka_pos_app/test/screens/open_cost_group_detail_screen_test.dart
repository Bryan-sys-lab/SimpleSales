import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/screens/open_cost_group_detail_screen.dart';
import 'package:duka_pos/ui/components/surface.dart';
import 'package:duka_pos/utils/money.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('cost-pool details remain readable on a compact phone',
      (WidgetTester tester) async {
    tester.useDevice(Device.compact);

    await tester.pumpApp(
      home: OpenCostGroupDetailScreen(
        poolId: 42,
        loadPools: () async => <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 42,
            'name': 'Spring inventory',
            'note': 'Seasonal stock',
            'invested_minor': 1250000,
            'recovered_minor': 250000,
          },
        ],
        loadProducts: () async => <Product>[],
        loadEntries: (int _) async => <Map<String, dynamic>>[],
      ),
      textScaler: TextScaler.linear(1.25),
    );
    await tester.pump();

    expect(find.text('Spring inventory'), findsOneWidget);
    expect(find.byType(SurfaceCard), findsNWidgets(3));
    final refillButton = find.widgetWithText(FilledButton, 'Reload stock');
    expect(refillButton, findsOneWidget);
    expect(tester.widget<FilledButton>(refillButton).onPressed, isNull);
    tester.expectNoOverflow('cost group detail at compact width');
  });

  testWidgets('linked cost-pool items keep the refill action enabled',
      (WidgetTester tester) async {
    tester.useDevice(Device.compact);

    await tester.pumpApp(
      home: OpenCostGroupDetailScreen(
        poolId: 42,
        loadPools: () async => <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 42,
            'name': 'Spring inventory',
            'note': 'Seasonal stock',
            'invested_minor': 1250000,
            'recovered_minor': 250000,
          },
        ],
        loadProducts: () async => <Product>[
          Product(
            name: 'Tea',
            category: 'Drinks',
            costPrice: Money.fromMinor(1000),
            sellPrice: Money.fromMinor(1500),
            stockQty: 4,
            costPoolId: 42,
            reorderLevel: 1,
            updatedAt: '2026-11-22T00:00:00Z',
          ),
        ],
        loadEntries: (int _) async => <Map<String, dynamic>>[],
      ),
    );
    await tester.pump();

    expect(find.text('Tea'), findsOneWidget);
    final refillButton = find.widgetWithText(FilledButton, 'Reload stock');
    expect(refillButton, findsOneWidget);
    expect(tester.widget<FilledButton>(refillButton).onPressed, isNotNull);
  });
}
