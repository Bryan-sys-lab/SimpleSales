import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/l10n/generated/app_localizations.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/routing/app_redirect.dart';
import 'package:duka_pos/routing/app_stage_controller.dart';
import 'package:duka_pos/routing/home_shell.dart';
import 'package:duka_pos/routing/routes.dart';
import 'package:duka_pos/services/app_state.dart';
import 'package:duka_pos/services/live_channel_service.dart';
import 'package:duka_pos/services/app_stage.dart';
import 'package:duka_pos/ui/layout/window_size_class.dart';

class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Scaffold(
        // Findable by identity: the label text also appears on the navigation
        // bar, so `find.text` cannot tell "the Sell screen is showing" from
        // "the Sell tab exists".
        key: ValueKey<String>('screen-$label'),
        appBar: AppBar(title: Text(label)),
        body: Center(child: Text(label)),
      );
}

/// The screen for [label] — found only while it is actually on screen. The
/// default `skipOffstage: true` is the point: go_router keeps every visited
/// branch alive inside an `IndexedStack`, offstage, so a finder that saw
/// offstage widgets would pass even with the dashboard still showing.
Finder _screen(String label) => find.byKey(ValueKey<String>('screen-$label'));

class _FakeStage extends ChangeNotifier {
  _FakeStage(this._snapshot);
  final AppStageSnapshot _snapshot;
  AppStageSnapshot get snapshot => _snapshot;
}

GoRouter _testRouter(AppState state) {
  final _FakeStage stage = _FakeStage(AppStageSnapshot(
    stage: AppStage.ready,
    canManageStock: state.canManageStock,
    isAdmin: state.isAdmin,
  ));

  return GoRouter(
    navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'root'),
    initialLocation: Routes.dashboard,
    refreshListenable: stage,
    redirect: (BuildContext context, GoRouterState routerState) => appRedirect(
      snapshot: AppStageSnapshot(
        stage: AppStage.ready,
        canManageStock: state.canManageStock,
        isAdmin: state.isAdmin,
      ),
      location: routerState.uri.path,
    ),
    errorBuilder: (BuildContext context, GoRouterState routerState) =>
        const Scaffold(body: Center(child: Text('404'))),
    routes: <RouteBase>[
      StatefulShellRoute.indexedStack(
        builder: (BuildContext context, GoRouterState routerState,
                StatefulNavigationShell navigationShell) =>
            HomeShell(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.dashboard,
                builder: (BuildContext context, GoRouterState routerState) =>
                    const _PlaceholderScreen(label: 'Dashboard'),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.sell,
                builder: (BuildContext context, GoRouterState routerState) =>
                    const _PlaceholderScreen(label: 'Sell'),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.inventory,
                builder: (BuildContext context, GoRouterState routerState) =>
                    const _PlaceholderScreen(label: 'Inventory'),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.analytics,
                builder: (BuildContext context, GoRouterState routerState) =>
                    const _PlaceholderScreen(label: 'Analytics'),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.settings,
                builder: (BuildContext context, GoRouterState routerState) =>
                    const _PlaceholderScreen(label: 'Settings'),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

Future<void> _pumpShell(
    WidgetTester tester, AppState state, GoRouter router) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<AppState>.value(value: state),
        Provider<GoRouter>.value(value: router),
        // The idle guard listens to the shop's own activity, so a harness that
        // mounts the shell without the channel the app always provides would
        // take the shell down rather than observe it.
        ChangeNotifierProvider<LiveChannelService>.value(
            value: LiveChannelService()),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: ThemeData.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues(<String, Object>{
      'active_workspace_key': 'legacy',
      'onboarding_completed_legacy': true,
    });
  });

  setUp(() async {
    DatabaseHelper.resetForTests();
    final db = await DatabaseHelper.openInMemoryForTests();
    await db.createOwner(Owner(
      id: 1,
      name: 'Test Owner',
      pinHash: 'test_pin_hash',
      email: 'test@example.com',
      shopName: 'Test Shop',
      createdAt: DateTime.now().toIso8601String(),
    ));
  });

  tearDown(() {
    DatabaseHelper.resetForTests();
  });

  group('visibleDestinations', () {
    test('owner sees all five tabs', () {
      final AppState state = AppState();
      state.signIn('Owner', asOwner: true);
      final visible = visibleDestinations(state).toList();
      expect(visible, equals(AppDestination.values));
    });

    test('manager sees four tabs (no Settings)', () {
      final AppState state = AppState();
      state.signIn('Manager', asOwner: false, role: 'manager');
      final visible = visibleDestinations(state).toList();
      expect(visible, <AppDestination>[
        AppDestination.dashboard,
        AppDestination.sell,
        AppDestination.inventory,
        AppDestination.analytics,
      ]);
    });

    test('cashier sees only dashboard and sell', () {
      final AppState state = AppState();
      state.signIn('Cashier', asOwner: false);
      final visible = visibleDestinations(state).toList();
      expect(visible, <AppDestination>[
        AppDestination.dashboard,
        AppDestination.sell,
      ]);
    });
  });

  group('mobile bottom nav', () {
    testWidgets(
        'all five destinations are offered to an owner on a compact screen',
        (WidgetTester tester) async {
      tester.view.physicalSize =
          const Size(320, 640).testerPhysicalSizeForDpr(2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final AppState state = AppState();
      state.signIn('Test Owner', asOwner: true);
      final GoRouter router = _testRouter(state);
      await _pumpShell(tester, state, router);

      expect(find.byType(Scaffold), findsNWidgets(2));
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationDestination), findsNWidgets(5));
    });

    testWidgets('tapping each destination changes the URL',
        (WidgetTester tester) async {
      tester.view.physicalSize =
          const Size(320, 640).testerPhysicalSizeForDpr(2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final AppState state = AppState();
      state.signIn('Test Owner', asOwner: true);
      final GoRouter router = _testRouter(state);
      await _pumpShell(tester, state, router);

      final List<String> visited = <String>[];

      String location() => router.routeInformationProvider.value.uri.path;

      visited.add(location());

      await tester.tap(find.text('Sell').first);
      await tester.pump(const Duration(milliseconds: 50));
      visited.add(location());

      await tester.tap(find.text('Inventory').first);
      await tester.pump(const Duration(milliseconds: 50));
      visited.add(location());

      await tester.tap(find.text('Analytics').first);
      await tester.pump(const Duration(milliseconds: 50));
      visited.add(location());

      await tester.tap(find.text('Settings').first);
      await tester.pump(const Duration(milliseconds: 50));
      visited.add(location());

      final distinct = visited.toSet();
      expect(distinct.length, greaterThanOrEqualTo(3),
          reason: 'expected navigation to change the URL, got $visited');
    });

    testWidgets('manager sees four tabs', (WidgetTester tester) async {
      tester.view.physicalSize =
          const Size(320, 640).testerPhysicalSizeForDpr(2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final AppState state = AppState();
      state.signIn('Manager', asOwner: false, role: 'manager');
      final GoRouter router = _testRouter(state);
      await _pumpShell(tester, state, router);

      expect(find.byType(NavigationDestination), findsNWidgets(4));
    });

    testWidgets('cashier sees only two tabs', (WidgetTester tester) async {
      tester.view.physicalSize =
          const Size(320, 640).testerPhysicalSizeForDpr(2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final AppState state = AppState();
      state.signIn('Cashier', asOwner: false);
      final GoRouter router = _testRouter(state);
      await _pumpShell(tester, state, router);

      expect(find.byType(NavigationDestination), findsNWidgets(2));
      expect(find.text('Inventory'), findsNothing);
      expect(find.text('Analytics'), findsNothing);
      expect(find.text('Settings'), findsNothing);
    });
  });

  group('rail and drawer shells', () {
    testWidgets('medium width exposes a rail with the same destinations',
        (WidgetTester tester) async {
      tester.view.physicalSize =
          const Size(800, 600).testerPhysicalSizeForDpr(2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final AppState state = AppState();
      state.signIn('Test Owner', asOwner: true);
      final GoRouter router = _testRouter(state);
      await _pumpShell(tester, state, router);

      expect(find.byType(Scaffold), findsNWidgets(2));
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      final NavigationRail rail =
          find.byType(NavigationRail).evaluate().first.widget as NavigationRail;
      expect(rail.destinations.length, 5);
      expect(rail.selectedIndex, 0);
      expect(rail.extended, false);
    });

    testWidgets('extra-large width exposes a drawer with the same destinations',
        (WidgetTester tester) async {
      tester.view.physicalSize =
          const Size(1600, 800).testerPhysicalSizeForDpr(2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final AppState state = AppState();
      state.signIn('Test Owner', asOwner: true);
      final GoRouter router = _testRouter(state);
      await _pumpShell(tester, state, router);
      final BuildContext context = tester.element(find.byType(Scaffold).first);
      expect(windowSizeClassOf(context), WindowSizeClass.extraLarge);
      expect(find.byType(Drawer), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(ListTile), findsNWidgets(6));
    });
  });

  group('the body follows the tab', () {
    // The regression this group exists for: the shell once rendered the FIRST
    // StatefulNavigationShell widget go_router built, so the URL and the
    // highlighted tab changed while the body stayed on the dashboard. The old
    // tests only looked at the URL, which is why that shipped.
    testWidgets('every compact tab shows its own screen',
        (WidgetTester tester) async {
      tester.view.physicalSize =
          const Size(320, 640).testerPhysicalSizeForDpr(2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final AppState state = AppState();
      state.signIn('Test Owner', asOwner: true);
      final GoRouter router = _testRouter(state);
      await _pumpShell(tester, state, router);

      expect(_screen('Dashboard'), findsOneWidget);

      const List<String> tabs = <String>[
        'Sell',
        'Inventory',
        'Analytics',
        'Settings',
        'Dashboard',
      ];
      for (final String label in tabs) {
        await tester.tap(find
            .descendant(
              of: find.byType(NavigationBar),
              matching: find.text(label),
            )
            .first);
        await tester.pumpAndSettle();

        expect(_screen(label), findsOneWidget,
            reason: 'tapped $label but its screen is not showing');
        for (final String other in tabs.where((String t) => t != label)) {
          expect(_screen(other), findsNothing,
              reason: 'tapped $label but $other is still on screen');
        }
      }
    });

    testWidgets('the rail switches the body too', (WidgetTester tester) async {
      tester.view.physicalSize =
          const Size(800, 600).testerPhysicalSizeForDpr(2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final AppState state = AppState();
      state.signIn('Test Owner', asOwner: true);
      final GoRouter router = _testRouter(state);
      await _pumpShell(tester, state, router);

      // The collapsed rail shows the short labels: Till is Sell, Stock is
      // Inventory.
      await tester.tap(find
          .descendant(
            of: find.byType(NavigationRail),
            matching: find.text('Till'),
          )
          .first);
      await tester.pumpAndSettle();
      expect(_screen('Sell'), findsOneWidget);
      expect(_screen('Dashboard'), findsNothing);

      await tester.tap(find
          .descendant(
            of: find.byType(NavigationRail),
            matching: find.text('Stock'),
          )
          .first);
      await tester.pumpAndSettle();
      expect(_screen('Inventory'), findsOneWidget);
      expect(_screen('Sell'), findsNothing);
    });

    testWidgets('the wide-screen drawer switches the body too',
        (WidgetTester tester) async {
      tester.view.physicalSize =
          const Size(1600, 800).testerPhysicalSizeForDpr(2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final AppState state = AppState();
      state.signIn('Test Owner', asOwner: true);
      final GoRouter router = _testRouter(state);
      await _pumpShell(tester, state, router);

      await tester.tap(find.widgetWithText(ListTile, 'Analytics'));
      await tester.pumpAndSettle();
      expect(_screen('Analytics'), findsOneWidget);
      expect(_screen('Dashboard'), findsNothing);
    });

    testWidgets('a screen can move the shell with HomeShellTabs.goTo',
        (WidgetTester tester) async {
      tester.view.physicalSize =
          const Size(320, 640).testerPhysicalSizeForDpr(2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final AppState state = AppState();
      state.signIn('Test Owner', asOwner: true);
      final GoRouter router = _testRouter(state);
      await _pumpShell(tester, state, router);

      // What the dashboard's "12 items low" tile does.
      tester
          .element(find.byType(NavigationBar))
          .read<HomeShellTabs>()
          .goTo(AppDestination.inventory);
      await tester.pumpAndSettle();

      expect(_screen('Inventory'), findsOneWidget);
      expect(_screen('Dashboard'), findsNothing);
    });

    testWidgets('goTo is a no-op for a destination the role does not have',
        (WidgetTester tester) async {
      tester.view.physicalSize =
          const Size(320, 640).testerPhysicalSizeForDpr(2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final AppState state = AppState();
      state.signIn('Cashier', asOwner: false);
      final GoRouter router = _testRouter(state);
      await _pumpShell(tester, state, router);

      tester
          .element(find.byType(NavigationBar))
          .read<HomeShellTabs>()
          .goTo(AppDestination.inventory);
      await tester.pumpAndSettle();

      expect(_screen('Dashboard'), findsOneWidget);
      expect(_screen('Inventory'), findsNothing);
    });
  });
}

extension on Size {
  Size testerPhysicalSizeForDpr(double dpr) => this * dpr;
}
