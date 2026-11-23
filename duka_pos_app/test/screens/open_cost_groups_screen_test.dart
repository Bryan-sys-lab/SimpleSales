import 'package:duka_pos/l10n/generated/app_localizations.dart';
import 'package:duka_pos/l10n/app_localizations_config.dart';
import 'package:duka_pos/routing/routes.dart';
import 'package:duka_pos/screens/open_cost_group_form_screen.dart';
import 'package:duka_pos/screens/open_cost_groups_screen.dart';
import 'package:duka_pos/ui/layout/page.dart';
import 'package:duka_pos/ui/components/surface.dart';
import 'package:go_router/go_router.dart';
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

  testWidgets('a newly created cost group appears as soon as its form closes',
      (WidgetTester tester) async {
    var groups = <Map<String, dynamic>>[];
    var loads = 0;
    final router = GoRouter(
      initialLocation: Routes.openCostGroups,
      routes: <RouteBase>[
        GoRoute(
          path: Routes.openCostGroups,
          builder: (_, __) => OpenCostGroupsScreen(
            loadPools: () async {
              loads++;
              return groups;
            },
          ),
        ),
        GoRoute(
          path: Routes.openCostGroupNew,
          builder: (context, _) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => context.pop(true),
                child: const Text('Save test group'),
              ),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpApp(
      home: MaterialApp.router(
        routerConfig: router,
        theme: themedForTest(Brightness.light),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
    await tester.pumpAndSettle();
    expect(loads, 1);
    expect(find.text('Spring inventory'), findsNothing);

    groups = <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 42,
        'name': 'Spring inventory',
        'invested_minor': 0,
        'recovered_minor': 0,
      },
    ];
    await tester.tap(find.widgetWithText(FilledButton, 'New cost group').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save test group'));
    await tester.pumpAndSettle();

    expect(loads, 2);
    expect(find.text('Spring inventory'), findsOneWidget);
  });

  testWidgets('the cost-group form scrolls above the open keyboard',
      (WidgetTester tester) async {
    tester.useDevice(Device.compact);
    await tester.pumpApp(home: const OpenCostGroupFormScreen());
    await tester.pump();

    final lastField = find.byType(TextFormField).last;
    await tester.ensureVisible(lastField);
    await tester.tap(lastField);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();

    final saveButton = find.widgetWithText(FilledButton, 'Create cost group');
    await tester.ensureVisible(saveButton);
    await tester.pump();

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.getRect(saveButton).bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(AdaptivePage)).bottom));
  });
}
