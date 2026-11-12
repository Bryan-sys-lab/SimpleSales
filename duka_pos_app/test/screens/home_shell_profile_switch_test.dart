// Switching profiles must reset the shell to the new profile's exact set of
// destinations — nothing from the old profile may linger, and no destination
// may appear twice.

import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/l10n/generated/app_localizations.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/profile/shop_profile.dart';
import 'package:duka_pos/routing/app_redirect.dart';
import 'package:duka_pos/routing/app_stage_controller.dart';
import 'package:duka_pos/routing/home_shell.dart';
import 'package:duka_pos/routing/routes.dart';
import 'package:duka_pos/routing/shell_nav_bar.dart';
import 'package:duka_pos/services/app_state.dart';
import 'package:duka_pos/services/app_stage.dart';
import 'package:duka_pos/services/live_channel_service.dart';
import 'package:duka_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/harness.dart';

class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Scaffold(
        key: ValueKey<String>('screen-$label'),
        appBar: AppBar(title: Text(label)),
        body: Center(child: Text(label)),
      );
}

Finder _destination(AppDestination destination) => find.descendant(
      of: find.byType(ShellNavBar),
      matching: find.byIcon(destination.icon),
    );

GoRouter _testRouter(AppState state) {
  final _FakeStage stage = _FakeStage(AppStageSnapshot(
    stage: AppStage.ready,
    canManageStock: state.canManageStock,
    isAdmin: state.isAdmin,
    shopProfile: state.shopProfile,
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
        shopProfile: state.shopProfile,
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
                builder: (_, __) => const _PlaceholderScreen(label: 'Dashboard'),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.sell,
                builder: (_, __) => const _PlaceholderScreen(label: 'Sell'),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.inventory,
                builder: (_, __) =>
                    const _PlaceholderScreen(label: 'Inventory'),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.analytics,
                builder: (_, __) =>
                    const _PlaceholderScreen(label: 'Analytics'),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.settings,
                builder: (_, __) => const _PlaceholderScreen(label: 'Settings'),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: Routes.support,
                builder: (_, __) => const _PlaceholderScreen(label: 'Support'),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

class _FakeStage extends ChangeNotifier {
  _FakeStage(this._snapshot);
  final AppStageSnapshot _snapshot;
  AppStageSnapshot get snapshot => _snapshot;
}

Future<void> _pumpShell(
    WidgetTester tester, AppState state, GoRouter router) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<AppState>.value(value: state),
        Provider<GoRouter>.value(value: router),
        ChangeNotifierProvider<LiveChannelService>.value(
            value: LiveChannelService()),
      ],
      child: MaterialApp.router(
        routerConfig: router,
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

  testWidgets(
    'nav bar shows exactly the new profile\'s destinations after a switch',
    (WidgetTester tester) async {
      final AppState state = AppState();
      state.signIn('Test Owner', asOwner: true);
      state.setShopProfile(ShopProfile.duka);

      final visible = visibleDestinations(state);
      expect(
        visible,
        <AppDestination>[
          AppDestination.dashboard,
          AppDestination.inventory,
          AppDestination.sell,
          AppDestination.analytics,
          AppDestination.more,
          AppDestination.support,
        ],
      );

      // Switch to open: inventory is replaced by openBusiness; sell stays.
      state.setShopProfile(ShopProfile.open);
      final after = visibleDestinations(state).toList();
      expect(after, contains(AppDestination.dashboard));
      expect(after, contains(AppDestination.openBusiness));
      expect(after, contains(AppDestination.sell));
      expect(after, isNot(contains(AppDestination.inventory)));
      expect(after.toSet().length, after.length,
          reason: 'a destination appeared twice after the switch: $after');

      // Duka again: inventory returns, openBusiness gone.
      state.setShopProfile(ShopProfile.duka);
      final again = visibleDestinations(state).toList();
      expect(again, contains(AppDestination.inventory));
      expect(again, isNot(contains(AppDestination.openBusiness)));
      expect(again.toSet().length, again.length,
          reason: 'a destination appeared twice after switching back: $again');
    },
  );

  testWidgets(
    'switching profiles clears the nav bar to dashboard only',
    (WidgetTester tester) async {
      tester.useDevice(Device.compact);

      final AppState state = AppState();
      state.signIn('Test Owner', asOwner: true);
      state.setShopProfile(ShopProfile.drinks);
      final GoRouter router = _testRouter(state);
      await _pumpShell(tester, state, router);

      expect(find.byType(ShellNavBar), findsOneWidget);
      expect(_destination(AppDestination.dashboard), findsOneWidget);
      expect(_destination(AppDestination.inventory), findsOneWidget);
      expect(_destination(AppDestination.sell), findsOneWidget);

      // Switch to open: inventory is replaced by openBusiness; sell stays.
      state.setShopProfile(ShopProfile.open);
      await tester.pumpAndSettle();
      expect(_destination(AppDestination.dashboard), findsOneWidget);
      expect(_destination(AppDestination.inventory), findsNothing);
      expect(_destination(AppDestination.openBusiness), findsOneWidget);
      expect(_destination(AppDestination.sell), findsOneWidget);
    },
  );
}
