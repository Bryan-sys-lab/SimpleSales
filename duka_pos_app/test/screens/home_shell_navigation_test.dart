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
import 'package:duka_pos/theme/app_theme.dart';
import 'package:duka_pos/ui/components/support_bubble.dart';
import 'package:duka_pos/routing/shell_nav_bar.dart';
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

/// A destination on the bar, found by its ICON rather than by its word.
///
/// The bar shows the FULL label when the cell is wide enough and the SHORT
/// one when it is not — "Dashboard" on a tablet, "Home" on a 320dp phone —
/// because a word cut to "Dashbo…" is worse than a shorter word that is
/// COMPLETE. The ICON is the destination's identity and does not change with
/// the width of the cell, so it is what a test should look for.
Finder _destination(AppDestination destination) => find.descendant(
      of: find.byType(ShellNavBar),
      matching: find.byIcon(destination.icon),
    );

/// The destination a tab label in this test refers to.
AppDestination _destinationFor(String label) => switch (label) {
      'Dashboard' => AppDestination.dashboard,
      'Sell' => AppDestination.sell,
      'Inventory' => AppDestination.inventory,
      'Analytics' => AppDestination.analytics,
      'Settings' => AppDestination.settings,
      'Support' => AppDestination.support,
      _ => throw ArgumentError.value(label, 'label', 'no such tab'),
    };


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
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.support,
                builder: (BuildContext context, GoRouterState routerState) =>
                    const _PlaceholderScreen(label: 'Support'),
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
        // The app's own theme, not a hand-made one: the shell's components
        // read the theme's extensions, and a hand-made theme renders
        // unstyled.
        theme: buildDukaLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// Taps a destination in the bottom bar.
///
/// The sell button is the BALL, and it carries no text label of its own — it
/// is a mark in a circle — so it is found by what it says.
Future<void> _tapTab(WidgetTester tester, String label) async {
  if (label == 'Sell') {
    final SemanticsHandle handle = tester.ensureSemantics();
    await tester.tap(find.bySemanticsLabel('Sell').first);
    handle.dispose();
  } else {
    // Found by the ICON, not by the word: the bar spells a destination in full
    // when its cell is wide enough and in short form when it is not, and the
    // icon is the same either way. See [_destination].
    await tester.tap(_destination(_destinationFor(label)));
  }
  await tester.pumpAndSettle();
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
    test('owner sees all six tabs', () {
      final AppState state = AppState();
      state.signIn('Owner', asOwner: true);
      final visible = visibleDestinations(state).toList();
      expect(visible.toSet(), equals(AppDestination.values.toSet()));
    });

    test('manager sees five tabs (no Settings)', () {
      final AppState state = AppState();
      state.signIn('Manager', asOwner: false, role: 'manager');
      final visible = visibleDestinations(state).toList();
      // The order is the order the bar shows them in, and the sell button sits
      // in the middle of it.
      expect(visible, <AppDestination>[
        AppDestination.dashboard,
        AppDestination.inventory,
        AppDestination.sell,
        AppDestination.analytics,
        AppDestination.support,
      ]);
    });

    test('cashier sees dashboard, sell and support', () {
      final AppState state = AppState();
      state.signIn('Cashier', asOwner: false);
      final visible = visibleDestinations(state).toList();
      expect(visible, <AppDestination>[
        AppDestination.dashboard,
        AppDestination.sell,
        AppDestination.support,
      ]);
    });
  });

  group('mobile bottom nav', () {
    testWidgets(
        'all six destinations are offered to an owner on a compact screen',
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
      expect(find.byType(ShellNavBar), findsOneWidget);
      // The support left the bar and became the floating bubble, so the bar
      // carries the other five — with the sell button in the middle.
      expect(
        _destination(AppDestination.dashboard),
        findsOneWidget,
      );
      expect(
        _destination(AppDestination.inventory),
        findsOneWidget,
      );
      expect(
        _destination(AppDestination.analytics),
        findsOneWidget,
      );
      expect(
        _destination(AppDestination.settings),
        findsOneWidget,
      );
      expect(find.byType(SupportBubble), findsOneWidget);
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

      // The sell button is the BALL, and it has no text label of its own — it
      // is a mark in a circle. It is found by what it says.
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.tap(find.bySemanticsLabel('Sell').first);
      await tester.pump(const Duration(milliseconds: 50));
      visited.add(location());
      handle.dispose();

      await tester.tap(_destination(AppDestination.inventory));
      await tester.pump(const Duration(milliseconds: 50));
      visited.add(location());

      await tester.tap(_destination(AppDestination.analytics));
      await tester.pump(const Duration(milliseconds: 50));
      visited.add(location());

      await tester.tap(_destination(AppDestination.settings));
      await tester.pump(const Duration(milliseconds: 50));
      visited.add(location());

      final distinct = visited.toSet();
      expect(distinct.length, greaterThanOrEqualTo(3),
          reason: 'expected navigation to change the URL, got $visited');
    });

    testWidgets('manager sees five tabs', (WidgetTester tester) async {
      tester.view.physicalSize =
          const Size(320, 640).testerPhysicalSizeForDpr(2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final AppState state = AppState();
      state.signIn('Manager', asOwner: false, role: 'manager');
      final GoRouter router = _testRouter(state);
      await _pumpShell(tester, state, router);

      // Four in the bar — the support is the bubble.
      expect(find.byType(ShellNavBar), findsOneWidget);
      expect(
        _destination(AppDestination.dashboard),
        findsOneWidget,
      );
      expect(
        _destination(AppDestination.inventory),
        findsOneWidget,
      );
      expect(
        _destination(AppDestination.analytics),
        findsOneWidget,
      );
      expect(
        _destination(AppDestination.settings),
        findsNothing,
      );
    });

    testWidgets('cashier sees three tabs', (WidgetTester tester) async {
      tester.view.physicalSize =
          const Size(320, 640).testerPhysicalSizeForDpr(2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final AppState state = AppState();
      state.signIn('Cashier', asOwner: false);
      final GoRouter router = _testRouter(state);
      await _pumpShell(tester, state, router);

      // Two in the bar: the dashboard and the ball. The support is the bubble.
      expect(find.byType(ShellNavBar), findsOneWidget);
      expect(
        _destination(AppDestination.dashboard),
        findsOneWidget,
      );
      expect(
        _destination(AppDestination.inventory),
        findsNothing,
      );
      expect(
        _destination(AppDestination.analytics),
        findsNothing,
      );
      expect(
        _destination(AppDestination.settings),
        findsNothing,
      );
      expect(find.byType(SupportBubble), findsOneWidget);
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
      expect(find.byType(ShellNavBar), findsNothing);
      final NavigationRail rail =
          find.byType(NavigationRail).evaluate().first.widget as NavigationRail;
      expect(rail.destinations.length, 6);
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
      expect(find.byType(ShellNavBar), findsNothing);
      expect(find.byType(ListTile), findsNWidgets(7));
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
        await _tapTab(tester, label);

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
          .element(find.byType(ShellNavBar))
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
          .element(find.byType(ShellNavBar))
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
